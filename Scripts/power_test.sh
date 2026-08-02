#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MODE="${1:-}"
MIN_SECONDS="${CAFFEINE_TEST_MIN_SECONDS:-30}"
MAX_GAP="${CAFFEINE_TEST_MAX_GAP:-5}"
TEST_URL="${CAFFEINE_TEST_URL:-}"
MIN_NETWORK_SUCCESS="${CAFFEINE_TEST_MIN_NETWORK_SUCCESS:-80}"
ALLOW_COMPETITORS="${CAFFEINE_TEST_ALLOW_COMPETITORS:-0}"

if [[ "$MODE" != "screen" && "$MODE" != "lid" ]]; then
    echo "Usage: $0 <screen|lid>" >&2
    exit 2
fi

for value in "$MIN_SECONDS" "$MAX_GAP" "$MIN_NETWORK_SUCCESS"; do
    [[ "$value" =~ ^[0-9]+$ ]] || { echo "Test limits must be whole numbers." >&2; exit 2; }
done

if [[ "$MODE" == "lid" ]]; then
    "$ROOT/Scripts/check_power_state.sh" --require-closed-lid
else
    "$ROOT/Scripts/check_power_state.sh"
fi

STAMP=$(date -u +"%Y%m%dT%H%M%SZ")
RESULT_DIR="$ROOT/.build/power-tests/$STAMP-$MODE"
SAMPLES="$RESULT_DIR/samples.tsv"
NETWORK="$RESULT_DIR/network.tsv"
SUMMARY="$RESULT_DIR/summary.txt"
METADATA="$RESULT_DIR/metadata.txt"
ASSERTIONS_BEFORE="$RESULT_DIR/assertions-before.txt"
mkdir -p "$RESULT_DIR"

pmset -g assertions > "$ASSERTIONS_BEFORE"
APP_PID=$(pgrep -f "Caffeine.app/Contents/MacOS/Caffeine" | tail -n 1)
if [[ "$MODE" == "screen" ]]; then
    COMPETING_ASSERTIONS=$(grep -E 'pid .* (PreventUserIdleSystemSleep|PreventSystemSleep) named:' "$ASSERTIONS_BEFORE" \
        | grep -Fv "pid $APP_PID(Caffeine):" \
        | grep -Fv 'Powerd - Prevent sleep while display is on' || true)
else
    COMPETING_ASSERTIONS=$(grep -E 'pid .* PreventSystemSleep named:' "$ASSERTIONS_BEFORE" \
        | grep -Fv "pid $APP_PID(Caffeine):" || true)
fi

if [[ -n "$COMPETING_ASSERTIONS" && "$ALLOW_COMPETITORS" != "1" ]]; then
    echo "The test would not isolate Caffeine because another process can also prevent sleep:" >&2
    printf '%s\n' "$COMPETING_ASSERTIONS" >&2
    echo "Stop that process, or set CAFFEINE_TEST_ALLOW_COMPETITORS=1 for a shared test." >&2
    echo "Assertion snapshot: $ASSERTIONS_BEFORE" >&2
    exit 1
fi

{
    echo "mode=$MODE"
    echo "started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "minimum_seconds=$MIN_SECONDS"
    echo "maximum_heartbeat_gap=$MAX_GAP"
    echo "network_probe=$([[ -n "$TEST_URL" ]] && echo enabled || echo disabled)"
    echo "competing_assertions=$([[ -n "$COMPETING_ASSERTIONS" ]] && echo present || echo none)"
    sw_vers
    uname -a
    pmset -g batt
} > "$METADATA"

printf 'epoch\tclamshell\n' > "$SAMPLES"
printf 'epoch\thttp_status\n' > "$NETWORK"

sample_power_state() {
    while true; do
        local epoch clamshell
        epoch=$(date +%s)
        clamshell=$(ioreg -r -k AppleClamshellState -d 4 \
            | awk -F'= ' '/"AppleClamshellState"/ {print $2; exit}')
        printf '%s\t%s\n' "$epoch" "${clamshell:-Unknown}" >> "$SAMPLES"
        sleep 1
    done
}

probe_network() {
    while true; do
        local epoch code
        epoch=$(date +%s)
        if code=$(curl -L -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 4 "$TEST_URL"); then
            :
        else
            code="${code:-000}"
        fi
        printf '%s\t%s\n' "$epoch" "$code" >> "$NETWORK"
        sleep 5
    done
}

sample_power_state &
SAMPLE_PID=$!
NETWORK_PID=""
if [[ -n "$TEST_URL" ]]; then
    probe_network &
    NETWORK_PID=$!
fi

stop_monitors() {
    kill "$SAMPLE_PID" 2>/dev/null || true
    [[ -z "$NETWORK_PID" ]] || kill "$NETWORK_PID" 2>/dev/null || true
    wait "$SAMPLE_PID" 2>/dev/null || true
    [[ -z "$NETWORK_PID" ]] || wait "$NETWORK_PID" 2>/dev/null || true
}
trap stop_monitors EXIT INT TERM

if [[ "$MODE" == "screen" ]]; then
    echo
    echo "This will switch the display off. Leave it off for at least $MIN_SECONDS seconds."
    read -r -p "Press Return when ready. "
    START_EPOCH=$(date +%s)
    pmset displaysleepnow
    read -r -p "After waking the display, press Return to finish. "
else
    echo
    echo "Close the lid after pressing Return. Leave it closed for at least $MIN_SECONDS seconds."
    echo "Reopen it, wait for the desktop, then press Return again."
    read -r -p "Press Return when ready. "
    START_EPOCH=$(date +%s)
    read -r -p "Press Return after reopening the lid. "
fi

END_EPOCH=$(date +%s)
stop_monitors
trap - EXIT INT TERM

read -r SAMPLE_COUNT MAX_SEEN_GAP CLOSED_SAMPLES < <(
    awk -F '\t' -v start="$START_EPOCH" -v end="$END_EPOCH" '
        BEGIN { previous = start; count = 0; gap = 0; closed = 0 }
        $1 ~ /^[0-9]+$/ && $1 >= start && $1 <= end {
            current_gap = $1 - previous
            if (current_gap > gap) gap = current_gap
            previous = $1
            count++
            if ($2 == "Yes") closed++
        }
        END {
            current_gap = end - previous
            if (current_gap > gap) gap = current_gap
            print count, gap, closed
        }
    ' "$SAMPLES")

read -r NETWORK_ATTEMPTS NETWORK_SUCCESSES < <(
    awk -F '\t' -v start="$START_EPOCH" -v end="$END_EPOCH" '
        $1 ~ /^[0-9]+$/ && $1 >= start && $1 <= end {
            attempts++
            if ($2 >= 200 && $2 < 400) successes++
        }
        END { print attempts + 0, successes + 0 }
    ' "$NETWORK")

ELAPSED=$((END_EPOCH - START_EPOCH))
RESULT="PASS"
NETWORK_PERCENT=0
if [[ "$NETWORK_ATTEMPTS" -gt 0 ]]; then
    NETWORK_PERCENT=$((NETWORK_SUCCESSES * 100 / NETWORK_ATTEMPTS))
fi
if [[ "$ELAPSED" -lt "$MIN_SECONDS" || "$MAX_SEEN_GAP" -gt "$MAX_GAP" ]]; then
    RESULT="FAIL"
fi
if [[ "$MODE" == "lid" && "$CLOSED_SAMPLES" -eq 0 ]]; then
    RESULT="FAIL"
fi
if [[ -n "$TEST_URL" && "$NETWORK_PERCENT" -lt "$MIN_NETWORK_SUCCESS" ]]; then
    RESULT="FAIL"
fi

{
    echo "Caffeine $MODE power test"
    echo "Elapsed: ${ELAPSED}s"
    echo "Heartbeat samples: $SAMPLE_COUNT"
    echo "Largest scheduling gap: ${MAX_SEEN_GAP}s"

    if [[ "$ELAPSED" -lt "$MIN_SECONDS" ]]; then
        echo "FAIL: The test ran for less than ${MIN_SECONDS}s."
    fi
    if [[ "$MAX_SEEN_GAP" -gt "$MAX_GAP" ]]; then
        echo "FAIL: The Mac stopped scheduling work for ${MAX_SEEN_GAP}s."
    else
        echo "PASS: Work kept running without a sleep-sized gap."
    fi

    if [[ "$MODE" == "lid" ]]; then
        echo "Closed-lid samples: $CLOSED_SAMPLES"
        if [[ "$CLOSED_SAMPLES" -eq 0 ]]; then
            echo "FAIL: The monitor never observed a closed lid."
        fi
    fi

    if [[ -n "$TEST_URL" ]]; then
        echo "Network probes: $NETWORK_SUCCESSES/$NETWORK_ATTEMPTS (${NETWORK_PERCENT}%)"
        if [[ "$NETWORK_PERCENT" -lt "$MIN_NETWORK_SUCCESS" ]]; then
            echo "FAIL: Network success was below ${MIN_NETWORK_SUCCESS}%."
        fi
    else
        echo "Network probes: disabled"
    fi

    if [[ -n "$COMPETING_ASSERTIONS" ]]; then
        echo "Evidence: shared with another sleep-prevention process"
    else
        echo "Evidence: isolated to Caffeine"
    fi

    if [[ "$RESULT" == "PASS" ]]; then
        echo "Result: PASS"
    else
        echo "Result: FAIL"
    fi
} > "$SUMMARY"

cat "$SUMMARY"

echo "Logs: $RESULT_DIR"

if [[ "$MODE" == "lid" ]]; then
    "$ROOT/Scripts/check_power_state.sh" --require-closed-lid
else
    "$ROOT/Scripts/check_power_state.sh"
fi

[[ "$RESULT" == "PASS" ]]

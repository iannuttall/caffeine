#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/Scripts/config.env"

REQUIRE_CLOSED_LID=0
if [[ "${1:-}" == "--require-closed-lid" ]]; then
    REQUIRE_CLOSED_LID=1
elif [[ $# -gt 0 ]]; then
    echo "Usage: $0 [--require-closed-lid]" >&2
    exit 2
fi

DOMAIN="com.iannuttall.caffeine.shared"
PATTERN="$APP_NAME.app/Contents/MacOS/$APP_NAME"
APP_PID=$(pgrep -f "$PATTERN" | tail -n 1 || true)

if [[ -z "$APP_PID" ]]; then
    echo "FAIL: Caffeine is not running from an app bundle." >&2
    exit 1
fi

STATUS_ACTIVE=$(defaults read "$DOMAIN" statusActive 2>/dev/null || printf '0')
if [[ "$STATUS_ACTIVE" != "1" ]]; then
    echo "FAIL: Caffeine is running but not active. Turn the cup on first." >&2
    exit 1
fi

read_setting() {
    local key="$1" fallback="$2" value
    value=$(defaults read "$DOMAIN" "$key" 2>/dev/null || printf '%s' "$fallback")
    [[ "$value" == "1" ]] && printf '1' || printf '0'
}

ALLOW_DISPLAY_SLEEP=$(read_setting allowDisplaySleep 0)
KEEP_NETWORK_ACTIVE=$(read_setting keepNetworkActive 1)
CLOSED_LID_MODE=$(read_setting closedLidMode 0)

ASSERTIONS=$(pmset -g assertions)
OWNER_LINES=$(printf '%s\n' "$ASSERTIONS" | grep -F "pid $APP_PID($APP_NAME):" || true)
FAILURES=0

require_assertion() {
    local name="$1"
    if printf '%s\n' "$OWNER_LINES" | grep -Fq "$name"; then
        echo "PASS: $name"
    else
        echo "FAIL: Caffeine does not own $name" >&2
        FAILURES=$((FAILURES + 1))
    fi
}

reject_assertion() {
    local name="$1"
    if printf '%s\n' "$OWNER_LINES" | grep -Fq "$name"; then
        echo "FAIL: Caffeine owns unexpected $name" >&2
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $name is disabled as configured"
    fi
}

echo "Caffeine pid: $APP_PID"
require_assertion "PreventUserIdleSystemSleep"

if [[ "$ALLOW_DISPLAY_SLEEP" == "1" ]]; then
    reject_assertion "PreventUserIdleDisplaySleep"
else
    require_assertion "PreventUserIdleDisplaySleep"
fi

if [[ "$KEEP_NETWORK_ACTIVE" == "1" ]]; then
    require_assertion "NetworkClientActive"
else
    reject_assertion "NetworkClientActive"
fi

if [[ "$REQUIRE_CLOSED_LID" == "1" && "$CLOSED_LID_MODE" != "1" ]]; then
    echo "FAIL: Turn on closed-lid mode in Caffeine settings first." >&2
    FAILURES=$((FAILURES + 1))
elif [[ "$CLOSED_LID_MODE" == "1" ]]; then
    require_assertion "PreventSystemSleep"
else
    reject_assertion "PreventSystemSleep"
fi

if [[ "$FAILURES" -gt 0 ]]; then
    echo "Power assertion check failed with $FAILURES problem(s)." >&2
    exit 1
fi

echo "Power assertions match the current Caffeine settings."

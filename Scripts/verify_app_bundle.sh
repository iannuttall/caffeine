#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
source "$ROOT/Scripts/config.env"

RESOURCE_BUNDLE_NAME="Caffeine_Caffeine.bundle"
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "ERROR: Quit every running copy of $APP_NAME before running the package check." >&2
    exit 1
fi
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/caffeine-package-check.XXXXXX")
LAUNCH_PID=""
cleanup() {
    if [[ -n "$LAUNCH_PID" ]] && kill -0 "$LAUNCH_PID" 2>/dev/null; then
        kill "$LAUNCH_PID" 2>/dev/null || true
        wait "$LAUNCH_PID" 2>/dev/null || true
    fi
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TEMP_DIR/build"
if [[ $# -gt 0 ]]; then
    APP=$1
else
    for cachedItem in artifacts checkouts repositories workspace-state.json; do
        if [[ -e "$ROOT/.build/$cachedItem" ]]; then
            cp -cR "$ROOT/.build/$cachedItem" "$TEMP_DIR/build/$cachedItem"
        fi
    done
    if ! CAFFEINE_ADHOC_SIGN=1 \
        CAFFEINE_PACKAGE_DIR="$TEMP_DIR/package" \
        CAFFEINE_SWIFT_SCRATCH_PATH="$TEMP_DIR/build" \
        "$ROOT/Scripts/package_app.sh" release >"$TEMP_DIR/package.log" 2>&1; then
        echo "ERROR: Failed to build the package-check app." >&2
        sed -n '1,160p' "$TEMP_DIR/package.log" >&2
        exit 1
    fi
    APP=$(tail -n1 "$TEMP_DIR/package.log")
fi

[[ -n "$APP" && -d "$APP" ]] || { echo "ERROR: App bundle not found: ${APP:-<empty path>}" >&2; exit 1; }
APP=$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")
RESOURCE_BUNDLE="$APP/Contents/Resources/$RESOURCE_BUNDLE_NAME"
EXECUTABLE="$APP/Contents/MacOS/$APP_NAME"

[[ -x "$EXECUTABLE" ]] || { echo "ERROR: App executable not found: $EXECUTABLE" >&2; exit 1; }
[[ -d "$RESOURCE_BUNDLE" ]] || {
    echo "ERROR: Missing packaged resource bundle: $RESOURCE_BUNDLE" >&2
    exit 1
}
[[ ! -e "$APP/$RESOURCE_BUNDLE_NAME" ]] || {
    echo "ERROR: Resource bundle must not be placed at the application root." >&2
    exit 1
}

for resource in active.png active@2x.png inactive.png inactive@2x.png Cup.png; do
    path="$RESOURCE_BUNDLE/$resource"
    [[ -f "$path" ]] || { echo "ERROR: Missing packaged image: $resource" >&2; exit 1; }
    sips -g pixelWidth -g pixelHeight "$path" >/dev/null
done

codesign --verify --deep --strict --verbose=2 "$APP"

hiddenBundleCount=0
while IFS= read -r -d '' bundle; do
    mv "$bundle" "$TEMP_DIR/hidden-$hiddenBundleCount-$RESOURCE_BUNDLE_NAME"
    hiddenBundleCount=$((hiddenBundleCount + 1))
done < <(find "$TEMP_DIR/build" -type d -name "$RESOURCE_BUNDLE_NAME" -print0)

"$EXECUTABLE" >"$TEMP_DIR/launch.log" 2>&1 &
LAUNCH_PID=$!
sleep 5
if ! kill -0 "$LAUNCH_PID" 2>/dev/null; then
    wait "$LAUNCH_PID" 2>/dev/null || true
    LAUNCH_PID=""
    echo "ERROR: The packaged app exited during its isolated launch check." >&2
    sed -n '1,120p' "$TEMP_DIR/launch.log" >&2
    exit 1
fi

kill "$LAUNCH_PID"
wait "$LAUNCH_PID" 2>/dev/null || true
LAUNCH_PID=""
echo "OK: Packaged resources load, the app stays running, and strict signature verification passes."

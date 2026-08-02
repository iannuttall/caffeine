#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/Scripts/config.env"
PATTERN="$APP_NAME.app/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" 2>/dev/null || true
pkill -f "$PATTERN" 2>/dev/null || true
APP=$("$ROOT/Scripts/package_app.sh" debug | tail -n1)
OPEN_ARGS=(-n -g)
if [[ -n "${CAFFEINE_OPEN_ON_LAUNCH:-}" ]]; then
    OPEN_ARGS+=(--env "CAFFEINE_OPEN_ON_LAUNCH=$CAFFEINE_OPEN_ON_LAUNCH")
fi
open "${OPEN_ARGS[@]}" "$APP"

for _ in {1..15}; do
    if pgrep -f "$PATTERN" >/dev/null 2>&1; then
        echo "OK: $APP_NAME is running from $APP"
        exit 0
    fi
    sleep 0.4
done
echo "ERROR: $APP_NAME exited during launch." >&2
exit 1

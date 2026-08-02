#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/Scripts/config.env"
APP=$("$ROOT/Scripts/package_app.sh" debug | tail -n1)
DESTINATION="/Applications/$APP_NAME.app"

pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$DESTINATION"
ditto "$APP" "$DESTINATION"
xattr -cr "$DESTINATION"
mkdir -p "$HOME/.local/bin"
install -m 755 "$DESTINATION/Contents/MacOS/caffeinecli" "$HOME/.local/bin/caffeine"
open -g "$DESTINATION"
echo "$DESTINATION"

#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
ZIP=${1:?"usage: $0 <path-to-signed-zip>"}
[[ -f "$ZIP" ]] || { echo "ERROR: zip not found: $ZIP" >&2; exit 1; }

source "$ROOT/version.env"
source "$ROOT/Scripts/config.env"
APP_CONFIG_ENV=$(node "$ROOT/Scripts/lib/app_config.mjs" env "$ROOT/app.config.json")
source <(printf '%s\n' "$APP_CONFIG_ENV")
source "$ROOT/Scripts/sparkle_paths.sh"
: "${SPARKLE_PRIVATE_KEY_PATH:?Set SPARKLE_PRIVATE_KEY_PATH to the Sparkle EdDSA private key}"

"$ROOT/Scripts/validate_changelog.sh"
SIGN_UPDATE=$(sparkle_find_tool sign_update "$ROOT")
SIGN_OUTPUT=$("$SIGN_UPDATE" "$ZIP" -f "$SPARKLE_PRIVATE_KEY_PATH")
ED_SIGNATURE=$(printf '%s' "$SIGN_OUTPUT" | sed -E 's/.*edSignature="([^"]+)".*/\1/')
ZIP_LENGTH=$(stat -f%z "$ZIP")
ZIP_NAME=$(basename "$ZIP")
DOWNLOAD_URL="${DOWNLOAD_URL_PREFIX%/}/v${MARKETING_VERSION}/${ZIP_NAME}"
PUB_DATE=$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')

APPCAST="$ROOT/appcast.xml" \
CHANGELOG="$ROOT/CHANGELOG.md" \
VERSION="$MARKETING_VERSION" \
BUILD="$BUILD_NUMBER" \
MIN_MACOS="$MIN_MACOS" \
DOWNLOAD_URL="$DOWNLOAD_URL" \
ED_SIGNATURE="$ED_SIGNATURE" \
ZIP_LENGTH="$ZIP_LENGTH" \
PUB_DATE="$PUB_DATE" \
    node "$ROOT/Scripts/lib/appcast_update.mjs"
echo "Updated appcast.xml for $MARKETING_VERSION"

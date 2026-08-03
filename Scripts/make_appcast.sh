#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
ARTIFACT=${1:?"usage: $0 <path-to-signed-artifact>"}
[[ -f "$ARTIFACT" ]] || { echo "ERROR: artifact not found: $ARTIFACT" >&2; exit 1; }

source "$ROOT/version.env"
source "$ROOT/Scripts/config.env"
APP_CONFIG_ENV=$(node "$ROOT/Scripts/lib/app_config.mjs" env "$ROOT/app.config.json")
source <(printf '%s\n' "$APP_CONFIG_ENV")
source "$ROOT/Scripts/sparkle_paths.sh"
: "${SPARKLE_PRIVATE_KEY_PATH:?Set SPARKLE_PRIVATE_KEY_PATH to the Sparkle EdDSA private key}"
[[ -f "$SPARKLE_PRIVATE_KEY_PATH" ]] || {
    echo "ERROR: Sparkle private key not found: $SPARKLE_PRIVATE_KEY_PATH" >&2
    exit 1
}

"$ROOT/Scripts/validate_changelog.sh"
SIGN_UPDATE=$(sparkle_find_tool sign_update "$ROOT")
SIGN_OUTPUT=$("$SIGN_UPDATE" "$ARTIFACT" -f "$SPARKLE_PRIVATE_KEY_PATH")
ED_SIGNATURE=$(printf '%s' "$SIGN_OUTPUT" | sed -nE 's/.*edSignature="([^"]+)".*/\1/p')
[[ -n "$ED_SIGNATURE" ]] || {
    echo "ERROR: Could not parse the Sparkle signature." >&2
    exit 1
}
ARTIFACT_LENGTH=$(stat -f%z "$ARTIFACT")
ARTIFACT_NAME=$(basename "$ARTIFACT")
DOWNLOAD_URL="${DOWNLOAD_URL_PREFIX%/}/v${MARKETING_VERSION}/${ARTIFACT_NAME}"
PUB_DATE=$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')

APPCAST="$ROOT/appcast.xml" \
CHANGELOG="$ROOT/CHANGELOG.md" \
VERSION="$MARKETING_VERSION" \
BUILD="$BUILD_NUMBER" \
MIN_MACOS="$MIN_MACOS" \
DOWNLOAD_URL="$DOWNLOAD_URL" \
ED_SIGNATURE="$ED_SIGNATURE" \
ARTIFACT_LENGTH="$ARTIFACT_LENGTH" \
PUB_DATE="$PUB_DATE" \
    node "$ROOT/Scripts/lib/appcast_update.mjs"
echo "Updated appcast.xml for $MARKETING_VERSION"

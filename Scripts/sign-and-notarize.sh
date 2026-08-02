#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"
source "$ROOT/Scripts/config.env"
source "$ROOT/Scripts/sparkle_paths.sh"

"$ROOT/Scripts/validate_changelog.sh"

: "${APP_IDENTITY:?Set APP_IDENTITY to a Developer ID Application identity}"
: "${ASC_KEY_ID:?Set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
: "${ASC_KEY_PATH:?Set ASC_KEY_PATH to the App Store Connect .p8 key}"

APP=$("$ROOT/Scripts/package_app.sh" release | tail -n1)
SIGN=(codesign --force --timestamp --options runtime --sign "$APP_IDENTITY")
if [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]]; then
    while IFS= read -r target; do "${SIGN[@]}" "$target"; done < <(sparkle_signing_targets "$APP/Contents/Frameworks/Sparkle.framework")
fi
"${SIGN[@]}" "$APP/Contents/MacOS/caffeinecli"
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"

ARTIFACTS="$ROOT/.build/artifacts"
mkdir -p "$ARTIFACTS"
SUBMISSION="$ARTIFACTS/Caffeine-notarize.zip"
FINAL="$ARTIFACTS/Caffeine-$MARKETING_VERSION-universal.zip"
rm -f "$SUBMISSION" "$FINAL"
ditto --norsrc -c -k --keepParent "$APP" "$SUBMISSION"
xcrun notarytool submit "$SUBMISSION" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
xcrun stapler staple "$APP"
spctl -a -t exec -vv "$APP"
ditto --norsrc -c -k --keepParent "$APP" "$FINAL"
rm -f "$SUBMISSION"
echo "$FINAL"

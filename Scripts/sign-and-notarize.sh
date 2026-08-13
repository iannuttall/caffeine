#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"
source "$ROOT/Scripts/config.env"
if command -v node >/dev/null 2>&1; then
    APP_CONFIG_ENV=$(node "$ROOT/Scripts/lib/app_config.mjs" env "$ROOT/app.config.json")
    source <(printf '%s\n' "$APP_CONFIG_ENV")
fi
source "$ROOT/Scripts/sparkle_paths.sh"

"$ROOT/Scripts/validate_changelog.sh"

: "${APP_IDENTITY:?Set APP_IDENTITY to a Developer ID Application identity}"
: "${ASC_KEY_ID:?Set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
: "${ASC_KEY_PATH:?Set ASC_KEY_PATH to the App Store Connect .p8 key}"
[[ -f "$ASC_KEY_PATH" ]] || { echo "ERROR: App Store Connect key not found: $ASC_KEY_PATH" >&2; exit 1; }
[[ -n "$SPARKLE_PUBLIC_KEY" ]] || { echo "ERROR: Set the Sparkle public key before release." >&2; exit 1; }
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "ERROR: Quit every running copy of $APP_NAME before making a release." >&2
    exit 1
fi

APP=$("$ROOT/Scripts/package_app.sh" release | tail -n1)
SIGN=(codesign --force --timestamp --options runtime --sign "$APP_IDENTITY")
if [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]]; then
    while IFS= read -r target; do "${SIGN[@]}" "$target"; done < <(sparkle_signing_targets "$APP/Contents/Frameworks/Sparkle.framework")
fi
"${SIGN[@]}" "$APP/Contents/MacOS/caffeinecli"
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"
SIGN_INFO=$(codesign -d --verbose=2 "$APP" 2>&1 || true)
[[ "$SIGN_INFO" == *"flags="*"runtime"* ]] || {
    echo "ERROR: Hardened runtime is missing from the signed app." >&2
    exit 1
}

LAUNCH_PID=""
cleanup_launch() {
    if [[ -n "$LAUNCH_PID" ]] && kill -0 "$LAUNCH_PID" 2>/dev/null; then
        kill "$LAUNCH_PID" 2>/dev/null || true
    fi
}
trap cleanup_launch EXIT
"$APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 &
LAUNCH_PID=$!
sleep 5
if kill -0 "$LAUNCH_PID" 2>/dev/null; then
    kill "$LAUNCH_PID"
    wait "$LAUNCH_PID" 2>/dev/null || true
    LAUNCH_PID=""
else
    wait "$LAUNCH_PID" 2>/dev/null || true
    echo "ERROR: The signed app exited during its launch check." >&2
    exit 1
fi

ARTIFACTS="$ROOT/.build/artifacts"
mkdir -p "$ARTIFACTS"
DMG="$ARTIFACTS/Caffeine-$MARKETING_VERSION.dmg"
CHECKSUM="$DMG.sha256"
"$ROOT/Scripts/build_dmg.sh" "$APP" "$DMG" >/dev/null
codesign --force --timestamp --sign "$APP_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

SHA256=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
printf '%s  %s\n' "$SHA256" "$(basename "$DMG")" > "$CHECKSUM"

TAG="v$MARKETING_VERSION"
if command -v gh >/dev/null 2>&1; then
    if gh release view "$TAG" --json isDraft >/dev/null 2>&1; then
        existing_draft=$(gh release view "$TAG" --json isDraft -q '.isDraft')
        if [[ "$existing_draft" == "true" ]]; then
            gh release upload "$TAG" "$DMG" "$CHECKSUM" --clobber
            echo "Updated draft release $TAG with new assets."
        else
            echo "warning: $TAG is already published; not overwriting." >&2
        fi
    else
        gh release create "$TAG" "$DMG" "$CHECKSUM" \
            --draft \
            --title "$APP_NAME $MARKETING_VERSION" \
            --generate-notes
        echo "Created draft release $TAG."
    fi
else
    echo "warning: gh CLI not available; create the GitHub draft release manually." >&2
fi

echo "$DMG"
echo "$CHECKSUM"

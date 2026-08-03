#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
CONF=$(printf '%s' "${1:-release}" | tr '[:upper:]' '[:lower:]')
[[ "$CONF" == "debug" || "$CONF" == "release" ]] || { echo "Expected debug or release" >&2; exit 2; }

source "$ROOT/version.env"
source "$ROOT/Scripts/config.env"
if command -v node >/dev/null 2>&1; then
    APP_CONFIG_ENV=$(node "$ROOT/Scripts/lib/app_config.mjs" env "$ROOT/app.config.json")
    source <(printf '%s\n' "$APP_CONFIG_ENV")
fi
source "$ROOT/Scripts/sparkle_paths.sh"

CLI_NAME=caffeinecli
if [[ "$CONF" == "release" ]]; then
    ARCH_LIST=(arm64 x86_64)
else
    ARCH_LIST=("$(uname -m)")
fi

STAGE="$ROOT/.build/package-products/$CONF"
rm -rf "$STAGE"
for ARCH in "${ARCH_LIST[@]}"; do
    swift build -c "$CONF" --arch "$ARCH"
    BIN_DIR=$(swift build -c "$CONF" --arch "$ARCH" --show-bin-path)
    mkdir -p "$STAGE/$ARCH"
    cp "$BIN_DIR/$APP_NAME" "$STAGE/$ARCH/$APP_NAME"
    cp "$BIN_DIR/$CLI_NAME" "$STAGE/$ARCH/$CLI_NAME"
done
PREFERRED_BIN_DIR=$(swift build -c "$CONF" --arch "${ARCH_LIST[0]}" --show-bin-path)

APP="$ROOT/.build/package/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

install_binary() {
    local name="$1" destination="$2" sources=() arch
    for arch in "${ARCH_LIST[@]}"; do sources+=("$STAGE/$arch/$name"); done
    if [[ ${#sources[@]} -gt 1 ]]; then lipo -create "${sources[@]}" -output "$destination"; else cp "${sources[0]}" "$destination"; fi
    chmod +x "$destination"
}
install_binary "$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
install_binary "$CLI_NAME" "$APP/Contents/MacOS/$CLI_NAME"

shopt -s nullglob
for bundle in "$PREFERRED_BIN_DIR"/*.bundle; do cp -R "$bundle" "$APP/Contents/Resources/"; done
shopt -u nullglob

ICON_ENTRY=""
if [[ -d "$ROOT/Resources/AppIcon.icon" ]]; then
    ICON_OUTPUT="$ROOT/.build/icon"
    rm -rf "$ICON_OUTPUT"
    mkdir -p "$ICON_OUTPUT"
    if xcrun actool "$ROOT/Resources/AppIcon.icon" \
        --compile "$ICON_OUTPUT" \
        --platform macosx \
        --minimum-deployment-target "$MIN_MACOS" \
        --app-icon AppIcon \
        --output-partial-info-plist "$ICON_OUTPUT/partial.plist" \
        --errors --warnings; then
        [[ -f "$ICON_OUTPUT/Assets.car" ]] && cp "$ICON_OUTPUT/Assets.car" "$APP/Contents/Resources/Assets.car"
        [[ -f "$ICON_OUTPUT/AppIcon.icns" ]] && cp "$ICON_OUTPUT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
        ICON_ENTRY='<key>CFBundleIconFile</key><string>AppIcon</string><key>CFBundleIconName</key><string>AppIcon</string>'
    else
        echo "ERROR: Failed to compile the original Caffeine app icon." >&2
        exit 1
    fi
fi

SPARKLE_SRC="$PREFERRED_BIN_DIR/Sparkle.framework"
if [[ -d "$SPARKLE_SRC" ]]; then
    cp -R "$SPARKLE_SRC" "$APP/Contents/Frameworks/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
fi

FEED_VALUE=""
KEY_VALUE=""
if [[ "$CONF" == "release" && -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
    FEED_VALUE="$FEED_URL"
    KEY_VALUE="$SPARKLE_PUBLIC_KEY"
fi
BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>$APP_DISPLAY</string>
<key>CFBundleDisplayName</key><string>$APP_DISPLAY</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
$ICON_ENTRY
<key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
<key>LSUIElement</key><true/>
<key>LSMultipleInstancesProhibited</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>BuildTimestamp</key><string>$BUILD_TIMESTAMP</string>
<key>GitCommit</key><string>$GIT_COMMIT</string>
<key>SUFeedURL</key><string>$FEED_VALUE</string>
<key>SUPublicEDKey</key><string>$KEY_VALUE</string>
<key>SUEnableAutomaticChecks</key><false/>
</dict></plist>
PLIST

xattr -cr "$APP"
if [[ "$CONF" == "debug" ]]; then
    if [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]]; then
        while IFS= read -r target; do codesign --force --sign - "$target" || true; done < <(sparkle_signing_targets "$APP/Contents/Frameworks/Sparkle.framework")
    fi
    codesign --force --sign - "$APP/Contents/MacOS/$CLI_NAME"
    codesign --force --sign - --deep "$APP"
fi

if [[ "$CONF" == "release" ]]; then
    verify_universal() {
        local target="$1" architectures
        architectures=$(lipo -archs "$target")
        [[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] || {
            echo "ERROR: Expected a universal binary at $target, found: $architectures" >&2
            exit 1
        }
    }

    verify_universal "$APP/Contents/MacOS/$APP_NAME"
    verify_universal "$APP/Contents/MacOS/$CLI_NAME"
    if [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]]; then
        while IFS= read -r -d '' target; do
            if file "$target" | grep -q 'Mach-O'; then verify_universal "$target"; fi
        done < <(find "$APP/Contents/Frameworks/Sparkle.framework" -type f -perm -111 -print0)
    fi
fi
echo "$APP"

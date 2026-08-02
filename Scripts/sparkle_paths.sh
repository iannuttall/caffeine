#!/usr/bin/env bash

sparkle_find_tool() {
    local tool="$1"
    local root="${2:-$PWD}"
    local candidate
    candidate=$(find "$root/.build/artifacts" -type f -name "$tool" -perm -u+x 2>/dev/null | head -n1 || true)
    [[ -n "$candidate" ]] || { echo "ERROR: Sparkle tool '$tool' was not found." >&2; return 1; }
    printf '%s\n' "$candidate"
}

sparkle_signing_targets() {
    local sparkle="$1"
    local version_dir
    version_dir=$(cd "$sparkle/Versions/Current" && pwd -P)
    local candidates=(
        "$version_dir/Autoupdate"
        "$version_dir/Updater.app/Contents/MacOS/Updater"
        "$version_dir/Updater.app"
        "$version_dir/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
        "$version_dir/XPCServices/Downloader.xpc"
        "$version_dir/XPCServices/Installer.xpc/Contents/MacOS/Installer"
        "$version_dir/XPCServices/Installer.xpc"
        "$version_dir/Sparkle"
        "$sparkle"
    )
    local path
    for path in "${candidates[@]}"; do [[ -e "$path" ]] && printf '%s\n' "$path"; done
}

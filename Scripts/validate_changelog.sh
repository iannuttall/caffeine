#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/version.env"
TOP=$(grep '^## ' "$ROOT/CHANGELOG.md" | head -n1 | sed 's/^##[[:space:]]*//')

[[ -n "$TOP" ]] || { echo "ERROR: CHANGELOG.md has no version section." >&2; exit 1; }
TOP_VERSION=$(printf '%s' "$TOP" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
[[ "$TOP_VERSION" == "$MARKETING_VERSION" ]] || {
    echo "ERROR: Changelog version $TOP_VERSION does not match $MARKETING_VERSION." >&2
    exit 1
}
printf '%s' "$TOP" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || {
    echo "ERROR: Changelog version must include a YYYY-MM-DD date." >&2
    exit 1
}
echo "Changelog OK for $MARKETING_VERSION"

#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

case "${1:-lint}" in
    lint)
        command -v swiftformat >/dev/null || { echo "ERROR: swiftformat is not installed." >&2; exit 1; }
        command -v swiftlint >/dev/null || { echo "ERROR: swiftlint is not installed." >&2; exit 1; }
        swiftformat Sources Tests --lint
        swiftlint --strict
        ;;
    format)
        command -v swiftformat >/dev/null || { echo "ERROR: swiftformat is not installed." >&2; exit 1; }
        swiftformat Sources Tests
        ;;
    *)
        echo "Usage: $(basename "$0") [lint|format]" >&2
        exit 2
        ;;
esac

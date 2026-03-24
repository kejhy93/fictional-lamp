#!/usr/bin/env bash
set -euo pipefail

TAPE="demo.tape"
OUT="demo.gif"

# Check dependencies
missing=()
for cmd in vhs ffmpeg ttyd; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
done
if (( ${#missing[@]} > 0 )); then
    echo "Missing dependencies: ${missing[*]}"
    echo ""
    echo "Install on Fedora/RHEL:"
    echo "  sudo dnf install ffmpeg"
    echo "  # ttyd: https://github.com/tsl0922/ttyd/releases"
    echo "  # vhs:  https://github.com/charmbracelet/vhs/releases"
    echo ""
    echo "Install on macOS:"
    echo "  brew install vhs ffmpeg ttyd"
    exit 1
fi

echo "Recording $TAPE -> $OUT ..."
vhs "$TAPE"
echo "Done: $OUT"

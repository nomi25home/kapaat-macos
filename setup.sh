#!/usr/bin/env bash
# setup.sh — one-time: create a Python venv in the kapaat repo and install deps.
# Usage (from kapaat-macos/):
#   ./setup.sh ../kapaat          # explicit path
#   ./setup.sh                    # defaults to ../kapaat (sibling directory)
set -euo pipefail

KAPAAT_DIR="${1:-../kapaat}"

# Resolve to an absolute path so error messages are unambiguous
KAPAAT_DIR="$(cd "$KAPAAT_DIR" 2>/dev/null && pwd)" || {
    echo "Error: directory not found: ${1:-../kapaat}"
    exit 1
}

if [ ! -f "$KAPAAT_DIR/app.py" ]; then
    echo "Error: app.py not found in $KAPAAT_DIR"
    echo "Usage: ./setup.sh /path/to/kapaat"
    exit 1
fi

echo "→ Creating Python venv at $KAPAAT_DIR/.venv ..."
python3 -m venv "$KAPAAT_DIR/.venv"

echo "→ Installing dependencies..."
"$KAPAAT_DIR/.venv/bin/pip" install --upgrade pip --quiet
"$KAPAAT_DIR/.venv/bin/pip" install -r "$KAPAAT_DIR/requirements.txt" --quiet

echo ""
echo "✓ Setup complete."
echo ""
echo "Now build the macOS app:"
echo "  ./build.sh"
echo ""
echo "Then launch:"
echo "  open build/Kapaat.app"

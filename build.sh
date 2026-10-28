#!/usr/bin/env bash
# build.sh — compile and assemble Kapaat.app
# Run from this directory: ./build.sh
# Requires: Xcode Command Line Tools (xcode-select --install)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Kapaat"
BUNDLE="$SCRIPT_DIR/build/$APP_NAME.app"
SVG="$SCRIPT_DIR/Sources/Kapaat/AppIcon.svg"

# ── Clean ────────────────────────────────────────────────────────────────────
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

# ── Compile ──────────────────────────────────────────────────────────────────
echo "→ Compiling Swift sources…"
SOURCES=("$SCRIPT_DIR"/Sources/Kapaat/*.swift)
swiftc "${SOURCES[@]}" \
    -framework AppKit \
    -framework WebKit \
    -framework SwiftUI \
    -framework Security \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -parse-as-library \
    -o "$BUNDLE/Contents/MacOS/$APP_NAME"

echo "→ Attempting universal (arm64 + x86_64) binary…"
ARM_BIN="$BUNDLE/Contents/MacOS/${APP_NAME}_arm64"
X86_BIN="$BUNDLE/Contents/MacOS/${APP_NAME}_x86_64"

swiftc "${SOURCES[@]}" \
    -framework AppKit -framework WebKit -framework SwiftUI -framework Security \
    -target "arm64-apple-macosx13.0" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -parse-as-library \
    -o "$ARM_BIN" 2>/dev/null || true

swiftc "${SOURCES[@]}" \
    -framework AppKit -framework WebKit -framework SwiftUI -framework Security \
    -target "x86_64-apple-macosx13.0" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -parse-as-library \
    -o "$X86_BIN" 2>/dev/null || true

if [ -f "$ARM_BIN" ] && [ -f "$X86_BIN" ]; then
    lipo -create "$ARM_BIN" "$X86_BIN" -output "$BUNDLE/Contents/MacOS/$APP_NAME"
    rm "$ARM_BIN" "$X86_BIN"
    echo "   Universal binary created."
else
    rm -f "$ARM_BIN" "$X86_BIN"
fi

# ── Bundle metadata ──────────────────────────────────────────────────────────
echo "→ Writing Info.plist…"
cp "$SCRIPT_DIR/Info.plist" "$BUNDLE/Contents/Info.plist"

# ── Icon ─────────────────────────────────────────────────────────────────────
echo "→ Generating AppIcon.icns from SVG…"
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

svg_to_png() {
    local size=$1 dest=$2
    # qlmanage is built into macOS — no extra dependencies needed
    if qlmanage -t -s "$size" -o "$(dirname "$dest")" "$SVG" &>/dev/null; then
        local produced
        produced="$(dirname "$dest")/$(basename "$SVG").png"
        [ -f "$produced" ] && mv "$produced" "$dest"
    fi
}

for size in 16 32 64 128 256 512 1024; do
    svg_to_png "$size" "$ICONSET_DIR/icon_${size}x${size}.png"
    # @2x entries (retina)
    [ -f "$ICONSET_DIR/icon_${size}x${size}.png" ] && \
        cp "$ICONSET_DIR/icon_${size}x${size}.png" \
           "$ICONSET_DIR/icon_$((size/2))x$((size/2))@2x.png" 2>/dev/null || true
done

if ls "$ICONSET_DIR"/*.png &>/dev/null; then
    iconutil --convert icns \
        --output "$BUNDLE/Contents/Resources/AppIcon.icns" \
        "$ICONSET_DIR"
    echo "   AppIcon.icns written."
else
    echo "   Warning: could not generate icon (qlmanage unavailable?). App will use SF Symbol fallback."
fi

# Copy SVG into Resources so NSImage(named:) resolves "AppIcon" at runtime
# (macOS 12+ loads SVGs from the bundle automatically)
cp "$SVG" "$BUNDLE/Contents/Resources/AppIcon.svg"

# Update Info.plist to reference the icon
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" \
    "$BUNDLE/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" \
    "$BUNDLE/Contents/Info.plist"

rm -rf "$(dirname "$ICONSET_DIR")"

echo ""
echo "✓ Built: $BUNDLE"
echo ""
echo "To run:"
echo "  open \"$BUNDLE\""
echo ""
echo "Or drag Kapaat.app to /Applications."

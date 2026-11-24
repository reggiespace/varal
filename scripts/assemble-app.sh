#!/bin/sh
# Assembles buildable Varal.app/Contents/ so Launch Services registers
# LSUIElement = true and CFBundleURLSchemes = ["varal"] (finding IR-1).
# Usage: scripts/assemble-app.sh [configuration] [app-destination]
# Defaults: release, ./dist/Varal.app
set -eu

CONFIG="${1:-release}"
DEST="${2:-./dist/Varal.app}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/Varal"
if [ ! -x "$BIN" ]; then
    echo "error: expected binary at $BIN" >&2
    exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
cp "$BIN" "$DEST/Contents/MacOS/Varal"
cp "$ROOT/Varal/Info.plist" "$DEST/Contents/Info.plist"
cp "$ROOT/logos/app-icon/Varal.icns" "$DEST/Contents/Resources/Varal.icns"
cp "$ROOT"/logos/menu-bar/MenuBarIconTemplate*.png "$DEST/Contents/Resources/"

# Registration check (informational; lsregister may be unavailable in CI).
if command -v lsregister >/dev/null 2>&1; then
    lsregister -f "$DEST" || true
elif [ -x "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" || true
fi

echo "Assembled $DEST"
"/usr/bin/plutil" -p "$DEST/Contents/Info.plist" | grep -E "LSUIElement|CFBundleURLSchemes|CFBundleExecutable" || true

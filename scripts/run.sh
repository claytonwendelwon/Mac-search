#!/usr/bin/env bash
#
# Build Beacon, assemble it into a proper .app bundle, ad-hoc sign it,
# and (re)launch it. Runs entirely from the terminal -- no Xcode GUI needed.
#
set -euo pipefail

# Resolve project root (parent of this scripts/ directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

APP_NAME="Beacon"
CONFIG="${CONFIG:-release}"
BUILD_DIR="$ROOT/.build/$CONFIG"
APP_BUNDLE="$ROOT/$APP_NAME.app"

echo "==> Building $APP_NAME ($CONFIG)..."
swift build -c "$CONFIG"

echo "==> Assembling $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Ad-hoc signing..."
codesign --force --deep --entitlements "$ROOT/Resources/Beacon.entitlements" --sign - "$APP_BUNDLE" >/dev/null 2>&1 || \
  codesign --force --entitlements "$ROOT/Resources/Beacon.entitlements" --sign - "$APP_BUNDLE"

echo "==> Relaunching..."
# Quit any running instance so the new build takes over.
osascript -e 'tell application "Beacon" to quit' >/dev/null 2>&1 || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 0.4
open "$APP_BUNDLE"

cat <<'EOF'

==> Beacon is running.
    - Look for the magnifying-glass icon in your menu bar.
    - Press  Option + S  anywhere to open the search bar.
    - Or click the menu-bar icon. Press  Esc  to dismiss it.

    Tip: For complete coverage of every folder on your Mac, grant
    Beacon Full Disk Access in:
      System Settings > Privacy & Security > Full Disk Access
    (Spotlight already indexes most user locations without it.)
EOF

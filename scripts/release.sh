#!/usr/bin/env bash
#
# Build, sign (Developer ID + Hardened Runtime), notarize, staple, and package
# Beacon into a distributable .dmg that opens cleanly on other people's Macs.
#
# Prerequisites (one-time):
#   1. A "Developer ID Application" certificate in your login keychain
#      (Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application).
#   2. Notarization credentials stored in your keychain under a profile name:
#        xcrun notarytool store-credentials "beacon-notary" --apple-id "you@example.com"
#
# Usage:
#   bash scripts/release.sh [version]            # build + notarize + staple dmg
#   bash scripts/release.sh 0.1.0 --publish      # also create a GitHub Release
#
# Env overrides:
#   NOTARY_PROFILE   keychain profile name (default: beacon-notary)
#   SIGN_IDENTITY    full identity string (default: auto-detected Developer ID)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

APP_NAME="Beacon"
NOTARY_PROFILE="${NOTARY_PROFILE:-beacon-notary}"

# --- Args -------------------------------------------------------------------
VERSION="${1:-}"
PUBLISH="false"
for arg in "$@"; do
  [ "$arg" = "--publish" ] && PUBLISH="true"
done
if [ -z "$VERSION" ] || [ "$VERSION" = "--publish" ]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo "0.1.0")"
fi

BUILD_DIR="$ROOT/.build/release"
APP_BUNDLE="$ROOT/$APP_NAME.app"
DIST_DIR="$ROOT/dist"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION.zip"

# --- Locate signing identity -----------------------------------------------
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
if [ -z "$SIGN_IDENTITY" ]; then
  cat <<'EOF'
ERROR: No "Developer ID Application" certificate found in your keychain.

Create one via Xcode:
  Xcode > Settings > Accounts > (your team) > Manage Certificates
    > + > Developer ID Application

Then re-run this script.
EOF
  exit 1
fi
echo "==> Signing identity: $SIGN_IDENTITY"

# --- Verify notarization credentials exist ----------------------------------
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  cat <<EOF
ERROR: No notarization credentials found for profile "$NOTARY_PROFILE".

Store them once with:
  xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id "you@example.com"

(You'll be prompted for your Team ID and an app-specific password from
 https://appleid.apple.com > Sign-In and Security > App-Specific Passwords.)
EOF
  exit 1
fi

# --- Build ------------------------------------------------------------------
echo "==> Building $APP_NAME $VERSION (release)..."
swift build -c release

echo "==> Assembling $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# --- Sign (Hardened Runtime + secure timestamp) -----------------------------
echo "==> Code signing with Hardened Runtime..."
codesign --force --options runtime --timestamp \
  --entitlements "$ROOT/Resources/Beacon.entitlements" \
  --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"

mkdir -p "$DIST_DIR"

# --- Notarize the app -------------------------------------------------------
echo "==> Notarizing app (this can take a minute or two)..."
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
echo "==> Stapling notarization ticket to the app..."
xcrun stapler staple "$APP_BUNDLE"

# --- Build DMG --------------------------------------------------------------
echo "==> Creating $DMG_PATH..."
STAGING="$(mktemp -d)"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
  -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGING"

# --- Notarize + staple the DMG ---------------------------------------------
echo "==> Notarizing the DMG..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"

# --- Verify Gatekeeper acceptance ------------------------------------------
# Note: a .dmg is not itself code-signed; its notarization ticket is stapled,
# so we validate the ticket here. (Gatekeeper assesses the app inside on open.)
echo "==> Verifying notarization ticket on the DMG..."
xcrun stapler validate "$DMG_PATH"
rm -f "$ZIP_PATH"

echo
echo "==> Done. Notarized, stapled disk image:"
echo "    $DMG_PATH"

# --- Optional: publish to GitHub Releases -----------------------------------
if [ "$PUBLISH" = "true" ]; then
  echo "==> Publishing GitHub Release v$VERSION..."
  NOTES_FILE="$(mktemp)"
  cat > "$NOTES_FILE" <<EOF
Beacon $VERSION - a fast, native macOS search launcher.

## Install
1. Download \`$APP_NAME-$VERSION.dmg\` below and open it.
2. **Double-click Beacon.** That's it - it installs itself into Applications,
   relaunches from there, and opens the search bar with a quick hotkey tip.
   (Dragging to the Applications folder still works too, if you prefer.)
3. Press **Option + S** anywhere to open the search bar. Press **Esc** to dismiss.
   Beacon lives in the menu bar (its beacon icon) - no Dock icon or main window.

This build is signed with a Developer ID and notarized by Apple, so it opens
without security warnings.

## Search your text messages (optional)
Beacon can search your iMessage & SMS history. macOS protects the Messages
database, so this needs **Full Disk Access** (a one-time, manual toggle that
Apple requires for any app reading Messages):

1. In Beacon, press **Option + S** and click the **Messages** filter.
2. Click **Open Settings** - this jumps straight to
   **System Settings -> Privacy & Security -> Full Disk Access**.
3. Find **Beacon** in the list and turn its switch **on**.
   (Beacon adds itself to this list automatically - no need for the "+" button.)
4. Choose **Quit & Reopen** when prompted.

Now select the **Messages** filter and search by word, phrase, or contact.
**Return** opens the conversation in Messages; **Cmd + C** copies the text.

The same **Full Disk Access** toggle also unlocks **Notes** and **Safari
history**. (Chrome, Brave, Edge, and Arc history work without it.)

> File search needs no permissions and works the moment you launch Beacon.
> Full Disk Access only unlocks Messages, Notes, Safari history, and a few
> protected folders.

## Highlights
- **Unified "All" search** - the All tab blends files & apps, messages, and
  notes into one grouped, ranked list. Chips included in All show a small dot;
  Clipboard and History are opt-in via their own chips.
- **Recents that actually works** - the **Recents** filter shows files you've
  opened, saved, or added recently, including fresh images/videos/downloads,
  while filtering out app internals, caches, folders, and other Finder noise.
  Type to narrow within the recent-files timeline.
- **Clipboard history** - everything you copy is captured locally and
  searchable under the **Clipboard** filter. **Return** copies it back, ready
  to paste. Private/transient copies (password managers) are skipped.
- **Browser history** - the **History** filter searches every page you've
  visited across **Safari, Chrome, Brave, Edge, and Arc** (all profiles).
  **Return** opens it; **Cmd + C** copies the link.
- **System Settings shortcuts** - the **Settings** filter jumps straight to
  Wi-Fi, Displays, Privacy, Full Disk Access, Keyboard, Battery, and more.
- **Notes search** - search across all your Apple Notes; **Return** opens the
  exact note.

## What's new in $VERSION
- **Recents is now filesystem-backed.** Fresh Safari saves, screenshots, and
  downloads show up immediately without relying on Spotlight/Finder Recents.
- **File thumbnails.** Images, PDFs, videos, and many docs now show Quick Look
  previews in file rows instead of generic icons.
- **History favicons.** Browser-history rows load site icons directly from the
  visited site (no third-party favicon service), with better fallbacks for
  sites that don't expose `/favicon.ico`.
- **Downloaded apps show up.** Apps are scanned directly from application
  folders, so third-party/external installs like Chrome, Claude, Cursor, and
  Discord show in Apps and All.
- **System Settings filter.** A new last filter jumps directly to common
  System Settings panes like Wi-Fi, Privacy, Full Disk Access, Displays,
  Keyboard, Battery, and more.

Upgrading from an earlier version? Just replace the app in Applications -
your Full Disk Access setting carries over. Clipboard history starts recording
as soon as you launch this build.
EOF
  if gh release view "v$VERSION" >/dev/null 2>&1; then
    gh release upload "v$VERSION" "$DMG_PATH" --clobber
  else
    gh release create "v$VERSION" "$DMG_PATH" \
      --title "Beacon $VERSION" --notes-file "$NOTES_FILE"
  fi
  rm -f "$NOTES_FILE"
  echo "==> Release published."
fi

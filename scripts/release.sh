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
1. Download \`$APP_NAME-$VERSION.dmg\` below.
2. Open it and drag **Beacon** into your **Applications** folder.
3. Launch **Beacon** from Applications. It lives in the menu bar
   (magnifying-glass icon) - there's no Dock icon or main window.
4. Press **Option + S** anywhere to open the search bar. Press **Esc** to dismiss.

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

> File search needs no permissions and works the moment you launch Beacon.
> Full Disk Access only unlocks Messages and a few protected folders.

## What's new in $VERSION
- Message results now show the **contact's name** instead of the phone number
  (uses Contacts; you'll be asked once to allow it).
- Message search now covers your **entire history**, not just recent messages.
- Result snippets re-center on the matched word so it's always visible, and
  matched words are **bolded** in titles and snippets across every filter.
- Reordered filter chips: Messages moved up front; Photos/Videos to the end.

Upgrading from an earlier version? Just replace the app in Applications -
your Full Disk Access setting carries over (you'll only be asked once for
Contacts, which is new in this version).
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

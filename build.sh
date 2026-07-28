#!/bin/bash
# Builds Skribble and assembles a runnable Skribble.app bundle.
#
#   ./build.sh            release build  -> build/Skribble.app
#   ./build.sh --debug    debug build
#   ./build.sh --install  release build, then copy to /Applications
#   ./build.sh --run      release build, then launch
#   ./build.sh --dmg      release build, then package build/Skribble.dmg
#   ./build.sh --notarize --dmg
#                         sign with Developer ID, notarize and staple the DMG
#                         so it opens on other Macs with no Gatekeeper warning
#
# Notarizing needs a one-time credential, stored in your keychain (never in a
# file). Run this yourself once, in your own Terminal:
#
#   xcrun notarytool store-credentials "skribble-notary" \
#       --apple-id "you@example.com" --team-id "W67AW8RFW4"
#
# It asks for an app-specific password, which you create at appleid.apple.com
# under Sign-In and Security. Override the profile name with NOTARY_PROFILE.

set -euo pipefail
cd "$(dirname "$0")"

CONFIG="release"
INSTALL=false
RUN=false
DMG=false
NOTARIZE=false
NOTARY_PROFILE="${NOTARY_PROFILE:-skribble-notary}"

for arg in "$@"; do
  case "$arg" in
    --debug)    CONFIG="debug" ;;
    --release)  CONFIG="release" ;;
    --install)  INSTALL=true ;;
    --run)      RUN=true ;;
    --dmg)      DMG=true ;;
    --notarize) NOTARIZE=true; DMG=true ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

APP_NAME="Skribble"
BUNDLE_ID="com.gerowalther.skribble"
VERSION="1.0"
OUT_DIR="build"
APP="$OUT_DIR/$APP_NAME.app"

echo "==> Compiling ($CONFIG)"
swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"

echo "==> Generating icon"
ICONSET="$OUT_DIR/$APP_NAME.iconset"
rm -rf "$ICONSET"
if swift tools/make-icon.swift "$ICONSET" >/dev/null 2>&1 \
   && iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  ICON_ENTRY="<key>CFBundleIconFile</key><string>AppIcon</string>"
  rm -rf "$ICONSET"
else
  echo "    (icon generation skipped)"
  ICON_ENTRY=""
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    $ICON_ENTRY
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Skribble Drawing</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>LSItemContentTypes</key>
            <array><string>$BUNDLE_ID.drawing</string></array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>$BUNDLE_ID.drawing</string>
            <key>UTTypeDescription</key><string>Skribble Drawing</string>
            <key>UTTypeConformsTo</key><array><string>public.json</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key><array><string>skribble</string></array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Notarization requires a real Developer ID signature, the hardened runtime and
# a secure timestamp. Without --notarize we fall back to an ad-hoc signature,
# which runs fine locally but trips Gatekeeper once the app has been downloaded.
if [ "$NOTARIZE" = true ]; then
  SIGN_ID="$(security find-identity -v -p codesigning \
             | grep "Developer ID Application" \
             | head -1 | sed -E 's/.*"(.*)"/\1/')"
  if [ -z "$SIGN_ID" ]; then
    echo "    no 'Developer ID Application' certificate in the keychain." >&2
    echo "    Install one from developer.apple.com before notarizing." >&2
    exit 1
  fi
  echo "==> Signing ($SIGN_ID)"
  codesign --force --deep --options runtime --timestamp \
           --sign "$SIGN_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  echo "==> Signing (ad-hoc)"
  codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
    echo "    (codesign failed; the app will still run)"
fi

echo "==> Built $APP"

if [ "$INSTALL" = true ]; then
  echo "==> Installing to /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  echo "    /Applications/$APP_NAME.app"
fi

if [ "$DMG" = true ]; then
  echo "==> Packaging disk image"
  STAGE="$OUT_DIR/dmg"
  DMG_PATH="$OUT_DIR/$APP_NAME.dmg"
  rm -rf "$STAGE" "$DMG_PATH"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/$APP_NAME.app"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -quiet \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG_PATH"
  rm -rf "$STAGE"
  echo "    $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"

  if [ "$NOTARIZE" = true ]; then
    if ! security find-generic-password -s "com.apple.gke.notary.tool" \
         -a "$NOTARY_PROFILE" >/dev/null 2>&1; then
      echo "" >&2
      echo "    No notarytool profile named '$NOTARY_PROFILE'." >&2
      echo "    Create it once, in your own Terminal:" >&2
      echo "" >&2
      echo "      xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\" >&2
      echo "          --apple-id \"you@example.com\" --team-id \"W67AW8RFW4\"" >&2
      echo "" >&2
      exit 1
    fi

    echo "==> Notarizing (this usually takes 1-5 minutes)"
    # Signing the DMG too means the disk image itself also passes Gatekeeper.
    codesign --force --sign "$SIGN_ID" --timestamp "$DMG_PATH"
    xcrun notarytool submit "$DMG_PATH" \
      --keychain-profile "$NOTARY_PROFILE" --wait

    echo "==> Stapling"
    # Stapling attaches the ticket to the file so it validates offline.
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature -v "$DMG_PATH"
    echo "    Notarized and stapled."
  fi
fi

if [ "$RUN" = true ]; then
  echo "==> Launching"
  open "$APP"
fi

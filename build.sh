#!/bin/bash
# Builds Skribble and assembles a runnable Skribble.app bundle.
#
#   ./build.sh            release build  -> build/Skribble.app
#   ./build.sh --debug    debug build
#   ./build.sh --install  release build, then copy to /Applications
#   ./build.sh --run      release build, then launch
#   ./build.sh --dmg      release build, then package build/Skribble.dmg

set -euo pipefail
cd "$(dirname "$0")"

CONFIG="release"
INSTALL=false
RUN=false
DMG=false

for arg in "$@"; do
  case "$arg" in
    --debug)   CONFIG="debug" ;;
    --release) CONFIG="release" ;;
    --install) INSTALL=true ;;
    --run)     RUN=true ;;
    --dmg)     DMG=true ;;
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

# Ad-hoc signature so macOS is willing to launch the bundle and remember any
# Screen Recording permission granted to it.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
  echo "    (codesign failed; the app will still run)"

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
fi

if [ "$RUN" = true ]; then
  echo "==> Launching"
  open "$APP"
fi

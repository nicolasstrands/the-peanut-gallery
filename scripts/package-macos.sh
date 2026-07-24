#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACOS_PACKAGE="$REPO_ROOT/apps/macos-overlay"
DIST_DIR="$REPO_ROOT/dist"
APP_DIR="$DIST_DIR/PeanutGallery.app"
ZIP_PATH="$DIST_DIR/PeanutGallery-unsigned.zip"
ICON_SOURCE="$REPO_ROOT/apps/web/public/branding/peanut-gallery-logo.png"
ICONSET_DIR="$DIST_DIR/PeanutGallery.iconset"

echo "Building Peanut Gallery in release mode..."
swift build --configuration release --package-path "$MACOS_PACKAGE"

BIN_DIR="$(swift build --show-bin-path --configuration release --package-path "$MACOS_PACKAGE")"
BIN_PATH="$BIN_DIR/PeanutGallery"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Could not find release executable at $BIN_PATH" >&2
  exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources" "$ICONSET_DIR"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/PeanutGallery"
cp "$MACOS_PACKAGE/PeanutGallery/Info.plist" "$APP_DIR/Contents/Info.plist"

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Could not find app icon source at $ICON_SOURCE" >&2
  exit 1
fi

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/PeanutGallery.icns"

echo "Creating unsigned ZIP..."
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo
echo "Created:"
echo "  $APP_DIR"
echo "  $ZIP_PATH"
echo
echo "This build is unsigned and un-notarized. Gatekeeper may require users to right-click the app and choose Open."

#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${CONFIGURATION:-debug}"
PRODUCT_NAME="PromptPaster"
APP_NAME="Prompt Paster.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

swift build --configuration "$CONFIGURATION"
BUILD_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BUILD_DIR/$PRODUCT_NAME" "$MACOS_DIR/$PRODUCT_NAME"
if [ -d "$BUILD_DIR/${PRODUCT_NAME}_${PRODUCT_NAME}.bundle" ]; then
    cp -R "$BUILD_DIR/${PRODUCT_NAME}_${PRODUCT_NAME}.bundle" "$RESOURCES_DIR/"
fi
chmod +x "$MACOS_DIR/$PRODUCT_NAME"

echo "Built $APP_DIR"

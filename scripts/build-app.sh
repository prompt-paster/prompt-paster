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

swift build --configuration "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/.build/$CONFIGURATION/$PRODUCT_NAME" "$MACOS_DIR/$PRODUCT_NAME"
chmod +x "$MACOS_DIR/$PRODUCT_NAME"

echo "Built $APP_DIR"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg-staging"
APP_NAME="Prompt Paster.app"
VOLUME_NAME="Prompt Paster"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT_DIR/Packaging/Info.plist")"
DMG_PATH="${DMG_PATH:-$DIST_DIR/PromptPaster-$VERSION.dmg}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
NOTARY_KEYCHAIN_PATH="${NOTARY_KEYCHAIN_PATH:-}"

notary_args=()
if [ "$NOTARIZE" = "1" ]; then
    if [ -z "$CODESIGN_IDENTITY" ]; then
        echo "NOTARIZE=1 requires CODESIGN_IDENTITY so the app is signed before submission." >&2
        exit 1
    fi
    if [ -n "$NOTARY_KEYCHAIN_PROFILE" ]; then
        notary_args=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
        if [ -n "$NOTARY_KEYCHAIN_PATH" ]; then
            notary_args+=(--keychain "$NOTARY_KEYCHAIN_PATH")
        fi
    elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APP_SPECIFIC_PASSWORD:-}" ]; then
        notary_args=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APP_SPECIFIC_PASSWORD")
    else
        echo "NOTARIZE=1 requires NOTARY_KEYCHAIN_PROFILE or APPLE_ID, APPLE_TEAM_ID, and APP_SPECIFIC_PASSWORD." >&2
        exit 1
    fi
fi

CONFIGURATION=release "$ROOT_DIR/scripts/build-app.sh"

APP_DIR="$DIST_DIR/$APP_NAME"
if [ ! -d "$APP_DIR" ]; then
    echo "Missing app bundle after build: $APP_DIR" >&2
    exit 1
fi

if [ -n "$CODESIGN_IDENTITY" ]; then
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --entitlements "$ROOT_DIR/Packaging/Entitlements.plist" \
        --sign "$CODESIGN_IDENTITY" \
        "$APP_DIR"
    codesign --verify --strict --deep --verbose=2 "$APP_DIR"
else
    echo "CODESIGN_IDENTITY is not set; applying an ad-hoc signature for unsigned local validation."
    codesign \
        --force \
        --deep \
        --sign - \
        "$APP_DIR"
    codesign --verify --strict --deep --verbose=2 "$APP_DIR"
fi

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
cat > "$STAGING_DIR/README.txt" <<'README'
Prompt Paster

Drag Prompt Paster.app to Applications, then launch it from Applications.
It runs as a menu-bar utility and does not show a Dock icon.

Global trigger notes:
- Control+Option+Space is the fallback hotkey.
- Double-Control requires Accessibility permission in System Settings.
README

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

if [ -n "$CODESIGN_IDENTITY" ]; then
    codesign \
        --force \
        --timestamp \
        --sign "$CODESIGN_IDENTITY" \
        "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
fi

if [ "$NOTARIZE" = "1" ]; then
    xcrun notarytool submit "$DMG_PATH" "${notary_args[@]}" --wait
    xcrun stapler staple "$DMG_PATH"
fi

if [ "$NOTARIZE" = "1" ]; then
    "$ROOT_DIR/scripts/validate-release-package.sh" "$DMG_PATH" --expect-notarized
else
    "$ROOT_DIR/scripts/validate-release-package.sh" "$DMG_PATH"
fi

echo "Built $DMG_PATH"

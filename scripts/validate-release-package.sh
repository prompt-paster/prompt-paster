#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 <PromptPaster.dmg> [--launch-smoke]" >&2
    exit 64
fi

DMG_PATH="$1"
LAUNCH_SMOKE="${2:-}"
APP_NAME="Prompt Paster.app"
EXECUTABLE_NAME="PromptPaster"

if [ "$LAUNCH_SMOKE" != "" ] && [ "$LAUNCH_SMOKE" != "--launch-smoke" ]; then
    echo "Unknown option: $LAUNCH_SMOKE" >&2
    exit 64
fi

if [ ! -f "$DMG_PATH" ]; then
    echo "Missing DMG artifact: $DMG_PATH" >&2
    exit 1
fi

TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
MOUNT_DIR="$(mktemp -d "$TMP_BASE/prompt-paster-dmg.XXXXXX")"
ATTACHED=0

cleanup() {
    if [ "$ATTACHED" -eq 1 ]; then
        for _ in {1..5}; do
            if hdiutil detach "$MOUNT_DIR" -quiet; then
                ATTACHED=0
                break
            fi
            sleep 0.5
        done
    fi
    if [ "$ATTACHED" -eq 0 ]; then
        rm -rf "$MOUNT_DIR"
    else
        echo "Warning: could not detach $MOUNT_DIR; leaving mountpoint for manual cleanup." >&2
    fi
}
trap cleanup EXIT

hdiutil verify "$DMG_PATH" >/dev/null
hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" -quiet
ATTACHED=1

APP_DIR="$MOUNT_DIR/$APP_NAME"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
EXECUTABLE="$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

test -d "$APP_DIR"
test -f "$INFO_PLIST"
test -x "$EXECUTABLE"
test -f "$RESOURCES_DIR/PromptPaster.icns"
test -d "$RESOURCES_DIR/PromptPaster_PromptPaster.bundle"
test -L "$MOUNT_DIR/Applications"
test -f "$MOUNT_DIR/README.txt"

plutil -lint "$INFO_PLIST" >/dev/null

if [ "$LAUNCH_SMOKE" = "--launch-smoke" ]; then
    EXECUTABLE_REAL="$(cd "$(dirname "$EXECUTABLE")" && pwd -P)/$EXECUTABLE_NAME"

    find_mounted_app_pid() {
        local pid
        local command

        while IFS= read -r pid; do
            command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
            case "$command" in
                "$EXECUTABLE_REAL"*)
                    echo "$pid"
                    return 0
                    ;;
            esac
        done < <(pgrep -x "$EXECUTABLE_NAME" || true)

        return 1
    }

    open -n "$APP_DIR"
    launched_pid=""
    launched=0
    for _ in {1..20}; do
        if launched_pid="$(find_mounted_app_pid)"; then
            kill "$launched_pid"
            echo "Launch smoke passed for $APP_DIR"
            launched=1
            break
        fi
        sleep 0.25
    done

    if [ -n "$launched_pid" ] && kill -0 "$launched_pid" 2>/dev/null; then
        kill "$launched_pid"
    fi

    for _ in {1..20}; do
        if [ -z "$launched_pid" ] || ! kill -0 "$launched_pid" 2>/dev/null; then
            break
        fi
        sleep 0.25
    done

    if [ "$launched" -ne 1 ]; then
        echo "Launch smoke failed: $EXECUTABLE_NAME did not start." >&2
        exit 1
    fi
fi

echo "Validated $DMG_PATH"

#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <output.icns>" >&2
    exit 64
fi

OUTPUT_ICNS="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/prompt-paster-icon.XXXXXX")"
ICONSET_DIR="$WORK_DIR/PromptPaster.iconset"
SWIFT_FILE="$WORK_DIR/render-icon.swift"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$ICONSET_DIR"

cat > "$SWIFT_FILE" <<'SWIFT'
import AppKit

let size = Int(CommandLine.arguments[1])!
let outputPath = CommandLine.arguments[2]
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let radius = CGFloat(size) * 0.22
let background = NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(size) * 0.05, dy: CGFloat(size) * 0.05), xRadius: radius, yRadius: radius)

NSColor(calibratedRed: 0.12, green: 0.20, blue: 0.24, alpha: 1).setFill()
background.fill()

let inset = CGFloat(size) * 0.20
let cardRect = rect.insetBy(dx: inset, dy: inset * 1.12)
let card = NSBezierPath(roundedRect: cardRect, xRadius: CGFloat(size) * 0.06, yRadius: CGFloat(size) * 0.06)
NSColor(calibratedRed: 0.94, green: 0.91, blue: 0.82, alpha: 1).setFill()
card.fill()

NSColor(calibratedRed: 0.20, green: 0.34, blue: 0.36, alpha: 1).setStroke()
for index in 0..<3 {
    let y = cardRect.maxY - CGFloat(index + 1) * cardRect.height * 0.24
    let line = NSBezierPath()
    line.lineWidth = max(2, CGFloat(size) * 0.035)
    line.move(to: NSPoint(x: cardRect.minX + cardRect.width * 0.16, y: y))
    line.line(to: NSPoint(x: cardRect.maxX - cardRect.width * (index == 2 ? 0.34 : 0.16), y: y))
    line.stroke()
}

let cursorWidth = max(4, CGFloat(size) * 0.05)
let cursorRect = NSRect(
    x: cardRect.maxX - cardRect.width * 0.20,
    y: cardRect.minY + cardRect.height * 0.14,
    width: cursorWidth,
    height: cardRect.height * 0.24
)
NSColor(calibratedRed: 0.79, green: 0.38, blue: 0.18, alpha: 1).setFill()
NSBezierPath(roundedRect: cursorRect, xRadius: cursorWidth / 2, yRadius: cursorWidth / 2).fill()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Failed to render icon")
}

try png.write(to: URL(fileURLWithPath: outputPath))
SWIFT

render_icon() {
    local points="$1"
    local scale="$2"
    local name="$3"
    local pixels=$((points * scale))

    swift "$SWIFT_FILE" "$pixels" "$ICONSET_DIR/$name"
}

render_icon 16 1 "icon_16x16.png"
render_icon 16 2 "icon_16x16@2x.png"
render_icon 32 1 "icon_32x32.png"
render_icon 32 2 "icon_32x32@2x.png"
render_icon 128 1 "icon_128x128.png"
render_icon 128 2 "icon_128x128@2x.png"
render_icon 256 1 "icon_256x256.png"
render_icon 256 2 "icon_256x256@2x.png"
render_icon 512 1 "icon_512x512.png"
render_icon 512 2 "icon_512x512@2x.png"

mkdir -p "$(dirname "$OUTPUT_ICNS")"
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

echo "Generated $OUTPUT_ICNS from local vector drawing"

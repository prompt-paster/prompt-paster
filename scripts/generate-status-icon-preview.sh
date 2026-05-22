#!/usr/bin/env bash
set -euo pipefail

OUTPUT_PATH="${1:-dist/status-icon-preview.png}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/prompt-paster-status-icon.XXXXXX")"
SWIFT_FILE="$WORK_DIR/render-status-icon-preview.swift"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cat > "$SWIFT_FILE" <<'SWIFT'
import AppKit

let outputPath = CommandLine.arguments[1]
let scale: CGFloat = 2
let previewSize = NSSize(width: 520, height: 180)
let image = NSImage(size: previewSize)

func drawStatusBar(in rect: NSRect, background: NSColor, foreground: NSColor, label: String) {
    background.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()

    let itemRect = NSRect(x: rect.midX - 62, y: rect.midY - 16, width: 124, height: 32)
    foreground.withAlphaComponent(0.12).setFill()
    NSBezierPath(roundedRect: itemRect, xRadius: 7, yRadius: 7).fill()

    let badgeAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: foreground.withAlphaComponent(0.92)
    ]
    "Prompt Paster".draw(at: NSPoint(x: itemRect.minX + 11, y: itemRect.midY - 8), withAttributes: badgeAttributes)

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: foreground.withAlphaComponent(0.82)
    ]
    label.draw(at: NSPoint(x: rect.minX + 18, y: rect.minY + 12), withAttributes: attributes)
}

image.lockFocus()
NSColor.windowBackgroundColor.setFill()
NSRect(origin: .zero, size: previewSize).fill()

drawStatusBar(
    in: NSRect(x: 24, y: 98, width: 472, height: 46),
    background: NSColor(calibratedWhite: 0.96, alpha: 1),
    foreground: NSColor(calibratedWhite: 0.08, alpha: 1),
    label: "Light menu bar"
)
drawStatusBar(
    in: NSRect(x: 24, y: 32, width: 472, height: 46),
    background: NSColor(calibratedWhite: 0.08, alpha: 1),
    foreground: NSColor(calibratedWhite: 0.96, alpha: 1),
    label: "Dark menu bar"
)

image.unlockFocus()

guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(previewSize.width * scale),
        pixelsHigh: Int(previewSize.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
else {
    fatalError("Could not create bitmap")
}

bitmap.size = previewSize
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(origin: .zero, size: previewSize))
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode preview")
}

try FileManager.default.createDirectory(
    at: URL(fileURLWithPath: outputPath).deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: URL(fileURLWithPath: outputPath))
SWIFT

swift "$SWIFT_FILE" "$ROOT_DIR/$OUTPUT_PATH"
echo "Generated $OUTPUT_PATH"

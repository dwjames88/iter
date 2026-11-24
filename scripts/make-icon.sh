#!/bin/bash
# Rebuilds the Mac app icon PNGs (Mac/Resources/Assets.xcassets/AppIcon.appiconset) from Brand/logo/app-icon.svg. No windows are
# opened. The set's Contents.json and the iOS icon (iOS/Resources, which has its own 1024 art) are left alone.
#   scripts/make-icon.sh
# Environment: ITER_ICON_SET = write the PNGs into this folder instead (to try it without touching the catalog).
# Icon convention (macOS 26): the system masks the icon, so the artwork is a full-bleed square (no rounded
# corners, no margin, no shadow). See Design/TOKENS.md, "App icon".
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOGO="$ROOT/Brand/logo"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The Brand/logo SVGs are First Light already (ground #1E0F0A, ink/mark #1E0F0A light or #FFF4E8 dark, dot #D9431A light or
# #FF8A5C dark), so nothing is recoloured here. The only edits: the icon loses its rounded corners, and the Mono files, which
# are currentColor only, are written out as black templates. The retired gold files live in Brand/logo/_retired (not read).

# --- App icon: full-bleed square (drop the rounded rect rx); ground, mark and dot come from the file ---------------------------
sed -e 's/ rx="[0-9.]*"//' "$LOGO/app-icon.svg" > "$WORK/app-icon-square.svg"

cat > "$WORK/render.swift" <<'SWIFT'
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let image = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write(Data("cannot read SVG\n".utf8)); exit(1)
}
let out = URL(fileURLWithPath: args[2], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try png.write(to: out.appendingPathComponent("\(pixels).png"))
}
SWIFT
swift "$WORK/render.swift" "$WORK/app-icon-square.svg" "$WORK/png"

ICONSET="${ITER_ICON_SET:-$ROOT/Mac/Resources/Assets.xcassets/AppIcon.appiconset}"
mkdir -p "$ICONSET"
# name:pixels, in the order of Contents.json
for entry in 16x16:1:16 16x16:2:32 32x32:1:32 32x32:2:64 128x128:1:128 128x128:2:256 256x256:1:256 256x256:2:512 512x512:1:512 512x512:2:1024; do
  IFS=: read -r size scale px <<<"$entry"
  suffix=""; [ "$scale" = 2 ] && suffix="@2x"
  cp "$WORK/png/$px.png" "$ICONSET/icon_${size}${suffix}.png"
done
echo "icon PNGs written to $ICONSET"

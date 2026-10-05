#!/bin/bash
# Rebuilds the app icon PNGs and the in-app logo image sets from Brand/logo/*.svg. No windows are opened.
#   scripts/make-icon.sh
# Icon convention (macOS 26): the system masks the icon, so the artwork is a full-bleed square (no rounded
# corners, no margin, no shadow). See Design/TOKENS.md, "App icon".
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOGO="$ROOT/Brand/logo"
CAT="$ROOT/App/Resources/Assets.xcassets"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Brand colours: First Light (firstlight-deep). The source SVGs in Brand/logo keep #F5B72B as a placeholder dot colour (and
# currentColor for the ink) that this script substitutes; the app icon source keeps #0A0A0A ground, #FFFFFF mark, #F5B72B dot.
INK_LIGHT="#1E0F0A"; INK_DARK="#FFF4E8"; DOT_LIGHT="#D9431A"; DOT_DARK="#FF8A5C"
ICON_GROUND="#1E0F0A"; ICON_MARK="#FFF4E8"; ICON_DOT="#FF8A5C"

# --- App icon: full-bleed square (drop the rounded rect), First Light ground, mark and dot -----------------------------------
sed -e 's/ rx="[0-9.]*"//' -e "s/fill=\"#0A0A0A\"/fill=\"$ICON_GROUND\"/g" -e "s/fill=\"#FFFFFF\"/fill=\"$ICON_MARK\"/g" \
    -e "s/fill=\"#F5B72B\"/fill=\"$ICON_DOT\"/g" "$LOGO/app-icon.svg" > "$WORK/app-icon-square.svg"

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

ICONSET="$CAT/AppIcon.appiconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
# name:pixels, in the order of Contents.json
for entry in 16x16:1:16 16x16:2:32 32x32:1:32 32x32:2:64 128x128:1:128 128x128:2:256 256x256:1:256 256x256:2:512 512x512:1:512 512x512:2:1024; do
  IFS=: read -r size scale px <<<"$entry"
  suffix=""; [ "$scale" = 2 ] && suffix="@2x"
  cp "$WORK/png/$px.png" "$ICONSET/icon_${size}${suffix}.png"
done
python3 - "$ICONSET/Contents.json" <<'PY'
import json, sys
images = []
for size in ["16x16", "32x32", "128x128", "256x256", "512x512"]:
    for scale in (1, 2):
        images.append({"filename": f"icon_{size}{'@2x' if scale == 2 else ''}.png", "idiom": "mac", "scale": f"{scale}x", "size": size})
json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, open(sys.argv[1], "w"), indent=2, sort_keys=True)
open(sys.argv[1], "a").write("\n")
PY

# --- In-app logo image sets (vector, single scale) --------------------------------------------------------------------
# currentColor does not survive an asset catalog, so the colours are written out. Logo/Symbol have a light file and a
# dark-appearance file; the Mono sets are black template images that tint to whatever the view's foreground style is.
imageset() { # name, light svg, dark svg (or empty), template (yes/no)
  local dir="$CAT/$1.imageset"; rm -rf "$dir"; mkdir -p "$dir"
  cp "$2" "$dir/$1.svg"
  python3 - "$dir/Contents.json" "$1" "${3:+$1-dark}" "$4" <<'PY'
import json, sys
path, name, dark, template = sys.argv[1:5]
images = [{"filename": f"{name}.svg", "idiom": "universal"}]
if dark:
    images.append({"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": f"{dark}.svg", "idiom": "universal"})
props = {"preserves-vector-representation": True}
if template == "yes":
    props["template-rendering-intent"] = "template"
json.dump({"images": images, "info": {"author": "xcode", "version": 1}, "properties": props}, open(path, "w"), indent=2, sort_keys=True)
open(path, "a").write("\n")
PY
  if [ -n "${3:-}" ]; then cp "$3" "$dir/$1-dark.svg"; fi
}
recolor() { sed -e "s/currentColor/$1/g" -e "s/#F5B72B/$2/g" "$3"; }
for name in lockup symbol; do
  recolor "$INK_LIGHT" "$DOT_LIGHT" "$LOGO/$name.svg" > "$WORK/$name-light.svg"
  recolor "$INK_DARK" "$DOT_DARK" "$LOGO/$name.svg" > "$WORK/$name-dark.svg"
  recolor "#000000" "#000000" "$LOGO/$name-mono.svg" > "$WORK/$name-mono.svg"
done
imageset Logo "$WORK/lockup-light.svg" "$WORK/lockup-dark.svg" no
imageset Symbol "$WORK/symbol-light.svg" "$WORK/symbol-dark.svg" no
imageset LogoMono "$WORK/lockup-mono.svg" "" yes
imageset SymbolMono "$WORK/symbol-mono.svg" "" yes
echo "icon and logo assets written to $CAT"

#!/bin/bash
# Icon QA — renders Buddy.icon through the REAL macOS icon pipeline and asserts
# the result matches the flat design. Catches what file inspection can't:
# Tahoe's icon jail, liquid-glass relighting (black strokes turning grey),
# blur from missing resolutions, wrong glyph scale.
#
# Run: pnpm icons:qa   (regenerates Assets.car + icon.icns as a side effect,
#                       and syncs the iOS copy of the .icon package)
# Pass = exit 0. Any FAIL prints details and exits 1.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONS=src-tauri/icons
WORK=$(mktemp -d /tmp/buddy-icon-qa.XXXXXX)
STAMP=$(date +%s)

echo "→ compiling ${ICONS}/Buddy.icon with actool"
mkdir -p "$WORK/car"
xcrun actool "$ICONS/Buddy.icon" --compile "$WORK/car" \
  --output-format human-readable-text --errors \
  --output-partial-info-plist "$WORK/car/partial.plist" \
  --app-icon Buddy --include-all-app-icons \
  --enable-on-demand-resources NO --development-region en \
  --target-device mac --minimum-deployment-target 26.0 --platform macosx \
  > "$WORK/actool.log" 2>&1 || { cat "$WORK/actool.log"; exit 1; }

cp "$WORK/car/Assets.car" "$ICONS/Assets.car"
rsync -a --delete "$ICONS/Buddy.icon/" ios/Buddy/Resources/AppIcon.icon/
echo "→ refreshed $ICONS/Assets.car, ios AppIcon.icon (icon.icns packed after render below)"

# Throwaway app with a unique bundle id so icon services can't serve a stale render.
APP="$WORK/IconQA-$STAMP.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$WORK/car/Assets.car" "$WORK/car/Buddy.icns" "$APP/Contents/Resources/"
echo 'import Foundation' > "$WORK/stub.swift"
swiftc "$WORK/stub.swift" -o "$APP/Contents/MacOS/IconQA" 2>/dev/null
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>IconQA</string>
  <key>CFBundleIdentifier</key><string>fyi.whale.buddy.iconqa$STAMP</string>
  <key>CFBundleName</key><string>IconQA</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>Buddy</string>
  <key>CFBundleIconName</key><string>Buddy</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
</dict>
</plist>
EOF
codesign --force -s - "$APP" 2>/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

echo "→ rendering through NSWorkspace (the same pipeline Dock/Finder/Spotlight use)"
cat > "$WORK/render.swift" <<EOF
import AppKit

func render(_ size: Int) -> NSBitmapImageRep {
    let icon = NSWorkspace.shared.icon(forFile: "$APP")
    icon.size = NSSize(width: size, height: size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Icon services registers the fresh bundle asynchronously — the first fetches
// can return the generic document icon. Warm up until real artwork appears.
var warmed = false
for _ in 0..<10 {
    let rep = render(1024)
    outer: for y in stride(from: 0, to: 1024, by: 8) {
        for x in stride(from: 0, to: 1024, by: 8) {
            if let c = rep.colorAt(x: x, y: y),
               c.alphaComponent > 0.8, c.redComponent < 0.35,
               c.greenComponent < 0.35, c.blueComponent < 0.35 {
                warmed = true; break outer
            }
        }
    }
    if warmed { break }
    Thread.sleep(forTimeInterval: 1)
}
guard warmed else { fputs("icon never warmed — still generic after 10s\n", stderr); exit(1) }

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = render(size)
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "$WORK/render-\(size).png"))
}
EOF
swift "$WORK/render.swift"

# Full-resolution .icns fallback (16→1024) packed from the SYSTEM's own renders,
# so icns-backed surfaces (Get Info, DMG, pre-Tahoe macOS) match Tahoe exactly.
# actool's own fallback icns caps at 256px and upscales soft — never ship it.
ISET="$WORK/Buddy.iconset"
mkdir -p "$ISET"
cp "$WORK/render-16.png"   "$ISET/icon_16x16.png"
cp "$WORK/render-32.png"   "$ISET/icon_16x16@2x.png"
cp "$WORK/render-32.png"   "$ISET/icon_32x32.png"
cp "$WORK/render-64.png"   "$ISET/icon_32x32@2x.png"
cp "$WORK/render-128.png"  "$ISET/icon_128x128.png"
cp "$WORK/render-256.png"  "$ISET/icon_128x128@2x.png"
cp "$WORK/render-256.png"  "$ISET/icon_256x256.png"
cp "$WORK/render-512.png"  "$ISET/icon_256x256@2x.png"
cp "$WORK/render-512.png"  "$ISET/icon_512x512.png"
cp "$WORK/render-1024.png" "$ISET/icon_512x512@2x.png"
iconutil -c icns "$ISET" -o "$ICONS/icon.icns"
echo "→ packed full-res icon.icns (16-1024) from system renders"

python3 - "$WORK/render-1024.png" <<'PY'
import sys
from PIL import Image

im = Image.open(sys.argv[1]).convert("RGBA")
W = im.size[0]
px = im.load()

fails = []
def check(name, ok, detail):
    print(("PASS " if ok else "FAIL ") + name + " — " + detail)
    if not ok: fails.append(name)

# Locate the black glyph bbox (ignore squircle edge shading: look for near-black).
xs, ys = [], []
for y in range(0, W, 2):
    for x in range(0, W, 2):
        r, g, b, a = px[x, y]
        if a > 200 and r < 90 and g < 90 and b < 90:
            xs.append(x); ys.append(y)
check("glyph-found", bool(xs), f"{len(xs)} dark samples")
if not xs:
    sys.exit(1)
x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
gw = x1 - x0

# 1. FLAT BLACK: liquid glass relights black strokes to ~grey 70-110. The real
#    design is #000. Sample the outline's darkest pixels; they must be near-black.
mid = (y0 + y1) // 2
row = [px[x, mid] for x in range(x0, x0 + int(gw * 0.15))]
darkest = min(max(p[0], p[1], p[2]) for p in row if p[3] > 200)
check("stroke-is-black", darkest <= 40, f"darkest outline channel={darkest} (glass relighting pushes this to 70+)")

# 1b. STROKE WEIGHT: whale's design = stroke 5.36% of the sticker width. The
#     system SVG renderer once drew it at ~3% (half-weight, "wiry" icon) — a
#     raster layer avoids that, and this assertion pins it forever.
runlen = 0; runs = []
for x in range(max(0, x0 - 6), x1):
    p = px[x, mid]
    if p[3] > 200 and max(p[0], p[1], p[2]) < 80: runlen += 1
    elif runlen: runs.append(runlen); runlen = 0
stroke_frac = (runs[0] / gw) if runs else 0
check("stroke-weight", 0.045 <= stroke_frac <= 0.063,
      f"stroke/sticker={stroke_frac:.4f}, design spec 0.0536 (thin render = SVG stroke bug)")

# 2. RED FOLD: #FF4342 within tolerance somewhere in the glyph's top-right.
best = None
for y in range(y0, y0 + int(gw * 0.35), 2):
    for x in range(x0 + int(gw * 0.6), x1, 2):
        r, g, b, a = px[x, y]
        if a > 200 and r > 180 and r - g > 60 and r - b > 60:
            best = (r, g, b); break
    if best: break
ok = best is not None and abs(best[0] - 255) <= 25 and abs(best[1] - 67) <= 30 and abs(best[2] - 66) <= 30
check("fold-red", ok, f"sampled {best}, want ~(255,67,66)")

# 3. WHITE BODY: sticker interior must be white, not tinted/vignetted.
cx, cy = (x0 + x1) // 2, y0 + int((y1 - y0) * 0.35)
r, g, b, a = px[cx, cy]
check("body-white", min(r, g, b) >= 245, f"body sample=({r},{g},{b})")

# 4. PROPORTION: glyph should span ~72% of the system tile. The tile is ~80% of
#    the rendered canvas (system margin), so glyph/canvas ≈ 0.72 * 0.80 = 0.576.
frac = gw / W
check("glyph-proportion", 0.52 <= frac <= 0.64, f"glyph/canvas={frac:.3f}, want ~0.576")

# 5. NO JAIL: the legacy jail paints an inner artwork edge ~straight vertical
#    grey line left of the glyph. Native render has clean white there.
jx = x0 - int(gw * 0.06)
greys = sum(1 for y in range(y0, y1, 4)
            if (lambda p: p[3] > 200 and 120 < p[0] < 230 and abs(p[0]-p[1]) < 12 and abs(p[1]-p[2]) < 12)(px[jx, y]))
check("no-jail-frame", greys < (y1 - y0) // 40, f"{greys} grey frame pixels at x={jx}")

print()
print("previews: " + sys.argv[1] + " (open to eyeball)")
sys.exit(1 if fails else 0)
PY
STATUS=$?

# icns must carry the full ladder up to 1024 and stay crisp — the 256-capped
# actool fallback is exactly the blur users reported at large sizes.
python3 - "$ICONS/icon.icns" <<'PY'
import subprocess, sys, tempfile, os
from PIL import Image
out = tempfile.mkdtemp()
subprocess.run(["iconutil", "-c", "iconset", sys.argv[1], "-o", out + "/i.iconset"], check=True)
names = os.listdir(out + "/i.iconset")
ok1024 = "icon_512x512@2x.png" in names
print(("PASS " if ok1024 else "FAIL ") + "icns-1024 — reps: " + ",".join(sorted(names)))
im = Image.open(out + "/i.iconset/icon_512x512@2x.png").convert("RGBA")
W = im.size[0]; px = im.load()
xs = [x for y in range(0, W, 8) for x in range(W) if px[x, y][3] > 200 and max(px[x, y][:3]) < 90]
mid_dark_x = min(xs)
row_y = next(y for y in range(0, W, 8) for x in [min(xs)] if px[x, y][3] > 200 and max(px[x, y][:3]) < 90)
vals = [max(px[x, row_y][:3]) for x in range(max(0, mid_dark_x - 12), mid_dark_x + 14)]
trans = sum(1 for v in vals if 40 < v < 215)
sharp = trans <= 4
print(("PASS " if sharp else "FAIL ") + f"icns-sharpness — {trans} transition px at 1024 (>4 = upscaled blur)")
sys.exit(0 if (ok1024 and sharp) else 1)
PY
ICNS_STATUS=$?
[ $STATUS -eq 0 ] && STATUS=$ICNS_STATUS
echo "renders in: $WORK"
exit $STATUS

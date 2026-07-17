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
cp "$WORK/car/Buddy.icns" "$ICONS/icon.icns"
rsync -a --delete "$ICONS/Buddy.icon/" ios/Buddy/Resources/AppIcon.icon/
echo "→ refreshed $ICONS/Assets.car, $ICONS/icon.icns, ios AppIcon.icon"

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
for size in [1024, 128] {
    let icon = NSWorkspace.shared.icon(forFile: "$APP")
    icon.size = NSSize(width: size, height: size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "$WORK/render-\(size).png"))
}
EOF
swift "$WORK/render.swift"

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
echo "renders in: $WORK"
exit $STATUS

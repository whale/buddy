#!/usr/bin/env python3
"""
Placeholder icon generator for Buddy's Tauri shell. UNVERIFIED scaffold helper.

Produces simple PNGs with no external dependencies (stdlib zlib + struct only):
  icons/32x32.png, 128x128.png, 128x128@2x.png, icon.png  -> app/dock icon (rounded dark square, white "b")
  icons/tray.png (44x44 = 22x22@2x), tray@2x.png            -> menu-bar icon (template: black glyph on transparent)

These are throwaway placeholders. Drop a real 22x22@2x menu-bar icon at
src-tauri/icons/tray.png (44x44 px, black-on-transparent "template" style so
macOS can recolor it for light/dark menu bars) and real app icons before shipping.

Run:  python3 src-tauri/gen-icons.py
"""
import struct, zlib, os

HERE = os.path.dirname(os.path.abspath(__file__))
ICONS = os.path.join(HERE, "icons")
os.makedirs(ICONS, exist_ok=True)


def write_png(path, w, h, pixels):
    """pixels: list of rows, each row a list of (r,g,b,a) tuples."""
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter type 0 (none)
        for (r, g, b, a) in row:
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)  # 8-bit RGBA
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b""))


# --- tiny 5x7 bitmap "b" glyph, scaled up and centered ---
GLYPH_B = [
    "10000",
    "10000",
    "11110",
    "10001",
    "10001",
    "10001",
    "11110",
]


def draw_glyph(w, h, fg, bg, rounded=False, radius_frac=0.22):
    gh = len(GLYPH_B)
    gw = len(GLYPH_B[0])
    # scale glyph to ~52% of canvas, centered
    scale = max(1, int(min(w, h) * 0.52 / gh))
    sx = (w - gw * scale) // 2
    sy = (h - gh * scale) // 2
    rad = int(min(w, h) * radius_frac) if rounded else 0

    def in_rounded(x, y):
        if not rounded:
            return True
        r = rad
        for (cx, cy) in ((r, r), (w - 1 - r, r), (r, h - 1 - r), (w - 1 - r, h - 1 - r)):
            if ((x < r and y < r) or (x > w - 1 - r and y < r) or
                    (x < r and y > h - 1 - r) or (x > w - 1 - r and y > h - 1 - r)):
                pass
        # simpler: clip the four corners by circle test
        corners = [(r, r), (w - 1 - r, r), (r, h - 1 - r), (w - 1 - r, h - 1 - r)]
        if x < r and y < r:
            return (x - r) ** 2 + (y - r) ** 2 <= r * r
        if x > w - 1 - r and y < r:
            return (x - (w - 1 - r)) ** 2 + (y - r) ** 2 <= r * r
        if x < r and y > h - 1 - r:
            return (x - r) ** 2 + (y - (h - 1 - r)) ** 2 <= r * r
        if x > w - 1 - r and y > h - 1 - r:
            return (x - (w - 1 - r)) ** 2 + (y - (h - 1 - r)) ** 2 <= r * r
        return True

    rows = []
    for y in range(h):
        row = []
        for x in range(w):
            on_glyph = False
            gx = (x - sx) // scale
            gy = (y - sy) // scale
            if 0 <= gx < gw and 0 <= gy < gh and (x - sx) >= 0 and (y - sy) >= 0:
                if GLYPH_B[gy][gx] == "1":
                    on_glyph = True
            if not in_rounded(x, y):
                row.append((0, 0, 0, 0))
            elif on_glyph:
                row.append(fg)
            else:
                row.append(bg)
        rows.append(row)
    return rows


# App / dock icon: dark rounded square, white "b"
DARK = (17, 17, 17, 255)
WHITE = (255, 255, 255, 255)
for size in (32, 128, 256, 512):
    px = draw_glyph(size, size, WHITE, DARK, rounded=True)
    if size == 32:
        write_png(os.path.join(ICONS, "32x32.png"), size, size, px)
    elif size == 128:
        write_png(os.path.join(ICONS, "128x128.png"), size, size, px)
    elif size == 256:
        write_png(os.path.join(ICONS, "128x128@2x.png"), size, size, px)
    elif size == 512:
        write_png(os.path.join(ICONS, "icon.png"), size, size, px)

# Menu-bar tray icon: TEMPLATE style — black glyph on transparent, so macOS
# tints it white in dark menu bars automatically. 22x22@1x and 44x44@2x.
BLACK = (0, 0, 0, 255)
CLEAR = (0, 0, 0, 0)
write_png(os.path.join(ICONS, "tray.png"), 22, 22, draw_glyph(22, 22, BLACK, CLEAR))
write_png(os.path.join(ICONS, "tray@2x.png"), 44, 44, draw_glyph(44, 44, BLACK, CLEAR))

print("Wrote placeholder icons to", ICONS)
for f in sorted(os.listdir(ICONS)):
    print("  ", f)

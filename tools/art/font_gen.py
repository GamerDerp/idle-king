"""Builds the "Kotel" pixel fonts (regular, bold, title) as BMFont text files + PNG atlases.

Godot 4 imports `.fnt` (BMFont text format) as FontFile (importer `font_data_bmfont`).
Each font is a fixed-size bitmap font: use it at font_size = base_size * k (k integer),
see docs/ART.md. The UI uses k = 2.

    regular  size 12  (cap 7 px, x-height 5)       -> fonts/kotel_regular.fnt
    bold     size 12  (same metrics, 2 px stems)   -> fonts/kotel_bold.fnt
    title    size 16  (cap 11 px, bold)            -> fonts/kotel_title.fnt
"""
import os

from PIL import Image

from font_glyphs import G, SPACES

ROWS = 11          # rows 0..10 of the design grid
BASE = 9           # rows 0..8 are above the baseline
LINE = 12          # line height (one empty row below descenders)


def glyph_bitmap(ch: str) -> list:
    """Full-height (ROWS) bitmap of a regular glyph: list of lists of 0/1."""
    top, rows = G[ch]
    w = len(rows[0])
    bm = [[0] * w for _ in range(ROWS)]
    for i, r in enumerate(rows):
        for x, c in enumerate(r):
            if c == "#":
                bm[top + i][x] = 1
    return bm


def embolden(bm: list) -> list:
    """Pixel bold: widen 1-px gaps that dilation would close, then dilate right by 1."""
    h, w = len(bm), len(bm[0])
    gap_cols = set()
    for x in range(1, w - 1):
        for y in range(h):
            if not bm[y][x] and bm[y][x - 1] and bm[y][x + 1]:
                gap_cols.add(x)
                break
    cols = []
    for x in range(w):
        cols.append(x)
        if x in gap_cols:
            cols.append(x)
    wide = [[bm[y][x] for x in cols] for y in range(h)]
    w2 = len(cols) + 1
    out = [[0] * w2 for _ in range(h)]
    for y in range(h):
        for x in range(w2):
            out[y][x] = 1 if ((x < w2 - 1 and wide[y][x]) or (x > 0 and wide[y][x - 1])) else 0
    return out


# rows duplicated in the title variant: cap top, x-height top, middle bar, baseline
TITLE_DUP = (2, 4, 5, 8)


def stretch_rows(bm: list) -> list:
    out = []
    for y, row in enumerate(bm):
        out.append(list(row))
        if y in TITLE_DUP:
            out.append(list(row))
    return out


def outlined(bm: list) -> list:
    """Pads by 1 px and marks a 1-px outline ring with 2 (ink stays 1)."""
    h, w = len(bm), len(bm[0])
    out = [[0] * (w + 2) for _ in range(h + 2)]
    for y in range(h):
        for x in range(w):
            if bm[y][x]:
                out[y + 1][x + 1] = 1
    for y in range(h + 2):
        for x in range(w + 2):
            if out[y][x] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h + 2 and 0 <= xx < w + 2 and out[yy][xx] == 1:
                        out[y][x] = 2
                        break
    return out


def variant(name: str) -> dict:
    """Returns {'glyphs': {ch: bitmap}, 'base': int, 'line': int, 'size': int, 'spacing': int}."""
    glyphs = {}
    if name == "number":
        # bold with a baked 1-px black outline: white ink is tinted by font_color, black stays black
        for ch in G:
            glyphs[ch] = outlined(embolden(glyph_bitmap(ch)))
        return {"glyphs": glyphs, "base": BASE, "line": LINE, "size": LINE, "spacing": -1,
                "space": 3, "offset": -1}
    for ch in G:
        bm = glyph_bitmap(ch)
        if name in ("bold", "title"):
            bm = embolden(bm)
        if name == "title":
            bm = stretch_rows(bm)
        glyphs[ch] = bm
    if name == "title":
        base = BASE + sum(1 for r in TITLE_DUP if r < BASE)
        line = base + (ROWS - BASE) + 1
        return {"glyphs": glyphs, "base": base, "line": line, "size": line, "spacing": 1, "space": 4}
    return {"glyphs": glyphs, "base": BASE, "line": LINE, "size": LINE, "spacing": 1,
            "space": 3 if name == "regular" else 4}


def trim(bm: list) -> tuple:
    """(x0, y0, w, h) of the ink box; empty glyph -> (0,0,0,0)."""
    ys = [y for y, r in enumerate(bm) if any(r)]
    xs = [x for x in range(len(bm[0])) if any(r[x] for r in bm)]
    if not ys:
        return 0, 0, 0, 0
    return 0, ys[0], len(bm[0]), ys[-1] - ys[0] + 1


def build_font(name: str, out_dir: str) -> dict:
    v = variant(name)
    chars = sorted(v["glyphs"].keys(), key=ord)
    # pack into an atlas (shelf packing, 1 px padding)
    atlas_w, pad = 256, 1
    placements, x, y, shelf = {}, pad, pad, 0
    for ch in chars:
        bm = v["glyphs"][ch]
        _x0, y0, w, h = trim(bm)
        if x + w + pad > atlas_w:
            x, y, shelf = pad, y + shelf + pad, 0
        placements[ch] = (x, y, w, h, y0)
        x += w + pad
        shelf = max(shelf, h)
    atlas_h = 1
    while atlas_h < y + shelf + pad:
        atlas_h *= 2
    img = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))
    px = img.load()
    for ch in chars:
        ax, ay, w, h, y0 = placements[ch]
        bm = v["glyphs"][ch]
        for yy in range(h):
            for xx in range(w):
                if bm[y0 + yy][xx] == 1:
                    px[ax + xx, ay + yy] = (255, 255, 255, 255)
                elif bm[y0 + yy][xx] == 2:
                    px[ax + xx, ay + yy] = (0, 0, 0, 255)
    base_name = f"kotel_{name}"
    png = os.path.join(out_dir, base_name + ".png")
    img.save(png)
    lines = [
        f'info face="Kotel {name.title()}" size={v["size"]} bold={1 if name != "regular" else 0} italic=0 '
        f'charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1 outline=0',
        f'common lineHeight={v["line"]} base={v["base"]} scaleW={atlas_w} scaleH={atlas_h} pages=1 packed=0 '
        f'alphaChnl=0 redChnl={0 if name == "number" else 4} greenChnl={0 if name == "number" else 4} '
        f'blueChnl={0 if name == "number" else 4}',
        f'page id=0 file="{base_name}.png"',
    ]
    char_lines = []
    for ch in chars:
        ax, ay, w, h, y0 = placements[ch]
        off = v.get("offset", 0)
        char_lines.append(f"char id={ord(ch)} x={ax} y={ay} width={w} height={h} xoffset={off} yoffset={y0 + off} "
                          f"xadvance={w + v['spacing']} page=0 chnl=15")
    for sp, adv in SPACES.items():
        adv = v["space"] if sp in (" ", " ") else adv
        char_lines.append(f"char id={ord(sp)} x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 "
                          f"xadvance={adv} page=0 chnl=15")
    lines.append(f"chars count={len(char_lines)}")
    lines += char_lines
    lines.append("kernings count=0")
    fnt = os.path.join(out_dir, base_name + ".fnt")
    with open(fnt, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    imp = fnt + ".import"
    if not os.path.exists(imp):
        # integer-only scaling keeps the pixels crisp at 2x/3x
        with open(imp, "w", encoding="utf-8") as f:
            f.write('[remap]\n\nimporter="font_data_bmfont"\ntype="FontFile"\n\n'
                    '[params]\n\nfallbacks=[]\ncompress=true\nscaling_mode=1\n')
    v["placements"] = placements
    v["chars"] = chars
    return v


# ------------------------------------------------------------------ preview renderer

def text_width(v: dict, text: str) -> int:
    w = 0
    for ch in text:
        if ch in SPACES:
            w += v["space"] if ch in (" ", " ") else SPACES[ch]
        elif ch in v["glyphs"]:
            w += len(v["glyphs"][ch][0]) + v["spacing"]
    return w


def draw_text(img: Image.Image, v: dict, x: int, y: int, text: str, color: tuple, shadow: tuple = None) -> int:
    """Draws at 1x into img (top-left of the line box at x,y). Returns the advance."""
    px = img.load()
    cx = x
    for ch in text:
        if ch in SPACES:
            cx += v["space"] if ch in (" ", " ") else SPACES[ch]
            continue
        if ch not in v["glyphs"]:
            raise KeyError(f"glyph missing: {ch!r}")
        bm = v["glyphs"][ch]
        for yy, row in enumerate(bm):
            for xx, on in enumerate(row):
                if on:
                    if shadow is not None:
                        sx, sy = cx + xx + 1, y + yy + 1
                        if 0 <= sx < img.width and 0 <= sy < img.height and px[sx, sy] != color:
                            px[sx, sy] = shadow
                    if 0 <= cx + xx < img.width and 0 <= y + yy < img.height:
                        px[cx + xx, y + yy] = color
        cx += len(bm[0]) + v["spacing"]
    return cx - x

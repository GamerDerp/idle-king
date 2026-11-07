"""Conquest-map art kit (DESIGN §6): the parchment valley map, region fog, node markers, roads, effects.

The map is drawn in ART pixels at 2x the node coordinates of config/map.json (0..1000 x 0..700):
    art = ORIGIN + pos * SCALE      (ORIGIN = (200, 150), SCALE = 2; canvas 2400 x 1700)
and shown, like everything else, with an integer zoom. The region layout (centres, label spots, fog
placement) is written to config/map_layout.json; regions 0-2 follow the existing nodes, 3-7 are a proposal
following docs/CONTENT_PLAN.md, clockwise from the east: R1 E, R2 SE, R3 S, R4 SW, R5 NW, R6 N, R7 NE.

Style: an old hand-inked map - sepia ink (copper_0 / soot) on aged parchment, symbols instead of colour
fields, a few hand-tinted accents (teal water, brass, ember), burnt and torn edges.
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw

import palette as pal
from pixel import Canvas, cloud, from_ascii, poisson, rng

W, H = 2400, 1700
ORIGIN = (200, 150)
SCALE = 2
INK = "copper_0"

REGIONS = [
    # id, centre (map coords), bias (bigger = larger cell), label (map coords)
    {"id": 0, "center": (500, 370), "label": (500, 300)},
    {"id": 1, "center": (790, 330), "bias": 30, "label": (800, 200)},
    {"id": 2, "center": (870, 590), "bias": 10, "label": (900, 690 - 25)},
    {"id": 3, "center": (560, 610), "bias": 0, "label": (560, 685 - 10)},
    {"id": 4, "center": (220, 520), "bias": 20, "label": (210, 640)},
    {"id": 5, "center": (190, 190), "bias": 20, "label": (200, 60)},
    {"id": 6, "center": (500, 110), "bias": 0, "label": (480, 30)},
    {"id": 7, "center": (840, 100), "bias": 0, "label": (860, 30)},
]
R0_RADIUS = 118
FORTRESS = (500, 370)


def art(p):
    return (ORIGIN[0] + p[0] * SCALE, ORIGIN[1] + p[1] * SCALE)


# ------------------------------------------------------------------ numpy helpers

NAMES = pal.names()
IDX = {n: i for i, n in enumerate(NAMES)}
LUT = np.array([pal.rgb(n) for n in NAMES], dtype=np.uint8)


def smooth(w: int, h: int, cell: int, seed: int) -> np.ndarray:
    """Smooth value noise in [0, 1] (bicubic upscale of a random lattice)."""
    r = np.random.RandomState(seed)
    gw, gh = w // cell + 3, h // cell + 3
    g = (r.rand(gh, gw) * 255).astype(np.uint8)
    im = Image.fromarray(g, "L").resize((gw * cell, gh * cell), Image.BICUBIC)
    a = np.asarray(im, dtype=np.float32)[:h, :w] / 255.0
    return a


def to_image(ix: np.ndarray, alpha: np.ndarray) -> Image.Image:
    rgb = LUT[ix]
    return Image.fromarray(np.dstack([rgb, alpha.astype(np.uint8)]), "RGBA")


def dilate(m: np.ndarray, n: int) -> np.ndarray:
    out = m.copy()
    for _ in range(n):
        o = out.copy()
        o[1:, :] |= out[:-1, :]
        o[:-1, :] |= out[1:, :]
        o[:, 1:] |= out[:, :-1]
        o[:, :-1] |= out[:, 1:]
        out = o
    return out


# ------------------------------------------------------------------ region assignment

EXTRA_SEEDS = {
    0: [(500, 370), (470, 390), (520, 330)],
    1: [(930, 380), (720, 330), (980, 250), (660, 210)],
    2: [(960, 520), (720, 650), (990, 690), (940, 650)],
    3: [(560, 610), (460, 650), (640, 560), (380, 600), (560, 520)],
    4: [(220, 520), (110, 430), (290, 650), (330, 450), (60, 620), (180, 360)],
    5: [(190, 190), (70, 300), (300, 250), (240, 70), (60, 120)],
    6: [(500, 110), (420, 190), (600, 170), (380, 60), (520, 30)],
    7: [(840, 100), (970, 130), (720, 90), (780, 30), (990, 30)],
}


def region_map(nodes: list) -> np.ndarray:
    """Region id per art pixel: the nearest SEED wins, where seeds are every map node (with its region)
    plus a few anchor points per region (EXTRA_SEEDS) that give the regions without nodes their area.
    Coordinates are warped a little by noise so the borders wander like hand-drawn ones."""
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    mx = (xs - ORIGIN[0]) / SCALE
    my = (ys - ORIGIN[1]) / SCALE
    wx = mx + (smooth(W, H, 120, 3) - 0.5) * 16
    wy = my + (smooth(W, H, 120, 4) - 0.5) * 16
    seeds = [(n["pos"][0], n["pos"][1], n["region"]) for n in nodes]
    for r, pts in EXTRA_SEEDS.items():
        seeds += [(x, y, r) for (x, y) in pts]
    best = np.full((H, W), 1e9, dtype=np.float32)
    rid = np.zeros((H, W), dtype=np.uint8)
    for (sx, sy, r) in seeds:
        d = (wx - sx) ** 2 + (wy - sy) ** 2
        sel = d < best
        best[sel] = d[sel]
        rid[sel] = r
    return rid


def check_nodes(rid: np.ndarray, nodes: list) -> None:
    for n in nodes:
        x, y = art(n["pos"])
        got = int(rid[int(y), int(x)])
        if got != n["region"]:
            raise SystemExit(f"map: node {n['id']} at {n['pos']} lands in region {got}, not {n['region']}")


# ------------------------------------------------------------------ glyphs (ink symbols)

def glyph(rows: str, legend: dict = None) -> Canvas:
    lg = {"#": INK, "+": "soot_1", "o": "parchment_0", "-": "dust_1"}
    if legend:
        lg.update(legend)
    lines = rows.strip("\n").split("\n")
    w = max(len(l) for l in lines)
    c = Canvas(w, len(lines))
    for y, l in enumerate(lines):
        for x, ch in enumerate(l):
            if ch in lg:
                c.set(x, y, lg[ch])
    return c


MOUNT_TONES = {
    "earth": ("parchment_2", "dust_2", "dust_1"),       # lit face, shadow face, hatch
    "silver": ("steam_3", "iron_2", "iron_1"),
    "dark": ("iron_2", "iron_0", "soot_2"),
    "coal": ("dust_1", "dust_0", "soot_2"),
}


def mountain(seed: int, size: int = 1, peak: bool = False, tone: str = "earth") -> Canvas:
    """Hand-tinted ink mountain: lit left face, shaded right face with ink hatching, a jagged ridge,
    a snow cap on peaks, a ground line. size 0..4 -> about 14..46 px tall."""
    r = rng(seed)
    lit, shade, hatch = MOUNT_TONES[tone]
    h = int((13 + r.randint(0, 5)) * (1 + 0.45 * size))
    w = int(h * r.uniform(1.3, 1.7))
    c = Canvas(w + 3, h + 3)
    px = w // 2 + r.randint(-w // 8, w // 8)
    # ridge line wobble so the faces are not perfect triangles
    for y in range(1, h + 1):
        t = y / h
        xl = int(px - px * t + (r.random() - 0.5) * 0.8)
        xr = int(px + (w - px) * t)
        mid = px + int((r.random() - 0.5) * 2 * t)
        for x in range(xl, xr + 1):
            if x < mid:
                c.set(x, y, lit)
            else:
                c.set(x, y, shade)
                if (x + y * 2) % 4 == 0 and y > 2:
                    c.set(x, y, hatch)
    if peak:
        for y in range(1, max(3, h // 3)):
            t = y / h
            for x in range(int(px - px * t), int(px + (w - px) * t * 0.6) + 1):
                if (x + y) % 5 or y < 3:
                    c.set(x, y, "steam_3" if x < px else "steam_2")
    c.outline(INK)
    c.hline(0, w + 2, h + 1, None)
    c.hline(1, w + 1, h + 1, INK)
    return c


def hill(seed: int, tone: str = "earth") -> Canvas:
    r = rng(seed)
    lit, shade, hatch = MOUNT_TONES[tone]
    w = r.randint(18, 30)
    h = w // 3
    c = Canvas(w + 2, h + 3)
    for x in range(w + 1):
        top = int(h - h * math.sin(math.pi * x / w)) + 1
        for y in range(top, h + 1):
            c.set(x, y, lit if x < w * 0.5 else shade)
            if x >= w * 0.5 and (x + y) % 3 == 0:
                c.set(x, y, hatch)
    c.outline(INK)
    return c


def tree(seed: int, kind: str = "round") -> Canvas:
    """A single tinted tree: round (verdigris crown), brass (copper crown, brass trunk, gear tooth),
    pine (dark green spire), dead (ink only)."""
    r = rng(seed)
    if kind == "dead":
        return glyph("""
.#...#.
..#.#..
#..#..#
.#.#.#.
..###..
...#...
...#...
""")
    crowns = {"round": ("verdigris_2", "verdigris_1", "verdigris_0", "copper_1"),
              "brass": ("copper_3", "copper_2", "copper_1", "brass_2")}
    if kind == "pine":
        c = Canvas(9, 13)
        for y in range(1, 11):
            half = (y % 4 + y // 3) * 0.6 + 0.5
            for x in range(int(4 - half), int(4 + half) + 1):
                c.set(x, y, "verdigris_1" if x < 4 else "verdigris_0")
        c.vline(4, 10, 12, "copper_1")
        c.outline(INK)
        return c
    hi, mid, lo, trunk = crowns[kind]
    rad = r.uniform(3.2, 4.6)
    c = Canvas(12, 14)
    c.vline(6, 7, 12, trunk)
    c.vline(5, 9, 12, trunk)
    for y in range(14):
        for x in range(12):
            dx, dy = x + 0.5 - 6, y + 0.5 - 5.5
            if dx * dx + dy * dy <= rad * rad:
                lit = -(dx * 0.6 + dy * 0.8) / rad
                c.set(x, y, hi if lit > 0.4 else mid if lit > -0.35 else lo)
    if kind == "brass":
        c.set(4, 3, "brass_3")
        c.set(7, 6, "brass_3")
    c.outline(INK)
    return c


def forest(seed: int, kind: str = "round") -> Canvas:
    """A clump of 3-7 overlapping trees (back row first)."""
    r = rng(seed)
    n = r.randint(3, 7)
    c = Canvas(40, 26)
    pts = sorted([(r.randint(2, 26), r.randint(0, 10)) for _ in range(n)], key=lambda p: p[1])
    for i, (x, y) in enumerate(pts):
        t = tree(seed * 7 + i, kind if r.random() > 0.25 or kind == "brass" else "pine")
        c.paste_over(t, x, y)
    return c


def tuft(seed: int) -> Canvas:
    return glyph(["#.#.#\n.###.\n..#..", ".#..#\n#.##.\n.##..", "#..#.\n.#.#.\n..#.."][seed % 3],
                 {"#": "verdigris_0"}) if False else _tuft(seed)


def _tuft(seed: int) -> Canvas:
    r = rng(seed)
    c = Canvas(9, 7)
    for k in range(r.randint(3, 5)):
        x = 1 + k * 2 + r.randint(0, 1)
        h = r.randint(3, 6)
        for y in range(h):
            c.set(x + (1 if y > h - 2 and k % 2 else 0), 6 - y, "verdigris_1" if y < h - 1 else "verdigris_2")
    c.hline(0, 8, 6, INK)
    if r.random() < 0.5:
        c.hline(2, 6, 6, "teal_1")
    return c


def dune(seed: int) -> Canvas:
    r = rng(seed)
    w = r.randint(14, 24)
    c = Canvas(w, 6)
    for x in range(w):
        y = int(3 - 2.4 * math.sin(math.pi * x / w))
        c.set(x, y, INK if x < w * 0.65 else "dust_1")
        if x > w * 0.5:
            for yy in range(y + 1, 5):
                if (x + yy) % 2:
                    c.set(x, yy, "dust_2")
    return c


def rocks(seed: int) -> Canvas:
    r = rng(seed)
    c = Canvas(16, 9)
    for _ in range(r.randint(2, 4)):
        x, y, rad = r.randint(3, 12), r.randint(4, 6), r.uniform(1.6, 3.0)
        c.ellipse(x, y, rad + 0.4, rad * 0.8, "dust_2")
        c.ellipse(x - 0.6, y - 0.6, rad * 0.6, rad * 0.5, "parchment_2")
    c.outline(INK)
    return c


def house(seed: int) -> Canvas:
    """Little cottage / workshop with a copper roof (Предместья)."""
    r = rng(seed)
    w = r.choice((8, 10))
    c = Canvas(w + 2, 10)
    for y in range(0, 4):
        c.hline(4 - y, w - 4 + y + 1, y + 1, "copper_2" if y < 2 else "copper_1")
    c.rect(1, 5, w, 8, "parchment_2")
    c.set(3, 6, INK)
    c.vline(w - 2, 6, 8, "copper_0")
    c.outline(INK)
    return c


def slag(seed: int) -> Canvas:
    return hill(seed, "coal")


def headframe() -> Canvas:
    return glyph("""
.###.
#.#.#
.###.
.#.#.
#...#
#####
""")


def mast(seed: int) -> Canvas:
    """Sky-port mooring mast with a little moored balloon."""
    return glyph("""
..ssss.
.svvvvs
.svvvvs
..ssss.
...#...
...#...
..###..
...#...
...#...
..###..
""", {"s": INK, "v": "steam_3"})


def airship() -> Canvas:
    return glyph("""
...######...
.##vvvvvv##.
#vvvvvvvvvv#
.##vvvvvv##.
...######...
.....##.....
....#hh#....
....####....
""", {"v": "parchment_2", "h": "brass_2"})


def pool(seed: int) -> Canvas:
    """Quicksilver pool (R6): a silver lens of liquid in an ink outline."""
    r = rng(seed)
    w = r.randint(8, 14)
    c = Canvas(w + 2, 6)
    c.ellipse(w / 2 + 1, 3, w / 2, 2.2, "iron_2")
    c.hline(3, w - 3, 2, "steam_3")
    c.outline(INK)
    return c


def cloud_glyph(seed: int, r_: float = 7) -> Canvas:
    c = Canvas(int(r_ * 4), int(r_ * 3))
    cloud(c, r_ * 2, r_ * 1.6, r_, seed=seed, dark="parchment_0", mid="parchment_2", light="steam_3", tail=False)
    c.outline(INK)
    return c


def storm(seed: int) -> Canvas:
    c = Canvas(40, 40)
    cloud(c, 20, 12, 10, seed=seed, dark="iron_0", mid="iron_1", light="iron_2", tail=False)
    c.outline(INK)
    pts = [(18, 20), (15, 26), (19, 27), (14, 36)]
    for (a, b) in zip(pts, pts[1:]):
        c.line(a[0], a[1], b[0], b[1], "brass_3")
        c.line(a[0] + 1, a[1], b[0] + 1, b[1], "ember_2")
    return c


def farm(seed: int) -> Canvas:
    r = rng(seed)
    w, h = r.randint(10, 16), r.randint(6, 9)
    c = Canvas(w + 1, h + 1)
    c.frame(0, 0, w, h, INK)
    for x in range(2, w, 2):
        c.vline(x, 1, h - 1, "dust_1")
    return c


def fortress() -> Canvas:
    """The King's fortress in ink with brass roofs, inside its moat ring (centre of the map)."""
    c = Canvas(96, 80)
    c.ellipse(48, 46, 44, 30, "teal_1")
    c.ellipse(48, 46, 44, 30, "teal_1")
    for t in range(80):
        a = t / 80 * math.tau
        c.set(round(48 + math.cos(a) * 44), round(46 + math.sin(a) * 30), INK)
        c.set(round(48 + math.cos(a) * 40), round(46 + math.sin(a) * 26), INK)
        if t % 6 == 0:
            c.set(round(48 + math.cos(a) * 42), round(46 + math.sin(a) * 28), "teal_2")
    c.ellipse(48, 46, 39, 25, "parchment_1")
    # walls
    c.rect(22, 34, 74, 62, "parchment_2")
    c.frame(22, 34, 74, 62, INK)
    for x in range(22, 75, 4):
        c.rect(x, 31, x + 1, 33, INK)
    # towers
    for (tx, ty) in ((18, 28), (70, 28), (18, 56), (70, 56)):
        c.rect(tx, ty, tx + 8, ty + 10, "parchment_2")
        c.frame(tx, ty, tx + 8, ty + 10, INK)
        for x in range(tx + 1, tx + 8):
            h = 4 - abs(x - (tx + 4))
            c.vline(x, ty - h, ty - 1, "brass_2")
        c.set(tx + 3, ty - 4, "brass_3")
    # keep with the boiler stacks
    c.rect(38, 20, 58, 46, "parchment_2")
    c.frame(38, 20, 58, 46, INK)
    for x in range(38, 59):
        h = 8 - abs(x - 48) * 8 // 11
        c.vline(x, 20 - h, 19, "brass_2" if x < 48 else "brass_1")
    for sx in (41, 54):
        c.rect(sx, 4, sx + 2, 14, INK)
        cloud(c, sx + 2, 2, 2.2, seed=sx, dark="parchment_0", mid="parchment_2", light="steam_3", tail=False)
    c.rect(45, 52, 51, 62, INK)                    # gate
    c.rect(46, 54, 50, 62, "ember_1")
    c.set(48, 28, "ember_2")                       # lit window
    c.set(43, 30, "ember_1")
    c.set(53, 30, "ember_1")
    return c


def compass() -> Canvas:
    """96x96 compass rose: brass 8-point star, ink rings and ticks, a pixel «С» (север) at the top."""
    S = 96
    c = Canvas(S, S)
    cx = cy = 47.5
    for t in range(360):
        a = math.radians(t)
        for rr_ in (30, 33):
            c.set(round(cx + math.cos(a) * rr_), round(cy + math.sin(a) * rr_), INK)
    for t in range(0, 360, 10):
        a = math.radians(t)
        for rr_ in range(30, 30 + (5 if t % 90 == 0 else 3 if t % 45 == 0 else 2)):
            c.set(round(cx + math.cos(a) * rr_), round(cy + math.sin(a) * rr_), INK)
    for k in range(8):
        a = math.radians(-90 + k * 45)
        ln = 40 if k % 2 == 0 else 22
        wd = 6 if k % 2 == 0 else 4
        tip = (cx + math.cos(a) * ln, cy + math.sin(a) * ln)
        l = (cx + math.cos(a - math.pi / 2) * wd, cy + math.sin(a - math.pi / 2) * wd)
        r = (cx + math.cos(a + math.pi / 2) * wd, cy + math.sin(a + math.pi / 2) * wd)
        for half, col in ((l, "brass_3" if k % 2 == 0 else "brass_2"), (r, "brass_1" if k % 2 == 0 else "brass_0")):
            for s in range(0, 41):
                t = s / 40
                p0 = (cx + (half[0] - cx) * t, cy + (half[1] - cy) * t)
                c.line(round(p0[0]), round(p0[1]), round(tip[0]), round(tip[1]), col)
        c.line(round(cx), round(cy), round(tip[0]), round(tip[1]), INK)
    c.disc(cx, cy, 3.0, "brass_3")
    c.disc(cx, cy, 1.4, INK)
    c.outline(INK)
    c.ascii(44, 0, [".###", "#...", "#...", "#...", ".###"], {"#": INK})   # «С»
    for (x, y) in ((44, 0), (45, 0)):
        pass
    return c


def cartouche(w: int = 440, h: int = 72) -> Canvas:
    """Title cartouche: a parchment plate with an ink double frame, curled scroll ends and brass corner
    ornaments. The view writes the title (Kotel title font) into manifest/map_layout 'title_box'."""
    c = Canvas(w, h)
    x0, x1, y0, y1 = 22, w - 23, 8, h - 9
    c.rect(x0, y0, x1, y1, "parchment_2")
    c.frame(x0, y0, x1, y1, INK)
    c.frame(x0 + 3, y0 + 3, x1 - 3, y1 - 3, INK)
    c.hline(x0 + 1, x1 - 1, y1 + 1, "dust_1")
    for (sx, d) in ((x0, -1), (x1, 1)):                 # rolled scroll ends
        for k in range(6):
            cx_, cy_ = sx + d * (6 + k), (y0 + y1) / 2
            c.ellipse(sx + d * 9, cy_, 9, (y1 - y0) / 2 + 2, "parchment_1")
        c.ellipse(sx + d * 9, (y0 + y1) / 2, 9, (y1 - y0) / 2 + 2, "parchment_1")
        for t in range(220):
            a = t / 220 * math.tau
            c.set(round(sx + d * 9 + math.cos(a) * 9), round((y0 + y1) / 2 + math.sin(a) * ((y1 - y0) / 2 + 2)), INK)
        for t in range(80):
            a = t / 80 * math.tau
            c.set(round(sx + d * 9 + math.cos(a) * 4), round((y0 + y1) / 2 + math.sin(a) * 6), INK)
        c.set(sx + d * 9, (y0 + y1) // 2, "brass_2")
    for (cx_, cy_) in ((x0 + 3, y0 + 3), (x1 - 3, y0 + 3), (x0 + 3, y1 - 3), (x1 - 3, y1 - 3)):
        c.disc(cx_, cy_, 3.0, "brass_2")
        c.set(cx_ - 1, cy_ - 1, "brass_3")
        c.set(cx_, cy_, INK)
    for x in range(x0 + 14, x1 - 13, 6):               # tiny ink scallop along the top and bottom borders
        c.set(x, y0 + 1, INK)
        c.set(x, y1 - 1, INK)
    # a gear ornament at the top centre
    gx, gy = w // 2, y0
    for t in range(16):
        a = t / 16 * math.tau
        rr_ = 6 + (1.5 if t % 2 == 0 else 0)
        c.set(round(gx + math.cos(a) * rr_), round(gy + math.sin(a) * rr_ * 0.8), INK)
    c.disc(gx, gy, 5.0, "brass_2")
    c.disc(gx, gy, 2.0, INK)
    return c


# ------------------------------------------------------------------ the big map

RIVER = [(660, -20), (640, 60), (600, 140), (628, 220), (612, 290), (585, 335), (575, 420), (540, 500),
         (552, 560), (590, 615), (575, 690), (600, 740)]
LAKE = (585, 640, 50, 22)        # marsh lake in R3 (map coords: cx, cy, rx, ry)
CLIFF = [(-60, 300), (0, 285), (25, 250), (18, 200), (48, 160), (36, 110), (66, 70), (58, 20), (80, -40)]


def catmull(pts: list, n: int) -> list:
    """Catmull-Rom spline through pts, n samples per segment."""
    out = []
    p = [pts[0]] + pts + [pts[-1]]
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                     + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(2)))
    out.append(pts[-1])
    return out


def label_rects() -> dict:
    out = {}
    for r in REGIONS:
        x, y = art(r["label"])
        out[r["id"]] = (x - 120, y - 18, x + 120, y + 18)
    return out


def build_map(nodes: list):
    """Returns (map Image RGBA, region id array, layout dict)."""
    rid = region_map(nodes)
    check_nodes(rid, nodes)
    ys, xs = np.mgrid[0:H, 0:W]
    # --- aged parchment: one warm tone, lighter towards the middle, darker towards the edges, a few
    # soft stains and rare foxing spots (no camouflage blobs)
    n1 = smooth(W, H, 260, 11)
    n2 = smooth(W, H, 70, 12)
    n3 = smooth(W, H, 10, 13)
    cxn, cyn = (xs - W / 2) / (W / 2), (ys - H / 2) / (H / 2)
    vig = np.sqrt(cxn ** 2 * 0.9 + cyn ** 2) + (n1 - 0.5) * 0.5
    ix = np.full((H, W), IDX["parchment_1"], dtype=np.uint8)
    ix[(vig < 0.62)] = IDX["parchment_2"]
    ix[vig > 1.02] = IDX["parchment_0"]
    ix[(n3 > 0.93) & (n2 > 0.62)] = IDX["dust_2"]                # foxing spots
    # --- region borders: dashed ink line + a darker parchment band just inside each region
    b = np.zeros((H, W), dtype=bool)
    b[:, 1:] |= rid[:, 1:] != rid[:, :-1]
    b[1:, :] |= rid[1:, :] != rid[:-1, :]
    band = dilate(b, 7) & ~b
    ix[band & (ix == IDX["parchment_1"])] = IDX["parchment_0"]
    ix[band & (ix == IDX["parchment_2"])] = IDX["parchment_1"]
    dash = ((xs + ys) // 5) % 2 == 0
    ix[dilate(b, 1) & dash] = IDX[INK]
    # --- faint rhumb lines from the compass point (old-map flavour)
    cpx, cpy = 300, 1450
    ang = np.degrees(np.arctan2(ys - cpy, xs - cpx))
    for a0 in range(-90, 1, 15):
        near = np.abs(((ang - a0 + 180) % 360) - 180) < 0.05
        ix[near & (ix != IDX[INK])] = IDX["parchment_0"]
    # --- burnt, torn edge
    e = np.minimum(np.minimum(xs, W - 1 - xs), np.minimum(ys, H - 1 - ys)).astype(np.float32)
    e = e + (smooth(W, H, 90, 21) - 0.5) * 70 + (smooth(W, H, 18, 22) - 0.5) * 14 - 44
    alpha = np.where(e < 0, 0, 255).astype(np.uint8)
    ix[(e >= 0) & (e < 2)] = IDX["soot_1"]
    ix[(e >= 2) & (e < 4)] = IDX["copper_0"]
    ix[(e >= 4) & (e < 7)] = IDX["dust_1"]
    ix[(e >= 7) & (e < 12) & (ix != IDX[INK])] = IDX["dust_2"]
    ix[(e >= 12) & (e < 22) & (ix == IDX["parchment_1"])] = IDX["parchment_0"]
    img = to_image(ix, alpha)
    dr = ImageDraw.Draw(img)

    def col(n):
        return pal.rgba(n)

    # --- cloud sea beyond the sky-port cliffs (north-west corner)
    cliff = [art(p) for p in CLIFF]
    poly = cliff + [(0, -60), (-60, -60), (-60, H)]
    sea = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sea).polygon([(x, y) for x, y in cliff] + [(-50, cliff[-1][1]), (-50, cliff[0][1])], fill=255)
    seam = (np.asarray(sea) > 0) & (alpha > 0)
    arr = np.array(img)
    arr[seam, :3] = LUT[IDX["steam_2"]]
    img = Image.fromarray(arr, "RGBA")
    # cloud-sea tops: lobed clouds with ink outlines, lighter tops
    sea_c = Canvas(W, H)
    for (x, y) in poisson(0, 0, 260, H, 26, 33):
        if seam[min(H - 1, y), min(W - 1, x)]:
            cloud(sea_c, x, y, rng(x + y).uniform(10, 18), seed=x * 7 + y, dark="steam_1", mid="steam_2",
                  light="steam_3", tail=False)
    sea_img = Image.fromarray(np.where(seam[..., None], np.asarray(sea_c.img), 0).astype(np.uint8), "RGBA")
    img.alpha_composite(sea_img)
    dr = ImageDraw.Draw(img)
    dr.line(cliff, fill=col(INK), width=3)
    for i in range(len(cliff) - 1):                   # cliff hatching on the land side
        (x0, y0), (x1, y1) = cliff[i], cliff[i + 1]
        for t in np.linspace(0, 1, 12):
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            dr.line([(x + 2, y), (x + 9, y + 4)], fill=col(INK), width=1)
    # --- river (ink banks, teal water, a light ripple line) and the marsh lake
    rv = catmull([art(p) for p in RIVER], 10)
    n_ = len(rv)
    for i in range(n_ - 1):                       # widens downstream
        wdt = 3 + int(5 * i / n_)
        dr.line([rv[i], rv[i + 1]], fill=col(INK), width=wdt + 4)
    for i in range(n_ - 1):
        wdt = 3 + int(5 * i / n_)
        dr.line([rv[i], rv[i + 1]], fill=col("teal_1"), width=wdt)
    for i in range(0, n_ - 1, 3):
        dr.line([(rv[i][0] - 1, rv[i][1]), (rv[i + 1][0] - 1, rv[i + 1][1])], fill=col("teal_2"), width=1)
    lx, ly = art(LAKE[:2])
    lrx, lry = LAKE[2] * SCALE, LAKE[3] * SCALE
    lake = [(lx + math.cos(t) * lrx * (1 + 0.18 * math.sin(3 * t + 1)), ly + math.sin(t) * lry * (1 + 0.15 * math.cos(2 * t)))
            for t in np.linspace(0, math.tau, 48)]
    dr.polygon(lake, fill=col(INK))
    dr.polygon([(lx + (x - lx) * 0.94, ly + (y - ly) * 0.9) for x, y in lake], fill=col("teal_1"))
    for k in range(5):
        yy = ly - lry // 2 + k * lry // 4
        dr.line([(lx - lrx // 2 + k * 9, yy), (lx - lrx // 2 + k * 9 + 26, yy)], fill=col("teal_2"), width=1)
    # --- symbols per region, blue-noise placed, never on labels / nodes / fortress / title
    labels = label_rects()
    node_pts = [art(n["pos"]) for n in nodes]
    title = (W // 2 - 220, 26, W // 2 + 220, 98)
    keep_out = list(labels.values()) + [title, (cpx - 56, cpy - 56, cpx + 56, cpy + 56), (ORIGIN[0] + 380 * 2, ORIGIN[1] + 300 * 2, ORIGIN[0] + 620 * 2,
                                                ORIGIN[1] + 440 * 2)]

    def free(x, y, w, h):
        if x < 30 or y < 30 or x + w > W - 30 or y + h > H - 30:
            return False
        if alpha[min(H - 1, y + h), min(W - 1, x + w // 2)] == 0 or seam[min(H - 1, y + h), min(W - 1, x)]:
            return False
        for (a, b_, c_, d) in keep_out:
            if x < c_ and x + w > a and y < d and y + h > b_:
                return False
        for (px, py) in node_pts:
            if abs(px - (x + w / 2)) < w / 2 + 16 and abs(py - (y + h / 2)) < h / 2 + 16:
                return False
        return True

    stamps = []

    clus = smooth(W, H, 110, 41)

    def place(region, maker, r_, seed, prob=1.0, cluster=0.0):
        rr = rng(seed)
        for (x, y) in poisson(0, 0, W, H, r_, seed):
            if int(rid[y, x]) != region or rr.random() > prob:
                continue
            if cluster and rr.random() > max(0.0, (clus[y, x] - 0.5 + cluster * 0.1) * 4):
                continue
            g = maker(x * 31 + y)
            gx, gy = x - g.w // 2, y - g.h
            if free(gx, gy, g.w, g.h):
                stamps.append((y, gx, gy, g))

    place(0, farm, 30, 101, 0.8, cluster=1)
    place(0, house, 26, 103, 0.7, cluster=1)
    place(0, lambda s: forest(s, "round"), 60, 102, 0.6, cluster=1)
    place(1, dune, 26, 111, 0.8, cluster=1)
    place(1, rocks, 44, 112, 0.6)
    place(2, lambda s: hill(s, "coal"), 30, 121, 0.9, cluster=1)
    place(2, lambda s: headframe(), 70, 122, 0.8)
    place(3, tuft, 16, 131, 0.9, cluster=1)
    place(3, lambda s: tree(s, "dead"), 46, 132, 0.6)
    place(4, lambda s: forest(s, "brass"), 22, 141, 1.0, cluster=2)
    place(5, mast, 80, 152, 0.8)
    place(5, lambda s: mountain(s, 0, tone="earth"), 44, 153, 0.7, cluster=1)
    place(5, lambda s: forest(s, "round"), 70, 154, 0.5, cluster=1)
    place(6, lambda s: mountain(s, 1, tone="silver"), 38, 161, 1.0, cluster=2)
    place(6, pool, 60, 162, 0.7)
    place(7, lambda s: mountain(s, 2, peak=True, tone="dark"), 48, 171, 1.0, cluster=2)
    place(7, lambda s: mountain(s, 0, tone="dark"), 40, 172, 0.5, cluster=1)
    stamps.sort(key=lambda s: s[0])
    for (_y, x, y, g) in stamps:
        img.alpha_composite(g.img, (int(x), int(y)))
    # --- feature pieces: storm peak, airship, fortress, compass, cartouche
    sx, sy = art((850, 70))
    img.alpha_composite(storm(7).img, (int(sx) - 20, int(sy) - 30))
    big = mountain(77, 4, peak=True, tone="dark")
    img.alpha_composite(big.img, (int(sx) - big.w // 2, int(sy) + 2))
    ax, ay = art((120, 250))
    img.alpha_composite(airship().img, (int(ax), int(ay)))
    fx, fy = art(FORTRESS)
    fo = fortress()
    img.alpha_composite(fo.img, (int(fx) - fo.w // 2, int(fy) - fo.h // 2 - 6))
    co = compass()
    img.alpha_composite(co.img, (cpx - co.w // 2, cpy - co.h // 2))
    ca = cartouche()
    img.alpha_composite(ca.img, (W // 2 - ca.w // 2, 26))
    layout = {
        "_comment": "Generated by tools/art/gen_art.py (sprites_map.py). Map art px = origin + node pos * scale. "
                    "Regions 0-2 follow config/map.json; 3-7 are the proposed layout (CONTENT_PLAN).",
        "art_size": [W, H], "origin": list(ORIGIN), "scale": SCALE,
        "fortress": list(FORTRESS),
        "title_box": [W // 2 - 196, 40, 392, 44],
        "compass": [cpx, cpy],
        "regions": [],
    }
    for r in REGIONS:
        ys_, xs_ = np.nonzero((rid == r["id"]) & (alpha > 0))
        bbox = [int(xs_.min()), int(ys_.min()), int(xs_.max()), int(ys_.max())]
        lx_, ly_ = art(r["label"])
        layout["regions"].append({"id": r["id"], "center": list(r["center"]), "label": [int(lx_), int(ly_)],
                                  "bbox": bbox, "fog": None if r["id"] == 0 else f"map_fog_r{r['id']}",
                                  "fog_pos": None})
    return img, rid, alpha, layout


# ------------------------------------------------------------------ fog of war

def _swirl(c: Canvas, x: float, y: float, r: float, name: str) -> None:
    """Decorative old-map cloud curl: a spiral stroke ending in a flick."""
    for k in range(int(r * 9)):
        t = k / (r * 9)
        a = t * math.tau * 1.4
        rr_ = r * (1 - t * 0.75)
        c.set(round(x + math.cos(a) * rr_), round(y + math.sin(a) * rr_ * 0.6), name)
    c.line(round(x + r), round(y), round(x + r * 2.2), round(y + r * 0.15), name)


def region_fog(rid: np.ndarray, alpha: np.ndarray, region: int, seed: int):
    """«Terra incognita» over one region: a flat ink-wash (parchment_0) that fills the region a little
    past its border, a lumpy cloud rim (big lobes lit top-left with an ink underline) along its edge,
    and sparse decorative cloud curls inside. Returns (Image, (x, y) art position)."""
    mask = dilate((rid == region) & (alpha > 0), 12)
    ys, xs = np.nonzero(mask)
    x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    m = mask[y0:y1, x0:x1]
    h, w = m.shape
    inner = m & ~dilate(~m, 18)
    ix = np.where(m, IDX["parchment_1"], 0).astype(np.uint8)
    al = np.where(inner, 250, 0).astype(np.uint8)
    # lobes along the rim (centres in the band between the border and 18 px inside)
    band = m & ~inner
    yy, xx = np.mgrid[0:h, 0:w]
    rr = rng(seed)
    pts = [(x, y) for (x, y) in poisson(0, 0, w, h, 16, seed) if band[min(h - 1, y), min(w - 1, x)]]
    pts.sort(key=lambda p: -p[1])
    for (cx, cy) in pts:
        r = rr.uniform(14, 24)
        xa, xb = max(0, int(cx - r) - 1), min(w, int(cx + r) + 2)
        ya, yb = max(0, int(cy - r) - 1), min(h, int(cy + r) + 2)
        dx = xx[ya:yb, xa:xb] + 0.5 - cx
        dy = yy[ya:yb, xa:xb] + 0.5 - cy
        inside = dx * dx + dy * dy <= r * r
        hl = (dx + r * 0.3) ** 2 + (dy + r * 0.35) ** 2 <= (r * 0.62) ** 2
        tone = np.where(hl, IDX["parchment_2"], IDX["parchment_1"])
        under = inside & ((dx - 1.2) ** 2 + (dy - 1.6) ** 2 > (r - 1.0) ** 2) & (dy > r * 0.1)
        ix[ya:yb, xa:xb][inside] = tone[inside]
        al[ya:yb, xa:xb][inside] = 250
        ix[ya:yb, xa:xb][under] = IDX["parchment_0"]
    img = to_image(ix, al)
    # decorative curls inside
    curl = Canvas(w, h)
    for (cx, cy) in poisson(0, 0, w, h, 70, seed + 1):
        if inner[min(h - 1, cy), min(w - 1, cx)] and inner[min(h - 1, cy + 6), min(w - 1, cx + 14)]:
            _swirl(curl, cx, cy, rr.uniform(6, 10), "parchment_0")
            if rr.random() < 0.5:
                _swirl(curl, cx + 16, cy + 5, rr.uniform(4, 6), "parchment_0")
    img.alpha_composite(curl.img)
    return img, (int(x0), int(y0))


def fog_wisp_frames() -> list:
    """48x28 drifting ink-wash puff (4-frame loop) to scatter over the fog for life; anchor (24, 20)."""
    out = []
    for f in range(4):
        c = Canvas(48, 28)
        for j, (sx, sy, r) in enumerate([(14, 16, 7), (26, 13, 8), (36, 17, 6)]):
            cloud(c, sx + f * 1.5 + j * 0.5 * (f % 2), sy - (f % 2), r, seed=300 + j,
                  dark="dust_2", mid="parchment_0", light="parchment_1", alpha=235, tail=False)
        c.outline(INK)
        out.append(c)
    return out


def fog_burn_frames() -> list:
    """64x48 the fog burns away (7 frames, once), anchor (32, 30): a glowing ember rim eats the cloud from
    the edge in, ash flecks drift up, nothing is left. Scatter several over a region when it opens."""
    out = []
    for f in range(7):
        c = Canvas(64, 48)
        t = f / 6
        rr = rng(320)
        lobes = [(20, 26, 13), (34, 20, 15), (46, 28, 12), (30, 32, 12)]
        for (x, y, r) in lobes:
            rad = r * (1 - t * 0.95)
            if rad < 1:
                continue
            for yy in range(int(y - rad) - 1, int(y + rad) + 2):
                for xx in range(int(x - rad) - 1, int(x + rad) + 2):
                    d = math.hypot(xx + 0.5 - x, yy + 0.5 - y)
                    if d <= rad:
                        if d > rad - 1.4 and f > 0:
                            c.set(xx, yy, "ember_2" if (xx + yy + f) % 3 else "brass_3")
                        elif d > rad - 2.6 and f > 0:
                            c.set(xx, yy, "ember_0")
                        else:
                            c.set(xx, yy, "parchment_1" if (xx - x) + (yy - y) < -rad * 0.4 else "parchment_0")
        for k in range(10):                          # ash and sparks rising
            ax = 10 + rr.randint(0, 44)
            ay = 40 - f * 5 - rr.randint(0, 10)
            if 0 <= ay < 48 and f > 0:
                c.set(ax + (k % 3) - 1, ay, "soot_1" if k % 3 else "ember_2")
        out.append(c)
    return out


# ------------------------------------------------------------------ node markers

GLYPHS = {
    "spine": """
..#......
..####...
..#####..
..####...
..#......
..#......
..#......
.###.....
#####....
""",
    "tower": """
...###...
...#.#...
.#######.
.#.....##
.#######.
..#...#..
..#...#..
.#######.
.........
""",
    "bait": """
.........
.......##
.....###.
...####..
.#####...
###.#....
.#..#....
....#....
.........
""",
    "lens": """
..####...
.#....#..
#..#...#.
#.#....#.
#......#.
.#....#..
..#####..
......##.
.......##
""",
    "mechanism": """
...#.#...
..#####..
.##...##.
###.#.###
.#.###.#.
###.#.###
.##...##.
..#####..
...#.#...
""",
    "moat": """
.........
.##..##..
#..##..##
.........
.##..##..
#..##..##
.........
.##..##..
#..##..##
""",
    "synergy": """
.........
.###.....
#...#....
#..#####.
#..#.#..#
.###.#..#
.....#..#
.....###.
.........
""",
    "global": """
....#....
....#....
...###...
#########
.#######.
..#####..
..##.##..
.##...##.
.#.....#.
""",
    "boss": """
..#####..
.#######.
##..#..##
##..#..##
#########
.###.###.
..#####..
..#.#.#..
.........
""",
    "reward": """
#.#####.#
#.#####.#
.#######.
..#####..
...###...
....#....
...###...
..#####..
.........
""",
    "region": """
..#####..
.#.....#.
#.......#
#.#####.#
#.#...#.#
#.#...#.#
#.#...#.#
#.#...#.#
###...###
""",
    "choice": """
....#....
.#######.
.######..
....#....
..######.
.#######.
....#....
....#....
...###...
""",
    "producer": """
.......#.
.......#.
.#.....#.
.#..#..#.
.##.##.#.
#########
#.#.#.#.#
#########
.........
""",
}
MAJOR = ("spine", "boss", "region", "global", "choice")
STATES = {"locked": 0, "available": [1, 2, 3], "purchased": 4, "maxed": 5, "excluded": 6}


def _glyph_on(c: Canvas, kind: str, cx: int, cy: int, name: str, bold: bool) -> None:
    rows = GLYPHS[kind].strip("\n").split("\n")
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == "#":
                c.set(cx - 4 + x, cy - 4 + y, name)
                if bold:
                    c.set(cx - 4 + x + 1, cy - 4 + y, name) if (x + 1 < len(row) and row[x + 1] != "#") else None


def node_marker(kind: str, state: str, phase: int = 0) -> Canvas:
    """One frame of a map node marker. Minor kinds 16x16 (r 6.5), major kinds 24x24 (r 10.5).
    locked: faint ink ring + faint glyph; available: ink ring on clean parchment, brass dots orbiting
    (3 phases); purchased: brass-filled medallion, dark glyph, red wax stamp; maxed: purchased + a
    second brass rim and a star glint; excluded: faint and crossed out in red-brown ink."""
    major = kind in MAJOR
    S = 24 if major else 16
    c = Canvas(S, S)
    cx = cy = (S - 1) / 2
    R = 10.5 if major else 6.5
    star = kind == "global"

    def inside(x, y, r):
        dx, dy = x + 0.5 - (cx + 0.5), y + 0.5 - (cy + 0.5)
        if star:
            a = math.atan2(dy, dx)
            rr_ = r * (0.78 + 0.22 * abs(math.cos(a * 4)))
            return dx * dx + dy * dy <= rr_ * rr_
        return dx * dx + dy * dy <= r * r

    filled = state in ("purchased", "maxed")
    for y in range(S):
        for x in range(S):
            if inside(x, y, R):
                if not inside(x, y, R - 1.2):
                    c.set(x, y, {"locked": "parchment_0", "excluded": "parchment_0"}.get(state, "soot_1" if filled else INK))
                elif filled:
                    lit = -((x - cx) * 0.6 + (y - cy) * 0.8) / R
                    c.set(x, y, "brass_3" if lit > 0.35 else "brass_2" if lit > -0.35 else "brass_1")
                elif state == "available":
                    c.set(x, y, "parchment_2")
    if kind == "boss":                              # banner tails under the medallion
        for k, x in enumerate((int(cx) - 5, int(cx) + 3)):
            for y in range(int(cy) + 8, S):
                c.hline(x, x + 2, y, "ember_1" if state not in ("locked", "excluded") else "parchment_0")
            c.set(x + 1, S - 1, None)
    g = {"locked": "parchment_0", "excluded": "parchment_0", "available": INK}.get(state, "soot_1")
    _glyph_on(c, kind, int(cx), int(cy), g, False)
    if state == "available":       # a brass halo ring with a bright arc that runs round (pulse)
        n = 40
        for k in range(n):
            a = k / n * math.tau
            seg = (k * 3 // n - phase) % 3
            c.set(round(cx + math.cos(a) * (R + 1.0)), round(cy + math.sin(a) * (R + 1.0)),
                  "brass_3" if seg == 0 else "brass_2" if seg == 1 else "brass_0")
    if filled:
        sx, sy = int(cx + R * 0.55), int(cy + R * 0.55)        # wax stamp
        c.disc(sx, sy, 2.4 if major else 1.8, "ember_1")
        c.set(sx - 1, sy - 1, "ember_2")
        c.set(sx, sy, "ember_0")
    if state == "maxed":           # a solid gilded outer rim + star glints at the 4 diagonals
        for t in range(48):
            a = t / 48 * math.tau
            c.set(round(cx + math.cos(a) * (R + 1.0)), round(cy + math.sin(a) * (R + 1.0)),
                  "brass_3" if math.cos(a) + math.sin(a) < 0 else "brass_1")
        for a in (math.pi * 1.25,):
            gx, gy = round(cx + math.cos(a) * (R - 2)), round(cy + math.sin(a) * (R - 2))
            for (dx, dy) in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                c.set(gx + dx, gy + dy, "parchment_2" if (dx, dy) == (0, 0) else "steam_3")
    if state == "excluded":
        for k in range(-int(R), int(R) + 1):
            c.set(int(cx) + k, int(cy) + k, "ember_0")
            c.set(int(cx) + k, int(cy) - k, "ember_0")
    return c


def node_frames(kind: str) -> list:
    return [node_marker(kind, "locked"), node_marker(kind, "available", 0), node_marker(kind, "available", 1),
            node_marker(kind, "available", 2), node_marker(kind, "purchased"), node_marker(kind, "maxed"),
            node_marker(kind, "excluded")]


# ------------------------------------------------------------------ roads and effects

def road_dot_frames() -> list:
    """4x4 road dot, 3 frames: 0 locked (faint), 1 open (ink), 2 conquered (brass with an ink rim).
    Recipe: place a dot every 7 art px along a node-to-node segment, leaving 10 px free at both ends."""
    out = []
    for f, (a, b) in enumerate((("parchment_0", "parchment_0"), (INK, INK), ("brass_3", "brass_1"))):
        c = Canvas(4, 4)
        c.rect(1, 1, 2, 2, b)
        c.set(1, 1, a)
        if f == 2:
            c.outline(INK)
        out.append(c)
    return out


def spark_frames() -> list:
    """9x9 spark that travels along a road to the next nodes after a purchase (4-frame loop)."""
    out = []
    for f in range(4):
        c = Canvas(9, 9)
        r = (3, 4, 3, 2)[f]
        for k in range(-r, r + 1):
            c.set(4 + k, 4, "brass_3" if abs(k) < 2 else "brass_2")
            c.set(4, 4 + k, "brass_3" if abs(k) < 2 else "brass_2")
        if f % 2 == 0:
            for (dx, dy) in ((-2, -2), (2, -2), (-2, 2), (2, 2)):
                c.set(4 + dx, 4 + dy, "ember_2")
        c.set(4, 4, "parchment_2")
        out.append(c)
    return out


def ink_splat_frames() -> list:
    """40x40 purchase splat (6 frames, once), anchor (20, 20): an ink drop lands, spreads with droplets,
    then thins out (the brass marker underneath shows through at the end)."""
    out = []
    rr = rng(330)
    drops = [(rr.uniform(0, math.tau), rr.uniform(9, 17), rr.uniform(1, 2.2)) for _ in range(9)]
    for f in range(6):
        c = Canvas(40, 40)
        t = min(1.0, f / 3)
        R = 4 + 9 * t
        f_ = 0.0 if f < 4 else (f - 3) / 3
        for y in range(40):
            for x in range(40):
                dx, dy = x + 0.5 - 20, y + 0.5 - 20
                a = math.atan2(dy, dx)
                rad = R * (0.85 + 0.15 * math.sin(a * 5 + 1))
                d = math.hypot(dx, dy)
                if d <= rad and not (f_ > 0 and d < rad * f_):
                    c.set(x, y, INK if d > rad - 1.5 or (x + y) % 5 else "soot_1")
        for (a, dist, s) in drops:
            d = dist * (0.4 + 0.6 * t)
            if f_ < 0.9:
                c.disc(20 + math.cos(a) * d, 20 + math.sin(a) * d, s * (1 - f_), INK)
        out.append(c)
    return out


def stamp_frames() -> list:
    """28x28 red wax seal pressed onto a bought node (5 frames, once), anchor (14, 14): it drops in large,
    squashes, settles with a brass gear imprint, then the view removes it (the marker keeps a small stamp)."""
    out = []
    for f, (r, lift) in enumerate(((11, -6), (9, -2), (8.5, 0), (8, 0), (8, 0))):
        c = Canvas(28, 28)
        cy = 14 + lift
        c.disc(14, cy, r, "ember_0")
        c.disc(13.5, cy - 0.5, r - 1.2, "ember_1")
        c.disc(12, cy - 2, r * 0.35, "ember_2")
        if f >= 2:
            for t in range(12):
                a = t / 12 * math.tau
                rr_ = 4 + (1 if t % 2 == 0 else 0)
                c.set(round(14 + math.cos(a) * rr_), round(cy + math.sin(a) * rr_), "brass_2")
            c.disc(14, cy, 1.5, "ember_0")
        if f == 2:
            for (dx, dy) in ((-10, 4), (10, 3), (-8, -6), (9, -7)):
                c.set(14 + dx, cy + dy, "ember_1")
        c.outline(INK)
        out.append(c)
    return out


def progress_frame() -> Canvas:
    """260x52 progress cartouche for «Долина покорена на N%»: a parchment scroll plate; text line
    x 34..225, y 12..26; bar slot x 36..223, y 31..38 (fill it with map_progress_fill tiles)."""
    c = cartouche(260, 52)
    c.rect(36, 31, 223, 38, "parchment_0")
    c.frame(35, 30, 224, 39, INK)
    for x in range(55, 224, 19):
        c.vline(x, 30, 31, INK)
    return c


def progress_fill() -> Canvas:
    """4x8 brass bar fill tile (tile horizontally inside the bar slot)."""
    c = Canvas(4, 8)
    for y, n in enumerate(("brass_3", "brass_3", "brass_2", "brass_2", "brass_2", "brass_1", "brass_1", "brass_0")):
        c.hline(0, 3, y, n)
    c.set(0, 0, "parchment_2")
    return c


def map_card() -> Canvas:
    """16x16 9-slice texture for the map tooltip (theme variation MapCard): a pinned parchment note with a
    torn-looking ink edge, a soft drop shadow (bottom/right) and a brass pin in the top-left corner."""
    c = Canvas(16, 16)
    c.rect(0, 0, 14, 14, "parchment_2")
    c.frame(0, 0, 14, 14, INK)
    c.hline(1, 15, 15, "soot_1")
    c.vline(15, 1, 15, "soot_1")
    c.hline(1, 13, 13, "parchment_1")
    c.vline(13, 1, 13, "parchment_1")
    c.set(0, 0, None)
    c.set(14, 0, None)
    c.disc(3, 3, 1.6, "brass_2")
    c.set(2, 2, "brass_3")
    c.set(3, 3, "brass_0")
    return c


def write_layout(root: str, layout: dict) -> None:
    path = os.path.join(root, "config", "map_layout.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(layout, f, indent=1, ensure_ascii=False)
        f.write("\n")

"""Battlefield backgrounds, one per region: a shared fortress side + a region field.

    compose_bg(region) -> (Canvas 450x340, smoke_points)
Region 1 «Ржавые пустоши» (dry dust), 2 «Угольные копи» (coal-dark ground, rails), 3 «Медные болота» (marsh).
Small ground details are scattered with blue noise (Poisson disc), patches are irregular blobs, edge
vegetation is placed in uneven clusters: no 16/32-px lattice is visible anywhere.
"""
import math

import layout as L
import sprites_world as WO
from pixel import C, Canvas, fill_shape, from_ascii, organic, poisson, rng, wobble

# per-region ground colours. ground = most of the field (enemy contrast is checked against it)
REGIONS = {
    1: {"ground": "dust_1", "dark": "dust_0", "light": "dust_2", "lit": "parchment_0", "shade": "soot_3",
        "ridge": "dust_0", "ridge_dark": "soot_3", "ridge_lit": "dust_1"},
    2: {"ground": "dust_0", "dark": "soot_3", "light": "dust_1", "lit": "dust_2", "shade": "soot_2",
        "ridge": "soot_2", "ridge_dark": "soot_1", "ridge_lit": "soot_3"},
    3: {"ground": "verdigris_0", "dark": "teal_0", "light": "verdigris_1", "lit": "verdigris_2", "shade": "soot_2",
        "ridge": "teal_0", "ridge_dark": "soot_2", "ridge_lit": "verdigris_0"},
    4: {"ground": "soot_3", "dark": "soot_2", "light": "dust_0", "lit": "dust_1", "shade": "soot_1",
        "ridge": "soot_2", "ridge_dark": "soot_1", "ridge_lit": "soot_3"},
}


def ridge_top(x: float) -> int:
    t = (x - L.FIELD_X0) / (L.W - L.FIELD_X0)
    return int(20 + 7 * math.sin(t * 7.1 + 0.5) + 4 * math.sin(t * 17.0))


def ridge_bot(x: float) -> int:
    t = (x - L.FIELD_X0) / (L.W - L.FIELD_X0)
    return int(L.H - 22 - 6 * math.sin(t * 6.3 + 1.7) - 3 * math.sin(t * 15.0 + 0.2))


def on_road(x: float, y: float, margin: float = 0) -> bool:
    return abs(y - L.road_center(x)) < L.ROAD_HALF + margin


def rgbset(*names) -> set:
    return {C(n)[:3] for n in names}


# ------------------------------------------------------------------ shared ground painters

def scatter_details(c: Canvas, R: dict, seed: int, r: float = 6.5, keep=None, on=None, blades: bool = False,
                    clump: float = 0.0) -> None:
    """Blue-noise micro detail: pebbles, specks, hairline cracks. Density varies with low-frequency noise
    so details cluster softly instead of covering the field evenly."""
    dens = WO.value_noise(L.W, L.H, 48, seed + 5)
    rr = rng(seed)
    allowed = on or rgbset(R["ground"], R["light"], R["dark"])
    for (x, y) in poisson(L.FIELD_X0 + 2, 0, L.W, L.H, r, seed):
        if dens[y][x] < 0.38 + clump * 0.12 or rr.random() > (dens[y][x] - clump * 0.25) * (1.25 + clump):
            continue
        if keep and not keep(x, y):
            continue
        under = c.get(x, y)[:3]
        if under not in allowed:
            continue
        light = under == C(R["light"])[:3]
        kind = rr.random()
        if blades and kind < 0.6:   # marsh grass: 2-3 px blades
            c.set(x, y, R["light"])
            c.set(x, y - 1, R["lit"] if rr.random() < 0.5 else R["light"])
            if rr.random() < 0.5:
                c.set(x + 1, y, R["light"])
                c.set(x + 2, y - 1, R["light"])
        elif kind < 0.45:      # pebble: lit top-left pixel, shadow below-right
            c.set(x, y, R["lit"] if light else R["light"])
            c.set(x + 1, y + 1, R["ground"] if light else R["dark"])
            if rr.random() < 0.35:
                c.set(x + 1, y, R["lit"] if light else R["light"])
        elif kind < 0.82:    # dark speck pair (a hole, dung, a seed)
            c.set(x, y, R["dark"])
            if rr.random() < 0.5:
                c.set(x + 1, y, R["dark"])
        else:                # short hairline crack, 3-5 px
            dx, dy = rr.choice(((1, 0), (1, 1), (1, -1)))
            for k in range(rr.randint(3, 5)):
                c.set(x, y, R["dark"])
                x += dx if rr.random() < 0.8 else 0
                y += dy if rr.random() < 0.5 else 0


def blob_patch(c: Canvas, cx: float, cy: float, rx: float, ry: float, seed: int, name: str,
               only: set = None, rough: float = 0.3, satellites: int = 2) -> list:
    """Irregular patch: a wobbly ellipse plus 1-3 small satellite blobs along its rim."""
    rr = rng(seed)
    px = fill_shape(c, organic(cx, cy, rx, ry, seed, rough), (cx - rx * 1.4, cy - ry * 1.4, cx + rx * 1.4, cy + ry * 1.4),
                    name, only)
    for k in range(satellites):
        a = rr.uniform(0, math.tau)
        sx, sy = cx + math.cos(a) * rx * rr.uniform(0.9, 1.25), cy + math.sin(a) * ry * rr.uniform(0.9, 1.3)
        srx, sry = rx * rr.uniform(0.18, 0.32), ry * rr.uniform(0.25, 0.45)
        px += fill_shape(c, organic(sx, sy, srx, sry, seed + 17 * k, rough * 0.6),
                         (sx - srx * 1.5, sy - sry * 1.5, sx + srx * 1.5, sy + sry * 1.5), name, only)
    return px


def rim_shade(c: Canvas, pixels: list, inner: str, rim: str) -> None:
    """Pale patch rim: its lower/right edge one tone darker (the crust's lip), so it is not a flat stamp."""
    s = set(pixels)
    for (x, y) in pixels:
        if (x, y + 1) not in s or (x + 1, y) not in s:
            if (x, y - 1) in s and (x - 1, y) in s:
                c.set(x, y, rim)


def edge_shade(c: Canvas, pixels: list, near: str, far: str) -> None:
    """Two-tone patch edge: the top/left boundary gets `near`, the bottom/right boundary gets `far`.
    Raised patches (moss): near = lit, far = dark. Hollows (mud, damp): near = dark (the rim's shadow
    falls in), far = lit (the far bank catches the light)."""
    s = set(pixels)
    for (x, y) in pixels:
        if (x, y - 1) not in s or (x - 1, y) not in s:
            c.set(x, y, near)
        elif (x, y + 1) not in s or (x + 1, y) not in s:
            c.set(x, y, far)


def ridges(c: Canvas, R: dict, seed: int) -> None:
    """Dark higher ground along the top and bottom edges: frames the field and leads the eye to the road."""
    for x in range(L.FIELD_X0, L.W):
        top, bot = ridge_top(x), ridge_bot(x)
        for y in range(0, top):
            c.set(x, y, R["ridge"])
        c.set(x, top, R["ridge_dark"])
        c.set(x, top + 1, R["ridge_dark"])
        c.set(x, top + 2, R["dark"])
        c.set(x, top - 1, R["ridge_lit"])
        for y in range(bot, L.H):
            c.set(x, y, R["ridge"])
        c.set(x, bot, R["ridge_lit"])
        c.set(x, bot + 1, R["ridge"])
    rr = rng(seed)
    for (x, y) in poisson(L.FIELD_X0, 0, L.W, L.H, 5.0, seed + 1):
        if y < ridge_top(x) - 2 or y > ridge_bot(x) + 2:
            c.set(x, y, R["ridge_dark"] if rr.random() < 0.7 else R["ridge_lit"])


def uneven_line(seed: int, x0: int, x1: int, gap=(6, 34), cluster=(1, 3)) -> list:
    """x positions along an edge in irregular clusters (no constant spacing)."""
    rr = rng(seed)
    xs, x = [], x0 + rr.randint(0, 8)
    while x < x1:
        for k in range(rr.randint(*cluster)):
            xs.append(x + k * rr.randint(7, 11))
        x += rr.randint(*gap) + 10 * cluster[1]
    return [v for v in xs if v < x1]


def stamp_all(c: Canvas, stamps: list) -> None:
    stamps.sort(key=lambda s_: s_[0])
    for (_ys, x, y, d) in stamps:
        if abs(y + d.h - L.road_center(x + d.w / 2)) < L.ROAD_HALF - 3 and d.w > 9:
            continue   # never put big props on the road
        c.paste_over(d, x, y)


def road_mask(seed: int, half: float = L.ROAD_HALF):
    """Inside-road test with a smooth, slightly wobbly edge (no per-column jaggies)."""
    f_top, f_bot = wobble(seed, 4), wobble(seed + 3, 4)

    def d(x: float, y: float) -> float:
        cy = L.road_center(x)
        a = x / 23.0
        e = 1.3 * (f_top(a) if y < cy else f_bot(a))
        return abs(y - cy) - half - e
    return d


# ------------------------------------------------------------------ region 1: Ржавые пустоши

def field_r1(c: Canvas) -> None:
    R = REGIONS[1]
    G = rgbset(R["ground"])
    # damp darker hollows first (few, small), then pale dry flats with cracked crust
    for i, (x, y, rx, ry) in enumerate([(262, 160, 12, 5), (420, 230, 10, 4), (170, 92, 9, 4), (356, 118, 8, 3)]):
        blob_patch(c, x, y, rx, ry, 300 + i, R["dark"], only=G, rough=0.35, satellites=1)
    flats = [(212, 121, 36, 15, 1), (330, 234, 42, 14, 2), (412, 152, 27, 12, 3), (182, 243, 21, 10, 4),
             (306, 70, 30, 9, 5), (250, 290, 16, 6, 6)]
    for (x, y, rx, ry, s) in flats:
        px = blob_patch(c, x, y, rx, ry, 100 + s, R["light"], only=G, rough=0.32, satellites=3)
        rim_shade(c, px, R["light"], R["ground"])
        # dry-mud crackle inside the flat: a few short polylines
        rr = rng(200 + s)
        pset = set(px)
        for _ in range(int(rx * ry / 90) + 1):
            qx, qy = rr.randint(int(x - rx * 0.6), int(x + rx * 0.6)), rr.randint(int(y - ry * 0.5), int(y + ry * 0.5))
            for k in range(rr.randint(4, 8)):
                if (qx, qy) in pset:
                    c.set(qx, qy, R["ground"])
                qx += rr.choice((1, 1, -1, 0))
                qy += rr.choice((0, 0, 1, -1))
    ridges(c, R, 11)
    # road
    d = road_mask(4)
    for x in range(L.FIELD_X0 - 2, L.W):
        for y in range(L.H):
            v = d(x, y)
            if v < 0:
                c.set(x, y, R["light"])
            elif v < 1.6:
                c.set(x, y, R["dark"])
    ruts = wobble(9, 3)
    for x in range(L.FIELD_X0, L.W):
        cy = L.road_center(x)
        for off in (-6, 6):
            if ruts(x / 9.0 + off) > -0.55:          # ruts break here and there
                c.set(x, int(cy + off + 0.5), R["ground"])
                if ruts(x / 5.0 + off * 2) > 0.45:
                    c.set(x, int(cy + off + 1.5), R["ground"])
    scatter_details(c, R, 31, r=7.0, keep=lambda x, y: ridge_top(x) + 2 < y < ridge_bot(x) - 1)
    # edges: bushes and boulders in uneven clusters on both ridges
    rr = rng(7)
    stamps = []
    for i, x in enumerate(uneven_line(41, L.FIELD_X0 + 4, L.W - 6)):
        b = WO.bush(i * 3 + 1) if rr.random() < 0.7 else WO.boulder(rr.randint(7, 13), rr.randint(6, 9), i)
        top = ridge_top(x)
        stamps.append((top, x, top - b.h + rr.randint(-3, 6), b))
    for i, x in enumerate(uneven_line(43, L.FIELD_X0 + 2, L.W - 6, gap=(4, 26))):
        b = WO.bush(i * 5 + 60) if rr.random() < 0.6 else WO.boulder(rr.randint(7, 15), rr.randint(6, 10), i + 9)
        bot = ridge_bot(x)
        stamps.append((bot + 9, x, bot - b.h // 2 + rr.randint(-2, 10), b))
    # roadside tussocks: blue-noise along both shoulders, about half kept
    for (x, y) in poisson(L.FIELD_X0 + 10, 0, L.W - 4, L.H, 9.0, 47):
        dd = d(x, y)
        if 0.5 < dd < 5 and rr.random() < 0.5:
            v = rr.random()
            g = WO.decal_grass(x + y) if v < 0.55 else WO.decal_rocks(x) if v < 0.8 else \
                WO.bush(x * 7 + y, rr.choice(("olive", "rust")))
            stamps.append((y, x - g.w // 2, y - g.h + 2, g))
    clusters = [
        [(232, 98, WO.wreck_boiler()), (222, 110, WO.decal_scrap(1)), (266, 108, WO.decal_scrap(2)),
         (216, 104, WO.decal_grass(3)), (270, 100, WO.decal_grass(4)), (250, 112, WO.decal_rocks(5))],
        [(372, 280, WO.wreck_wheel()), (395, 284, WO.boulder(16, 11, 5)), (360, 292, WO.boulder(9, 7, 7)),
         (390, 276, WO.decal_grass(6)), (352, 284, WO.decal_grass(7))],
        [(186, 262, WO.dead_tree()), (204, 276, WO.boulder(14, 10, 11)), (166, 278, WO.crater(7, 4)),
         (178, 286, WO.decal_grass(8)), (214, 268, WO.decal_grass(9))],
        [(398, 92, WO.crater(9, 5)), (420, 102, WO.boulder(12, 8, 13)), (386, 104, WO.decal_rocks(10)),
         (412, 88, WO.decal_scrap(4))],
        # small things for the big flats, so they are not empty
        [(296, 52, WO.fence_remnant(3)), (330, 58, WO.decal_grass(14))],
        [(318, 240, WO.stone_scatter(5)), (346, 222, WO.decal_scrap(5)), (300, 228, WO.bush(77, "sage"))],
        [(200, 128, WO.stone_scatter(8)), (244, 140, WO.signpost())],
        [(414, 152, WO.decal_scrap(7)), (430, 160, WO.decal_grass(15))],
        [(250, 286, WO.fence_remnant(9)), (178, 240, WO.stone_scatter(11))],
        [(160, 150, WO.bush(91, "rust")), (172, 156, WO.decal_rocks(12))],
    ]
    # a faint old cart track across the southern flat (paired rut dots, broken)
    for x in range(290, 380):
        y = int(250 + (x - 290) * 0.12)
        if (x * 7) % 5 < 3 and c.get(x, y)[:3] == C(R["light"])[:3]:
            c.set(x, y, R["ground"])
            c.set(x, y + 4, R["ground"])
    for cl in clusters:
        for (x, y, dd) in cl:
            stamps.append((y + dd.h, x, y, dd))
    stamp_all(c, stamps)


# ------------------------------------------------------------------ region 2: Угольные копи

def slag_heap(w: int, h: int, seed: int, coal: bool = False) -> Canvas:
    """Conical heap of slag (grey) or coal (black with blue-grey glints), lit top-left."""
    c = Canvas(w + 3, h + 2)
    rr = rng(seed)
    cx = w / 2
    f = wobble(seed, 3)
    ramp = ("soot_0", "soot_1", "soot_2", "iron_0") if coal else ("soot_2", "iron_0", "iron_1", "iron_2")
    for y in range(h):
        k = y / (h - 1)
        half = (0.18 + 0.82 * math.sqrt(k)) * w / 2 * (1 + 0.08 * f(y / 3))
        for x in range(int(cx - half), int(cx + half) + 1):
            u = (x - (cx - half)) / max(1, 2 * half)
            lit = 1 - u - 0.25 * k
            name = ramp[3] if lit > 0.72 else ramp[2] if lit > 0.42 else ramp[1] if lit > 0.12 else ramp[0]
            c.set(x, y + 1, name)
    # lumps: blue-noise chunks with a lit pixel
    for (x, y) in poisson(0, 2, w, h, 2.6, seed + 9):
        if c.opaque(x, y) and c.opaque(x + 1, y + 1):
            c.set(x, y, "steam_0" if coal and rr.random() < 0.5 else ramp[3])
            c.set(x + 1, y + 1, ramp[0])
    # shadow to the right
    for y in range(h - 2, h + 2):
        for x in range(int(cx), w + 3):
            if not c.opaque(x, y) and c.opaque(x - 2, y - 1):
                c.set(x, y, "soot_1")
    c.outline("soot_0")
    return c


def mine_cart(full: bool = True, w: int = 20, seed: int = 1) -> Canvas:
    """Iron mine cart in 3/4 (side + a sliver of the top): trapezoid bucket, lit rim, rivets, two wheels;
    `full` heaps coal over the rim."""
    h = 15
    c = Canvas(w + 2, h)
    top, bot = 5, 11
    for y in range(top, bot + 1):
        inset = (y - top) * 2 // 3
        for x in range(1 + inset, w - inset):
            c.set(x, y, "iron_1")
        c.set(1 + inset, y, "iron_2")
        c.set(w - 1 - inset, y, "iron_0")
    c.hline(1, w - 1, top, "iron_3")         # rolled rim
    c.hline(1, w - 1, top + 1, "iron_2")
    c.hline(4, w - 4, bot, "iron_0")
    for x in range(4, w - 3, 4):
        c.set(x, top + 3, "iron_3")
        c.set(x, bot - 2, "iron_3")
    c.vline(w // 2, top + 2, bot - 1, "iron_0")
    if full:
        rr = rng(seed)
        for x in range(2, w - 1):
            hh = int(2 + 2.2 * math.sin(math.pi * (x - 1) / (w - 2)) + rr.random())
            for y in range(top - hh, top):
                c.set(x, y, "soot_1" if (x + y) % 3 else "soot_0")
        for (x, y) in poisson(2, 0, w - 1, top, 2.2, seed):
            if c.opaque(x, y):
                c.set(x, y, "iron_0" if rr.random() < 0.6 else "steam_0")
    for wx in (5, w - 5):
        c.disc(wx, 12, 2.2, "soot_1")
        c.set(wx, 12, "iron_2")
        c.set(wx - 1, 11, "iron_0")
    c.outline("soot_0")
    return c


def rust_cart(seed: int, tipped: bool = False) -> Canvas:
    """Abandoned mine-cart bucket: rusted through (copper ramp, no iron sheen, no brass), dented rim,
    holes, NO wheels, half sunk in the ground; may hold a little old coal. Must never read as the
    `wagon_roll` enemy (iron + brass rim + wheels + headlamps)."""
    rr = rng(seed)
    w, h = 18, 14
    c = Canvas(w + 3, h)
    top, bot = 4, 10
    for y in range(top, bot + 1):
        inset = (y - top) // 2
        for x in range(1 + inset, w - inset):
            c.set(x, y, "copper_1")
        c.set(1 + inset, y, "copper_2")
        c.set(w - 1 - inset, y, "copper_0")
    for x in range(1, w):            # dented rim
        c.set(x, top + (1 if x in (5, 6, 12) else 0), "copper_2")
    c.set(2, top, "copper_3")
    for (x, y) in poisson(3, top + 2, w - 3, bot, 3.0, seed):      # rust holes and flakes
        r = rr.random()
        if r < 0.3:
            c.set(x, y, "soot_0")
            c.set(x + 1, y, "soot_1")
        elif r < 0.6:
            c.set(x, y, "copper_0")
        else:
            c.set(x, y, "dust_1")
    c.vline(w // 2, top + 2, bot - 1, "copper_0")
    if rr.random() < 0.6:
        for x in range(4, w - 4):
            if rr.random() < 0.7:
                c.set(x, top - 1, "soot_1" if x % 3 else "soot_0")
    # sunk: the ground covers the bottom, a dark lip where it meets the ground
    for x in range(0, w + 3):
        c.set(x, bot + 1, "soot_3")
        c.set(x, bot + 2, "dust_0" if x % 4 else "dust_1")
    c.outline("soot_0")
    if tipped:
        from PIL import Image as _I
        c.img = c.img.transpose(_I.FLIP_TOP_BOTTOM)
        c.px = c.img.load()
    return c


def mine_cart_wreck() -> Canvas:
    """An overturned, wheel-less rusty bucket with spilled coal to the right."""
    c = Canvas(30, 17)
    c.paste_over(rust_cart(11, tipped=True), 1, 0)
    for (x, y) in poisson(14, 8, 30, 17, 1.5, 4):
        if not c.opaque(x, y) and y > 9 + abs(x - 21) * 0.35:
            c.set(x, y, "soot_1" if (x + y) % 3 else "iron_0")
    return c


def timber_trestle() -> Canvas:
    """A-frame mine prop: two posts, a cap beam and a diagonal brace, lit from the left."""
    return from_ascii("""
00000000000000
0popppppppppo0
0nnnnnnnnnnnm0
.000000000000.
..0po0..0po0..
..0po0..0po0..
..0pn0.0on00..
..0pn00on0n0..
..0pn0on0.n0..
..0pnon0..n0..
..0ponn0..n0..
..0pn00...n0..
..0pn0...0n0..
..0pn0...0n0..
.00pn00.00n00.
.0DDDD0.0DDD0.
""")


def lantern_post() -> Canvas:
    return from_ascii("""
.000...
0hgf0..
0TRT0..
0RQR0..
.0f0...
..0n0..
..0n0..
..0n0..
..0n0..
..0n0..
..0n0..
..0n0..
.00n00.
.0DDD0.
""")


def mine_adit() -> Canvas:
    """Timbered tunnel mouth cut into the north ridge: dark opening, posts, lintel, rails leading out."""
    c = Canvas(40, 30)
    # rock face around the mouth
    for y in range(0, 24):
        for x in range(40):
            if abs(x - 20) < 19 - max(0, 8 - y) * 0.9:
                c.set(x, y, "soot_2" if (x + y) % 9 else "soot_3")
    for (x, y) in poisson(0, 0, 40, 24, 3.0, 77):
        if c.opaque(x, y):
            c.set(x, y, "iron_0")
    # opening: black with a faint inner frame
    c.rect(11, 6, 28, 26, "soot_0")
    c.rect(13, 9, 26, 26, "soot_0")
    c.hline(13, 26, 8, "soot_1")
    # posts and lintel
    for x0 in (8, 27):
        c.rect(x0, 5, x0 + 4, 27, "copper_1")
        c.vline(x0, 5, 27, "copper_2")
        c.vline(x0 + 4, 5, 27, "copper_0")
        c.hline(x0, x0 + 4, 16, "copper_0")
    c.rect(6, 2, 33, 6, "copper_1")
    c.hline(6, 33, 2, "copper_3")
    c.hline(6, 33, 3, "copper_2")
    c.hline(6, 33, 6, "copper_0")
    for x in (9, 16, 23, 30):
        c.set(x, 4, "iron_2")
    # lamp on the lintel
    c.set(19, 7, "brass_2")
    c.set(19, 8, "ember_2")
    c.set(20, 8, "ember_1")
    # rails coming out
    for y in range(20, 30):
        c.set(16, y, "iron_3")
        c.set(23, y, "iron_3")
        if y % 3 == 0:
            c.hline(14, 25, y, "copper_0")
            c.set(16, y, "iron_3")
            c.set(23, y, "iron_3")
    c.outline("soot_0")
    return c


def timber_pile() -> Canvas:
    return from_ascii("""
....0000000000....
...0oppppppppo0...
..0nnnnnnnnnnnnm0.
..0pooooooooooon0.
.0pnnnnnnnnnnnnm0.
.0poooooooooooon0.
0pnnnnnnnnnnnnnnm0
.0000000000000000.
""")


def pick_in_rock() -> Canvas:
    return from_ascii("""
......00.....
.....0dc0....
....0dc00....
...0dcn0.....
..0c0n0......
.0b0n0.......
.00n0........
.0n0.........
02220000.....
0222222110...
.00000000....
""")


def field_r2(c: Canvas) -> None:
    R = REGIONS[2]
    G = rgbset(R["ground"])
    # coal-dust drifts (darker), packed ash flats (lighter) and black puddles
    for i, (x, y, rx, ry) in enumerate([(214, 116, 40, 16), (336, 238, 48, 16), (410, 146, 30, 14),
                                        (176, 252, 24, 11), (300, 66, 34, 11), (270, 196, 60, 30),
                                        (420, 290, 26, 9), (190, 166, 14, 8), (380, 60, 22, 7)]):
        blob_patch(c, x, y, rx, ry, 500 + i, R["dark"], only=G, rough=0.34, satellites=3)
    for i, (x, y, rx, ry) in enumerate([(262, 152, 14, 5), (430, 236, 9, 4), (190, 84, 11, 4), (364, 112, 10, 4)]):
        px = blob_patch(c, x, y, rx, ry, 540 + i, R["light"], only=G, rough=0.3, satellites=2)
        rim_shade(c, px, R["light"], R["ground"])
    for i, (x, y, rx, ry) in enumerate([(286, 278, 9, 3), (232, 74, 7, 2.5)]):
        px = blob_patch(c, x, y, rx, ry, 560 + i, "soot_1", rough=0.25, satellites=1)
        for (px_, py_) in px[::7]:
            c.set(px_, py_, "steam_0")      # dull sky reflection
    ridges(c, R, 12)
    # road: packed grey ash with a rail track on wooden sleepers
    d = road_mask(5)
    for x in range(L.FIELD_X0 - 2, L.W):
        for y in range(L.H):
            v = d(x, y)
            if v < 0:
                c.set(x, y, R["light"])
            elif v < 1.6:
                c.set(x, y, R["dark"])
    scatter_details(c, R, 33, r=6.5, keep=lambda x, y: ridge_top(x) + 2 < y < ridge_bot(x) - 1)
    rr = rng(19)
    for (x, y) in poisson(L.FIELD_X0 + 2, 0, L.W, L.H, 5.0, 37):     # loose coal lumps
        if ridge_top(x) + 3 < y < ridge_bot(x) - 2 and d(x, y) > 1.5 and rr.random() < 0.4:
            c.set(x, y, "soot_1")
            c.set(x + 1, y, "soot_0")
            c.set(x, y - 1, "iron_0")
    sw = wobble(12, 2)
    x = L.FIELD_X0 + 1
    while x < L.W:      # sleepers: 3 px wide, spacing 6-7, slightly irregular lengths
        cy = L.road_center(x + 1)
        a = int(cy - 9 + sw(x / 7.0))
        b = int(cy + 8 + sw(x / 5.0 + 2))
        for y in range(a, b + 1):
            c.set(x, y, "copper_1")
            c.set(x + 1, y, "copper_1")
            c.set(x + 2, y, "copper_0")
        c.set(x, a, "copper_2")
        c.set(x + 1, a, "copper_2")
        c.set(x + 1, b + 1, R["dark"])
        c.set(x + 2, b + 1, R["dark"])
        c.set(x + 3, a + 1, R["dark"])
        x += 6 + (1 if (x * 7) % 5 == 0 else 0)
    for x in range(L.FIELD_X0, L.W):
        cy = L.road_center(x)
        for off in (-6, 5):
            y = int(round(cy + off))
            c.set(x, y - 1, "iron_3")
            c.set(x, y, "iron_2")
            c.set(x, y + 1, "soot_1")
    rr = rng(9)
    stamps = []
    for i, x in enumerate(uneven_line(61, L.FIELD_X0 + 4, L.W - 6, gap=(8, 40))):
        if 220 < x < 280:
            continue        # the adit stands here
        b = slag_heap(rr.randint(10, 16), rr.randint(6, 9), 70 + i) if rr.random() < 0.6 else \
            WO.boulder(rr.randint(8, 12), rr.randint(6, 8), i + 40)
        top = ridge_top(x)
        stamps.append((top, x, top - b.h + rr.randint(1, 5), b))
    for i, x in enumerate(uneven_line(63, L.FIELD_X0 + 2, L.W - 6, gap=(6, 30))):
        b = slag_heap(rr.randint(12, 18), rr.randint(7, 10), 90 + i, coal=rr.random() < 0.5) \
            if rr.random() < 0.6 else WO.boulder(rr.randint(9, 14), rr.randint(7, 10), i + 50)
        bot = ridge_bot(x)
        stamps.append((bot + 9, x, bot - 4 + rr.randint(0, 8), b))
    adit = mine_adit()
    ay = ridge_top(250) - 22
    stamps.append((ridge_top(250) + 6, 232, ay, adit))
    for y in range(ay + 30, ay + 58):       # siding: rails on sleepers down from the adit
        if y % 4 == 0:
            c.hline(244, 257, y, "copper_1")
            c.set(244, y, "copper_2")
        c.set(248, y, "iron_3")
        c.set(249, y, "iron_1")
        c.set(255, y, "iron_3")
        c.set(256, y, "iron_1")
    c.rect(245, ay + 58, 258, ay + 60, "copper_1")
    c.hline(245, 258, ay + 58, "copper_3")
    c.hline(245, 258, ay + 61, "soot_1")
    stamps.append((ay + 52, 242, ay + 40, rust_cart(3)))
    clusters = [
        [(206, 92, slag_heap(30, 20, 3)), (236, 104, slag_heap(16, 10, 4, coal=True)), (196, 108, WO.decal_rocks(5))],
        [(362, 264, mine_cart_wreck()), (390, 280, slag_heap(14, 9, 6, coal=True)), (346, 286, timber_pile())],
        [(160, 142, rust_cart(7)), (180, 146, WO.decal_rocks(3))],
        [(176, 252, timber_trestle()), (200, 270, slag_heap(18, 12, 8, coal=True)), (164, 278, WO.crater(6, 3))],
        [(404, 84, slag_heap(26, 18, 9)), (430, 100, lantern_post()), (388, 102, pick_in_rock())],
        [(300, 128, lantern_post()), (318, 262, lantern_post())],
    ]
    for cl in clusters:
        for (x, y, dd) in cl:
            stamps.append((y + dd.h, x, y, dd))
    stamp_all(c, stamps)


# ------------------------------------------------------------------ region 3: Медные болота

def reeds(seed: int) -> Canvas:
    rr = rng(seed)
    w = rr.randint(7, 11)
    c = Canvas(w, 14)
    for i in range(rr.randint(4, 6)):
        x = rr.randint(1, w - 2)
        h = rr.randint(6, 12)
        lean = rr.choice((-1, 0, 0, 1))
        for k in range(h):
            xx = x + (lean if k > h * 0.6 else 0)
            c.set(xx, 13 - k, "verdigris_1" if k < h - 1 else "verdigris_2")
        if rr.random() < 0.5:   # cattail head
            c.set(x + lean, 13 - h, "copper_1")
            c.set(x + lean, 12 - h, "copper_1")
            c.set(x + lean, 11 - h, "copper_2")
    c.outline("soot_1")
    return c


def marsh_tree() -> Canvas:
    """Dead swamp tree with hanging moss strands."""
    c = from_ascii("""
.....0.....0.......0...
......0..0.0..0...0....
...0...0.02.0.0..0.....
....0..0222.0..00......
.....00.22.20.0........
..0....0222220.........
...00...2322...........
.....0..322....0.......
......00322..00........
........3220...........
........322............
........322............
.......3322............
.......3222............
......33222............
.....3.3222.2..........
....D..D222.D2.........
...DDDDDDDDDDDD........
""")
    for (x, y) in [(3, 6), (3, 7), (3, 8), (12, 8), (12, 9), (12, 10), (12, 11), (6, 10), (6, 11), (14, 4), (14, 5)]:
        c.set(x, y, "verdigris_1" if y % 2 else "verdigris_0")
    c.recolor({"dust_0": "teal_0"})
    return c


def sunk_helmet() -> Canvas:
    """A half-sunken copper diving helmet (a hint of the region's Водолаз)."""
    return from_ascii("""
....00000....
..00ppoon00..
.0popoooonn0.
.0po0yxx0nm0.
0pp0yxxww0nm0
0po0xxwww0mm0
0Vo00www0VmV0
.wVVV000VVVw.
wwxwwwwwwxww.
.wwwwwwwwww..
""")


def lily(seed: int) -> Canvas:
    c = Canvas(6, 4)
    c.ellipse(2.5, 1.8, 2.6, 1.5, "verdigris_1")
    c.set(1, 1, "verdigris_2")
    c.set(3, 1, "teal_1")
    c.set(4, 2, "verdigris_0")
    if seed % 2:
        c.set(2, 0, "ember_2")
    return c


def copper_pipe_stub() -> Canvas:
    return from_ascii("""
.000000.
0pppooo0
0ponnnm0
.0pnnm0.
.0ponm0.
.0VonV0.
.0pVnm0.
.0poVm0.
wwwwwwww
.wwxww..
""")


def pool(c: Canvas, cx: float, cy: float, rx: float, ry: float, seed: int) -> None:
    """Marsh water pool: dark water, a lit far (south-east) bank rim, reflections, a muddy lip."""
    px = blob_patch(c, cx, cy, rx + 1.5, ry + 1.2, seed, "dust_0", rough=0.25, satellites=0)
    inside = organic(cx, cy, rx, ry, seed, 0.25)
    water = fill_shape(c, inside, (cx - rx * 1.4, cy - ry * 1.4, cx + rx * 1.4, cy + ry * 1.4), "teal_0")
    s = set(water)
    for (x, y) in water:
        if (x, y - 1) not in s:
            c.set(x, y, "soot_2")           # the near (north) bank shades the water
        elif (x, y + 1) not in s or (x + 1, y) not in s:
            c.set(x, y, "teal_1")
    rr = rng(seed)
    for _ in range(int(rx * ry / 20) + 1):
        x, y = rr.choice(water)
        if (x + 1, y) in s and (x + 2, y) in s:
            c.hline(x, x + 1 + rr.randint(0, 2), y, "teal_1")
    _ = px


def field_r3(c: Canvas) -> None:
    R = REGIONS[3]
    G = rgbset(R["ground"])
    for i, (x, y, rx, ry) in enumerate([(200, 130, 30, 12), (350, 230, 36, 12), (420, 160, 22, 9),
                                        (290, 66, 26, 8), (250, 250, 18, 6)]):
        px = blob_patch(c, x, y, rx, ry, 760 + i, "soot_3", only=G, rough=0.4, satellites=3)   # dark mud flats
        edge_shade(c, px, "soot_2", "dust_0")
        # an inner, wetter core (darker) with its own soft edge, and ripple arcs on it
        inner = fill_shape(c, organic(x + rx * 0.08, y + ry * 0.1, rx * 0.55, ry * 0.5, 790 + i, 0.3),
                           (x - rx, y - ry, x + rx, y + ry), "soot_2", only=rgbset("soot_3"))
        edge_shade(c, inner, "soot_1", "soot_3")
        rr_ = rng(770 + i)
        for k in range(max(1, len(inner) // 90)):
            gx, gy = rr_.choice(inner) if inner else (x, y)
            w = rr_.randint(2, 4)
            for dx in range(-w, w + 1):                 # a flat ripple arc: lit top, dark under
                yy = gy - (1 if abs(dx) < w - 1 else 0)
                if c.get(gx + dx, yy)[:3] in rgbset("soot_2", "soot_1"):
                    c.set(gx + dx, yy, "teal_0")
        for _ in range(len(px) // 60):          # wet glints in the mud
            gx, gy = rr_.choice(px)
            if c.get(gx, gy)[:3] == C("soot_3")[:3]:
                c.set(gx, gy, "teal_0")
    for i, (x, y, rx, ry) in enumerate([(380, 110, 22, 8), (230, 230, 26, 9), (420, 270, 16, 6), (170, 200, 12, 5)]):
        px = blob_patch(c, x, y, rx, ry, 780 + i, "teal_0", only=G, rough=0.38, satellites=2)  # damp hollows
        edge_shade(c, px, "soot_2", "verdigris_0")
    for i, (x, y, rx, ry) in enumerate([(220, 150, 10, 4), (330, 260, 12, 4), (412, 128, 9, 4),
                                        (176, 90, 8, 3), (300, 100, 9, 3), (390, 214, 7, 3), (270, 236, 6, 3)]):
        px = blob_patch(c, x, y, rx, ry, 700 + i, R["light"], only=rgbset(R["ground"]), rough=0.45,
                        satellites=2)
        edge_shade(c, px, R["lit"], "teal_0")       # moss cushions: lit top-left, shadow bottom-right
    ridges(c, R, 13)
    pools = [(232, 98, 22, 8), (392, 272, 26, 9), (186, 268, 16, 7), (412, 96, 16, 6), (302, 132, 12, 5),
             (268, 290, 12, 4), (440, 220, 10, 5), (170, 160, 8, 4)]
    for i, (x, y, rx, ry) in enumerate(pools):
        pool(c, x, y, rx, ry, 740 + i)
    # causeway: muddy track with a plank boardwalk down the middle
    d = road_mask(6)
    for x in range(L.FIELD_X0 - 2, L.W):
        for y in range(L.H):
            v = d(x, y)
            if v < 0:
                c.set(x, y, "soot_3")
            elif v < 1.6:
                c.set(x, y, "soot_2")
    scatter_details(c, R, 35, r=5.5, keep=lambda x, y: ridge_top(x) + 2 < y < ridge_bot(x) - 1,
                    on=rgbset(R["ground"], R["light"]), blades=True, clump=1.0)
    sw = wobble(14, 2)
    rr0 = rng(15)
    x = L.FIELD_X0 + 1
    while x < L.W:
        cy = L.road_center(x + 2)
        a = int(cy - 8 + sw(x / 6.0) * 1.2)
        b = int(cy + 7 + sw(x / 4.0 + 1) * 1.2)
        pw = rr0.choice((4, 5, 5))
        tone = rr0.choice(("dust_1", "dust_1", "dust_0", "dust_2"))
        if rr0.random() < 0.05:          # a missing plank: mud shows through
            x += pw
            continue
        for y in range(a, b + 1):
            for k in range(pw - 1):
                c.set(x + k, y, tone)
        c.hline(x, x + pw - 2, a, {"dust_0": "dust_1", "dust_1": "dust_2", "dust_2": "parchment_0"}[tone])
        c.vline(x + pw - 1, a, b, "soot_3")                                        # gap
        c.hline(x, x + pw - 1, b + 1, "soot_2")
        c.set(x + 1, a + 2, "iron_0")                                               # nail heads
        c.set(x + 1, b - 2, "iron_0")
        if rr0.random() < 0.25:
            c.set(x + 2, (a + b) // 2 + rr0.randint(-3, 3), "dust_0")              # knot
        x += pw
    rr = rng(13)
    stamps = []
    for i, x in enumerate(uneven_line(81, L.FIELD_X0 + 4, L.W - 6, gap=(4, 26))):
        b = reeds(i + 1)
        top = ridge_top(x)
        stamps.append((top, x, top - b.h + rr.randint(1, 5), b))
    for i, x in enumerate(uneven_line(83, L.FIELD_X0 + 2, L.W - 6, gap=(4, 24))):
        b = reeds(i + 40)
        bot = ridge_bot(x)
        stamps.append((bot + 9, x, bot - 6 + rr.randint(0, 8), b))
    for (x, y) in poisson(L.FIELD_X0 + 10, 0, L.W - 6, L.H, 10.0, 85):
        dd = d(x, y)
        if 0.5 < dd < 6 and rr.random() < 0.4:
            g = reeds(x * 3 + y)
            stamps.append((y, x - g.w // 2, y - g.h + 2, g))
    # dead trees scattered at different depths (never a row): one leaning over a pool, one on the far
    # ridge, two in the open, one near the bank
    for (x, y, flip) in [(364, 36, False), (282, 112, True), (430, 196, False), (214, 300, True), (158, 92, False)]:
        t = marsh_tree()
        if flip:
            t = t.flip_h()
        stamps.append((y, x, y - t.h, t))
    clusters = [
        [(222, 92, sunk_helmet()), (246, 96, lily(1)), (226, 104, lily(2)), (212, 96, reeds(5))],
        [(380, 262, copper_pipe_stub()), (400, 274, lily(3)), (410, 266, reeds(7)), (366, 276, reeds(8))],
        [(194, 270, lily(4)), (168, 272, reeds(9))],
        [(404, 90, lily(5)), (420, 84, reeds(10)), (296, 128, lily(6))],
    ]
    for cl in clusters:
        for (x, y, dd) in cl:
            stamps.append((y + dd.h, x, y, dd))
    stamp_all(c, stamps)


# ------------------------------------------------------------------ courtyard (paved 3/4 yard)

def crate(seed: int) -> Canvas:
    """Wooden crate in 3/4: lit top face, front face with planks and brass corner bands."""
    rr = rng(seed)
    w = rr.choice((9, 10, 11))
    c = Canvas(w + 2, 11)
    top_h = 3
    c.rect(0, 0, w, top_h, "copper_2")
    c.hline(0, w, 0, "copper_3")
    c.vline(0, 0, top_h, "copper_3")
    c.rect(0, top_h + 1, w, 9, "copper_1")
    c.hline(0, w, top_h + 4, "copper_0")
    c.hline(0, w, top_h + 1, "copper_2")
    c.vline(0, top_h + 1, 9, "brass_2")
    c.vline(w, top_h + 1, 9, "brass_0")
    c.line(1, top_h + 2, w - 1, 9 - 1, "copper_0")
    c.set(1, 1, "brass_3")
    c.set(w - 1, 1, "brass_1")
    for y in range(top_h + 1, 10):
        c.set(w + 1, y, "soot_1")       # shadow to the right
    c.hline(1, w + 1, 10, "soot_1")
    c.outline("soot_0")
    return c


def barrel() -> Canvas:
    return from_ascii("""
.000000.
0oppppo0
0pnnnnp0
0mmmmmm0
0hgggff0
0pnnnnm0
0ponnnm0
0hgggff0
0ponnnm0
.000000.
""")


def coal_heap(w: int, h: int, seed: int) -> Canvas:
    return slag_heap(w, h, seed, coal=True)


def paved_yard(c: Canvas) -> None:
    """Courtyard x 0..WALK_X0-1: big flagstones seen at 3/4 (wider than tall), irregular lengths and
    offsets, one-tone stones with a short lit top-left edge and soft dark joints; coal-dust stains.
    Low contrast so it reads as a floor and never competes with the towers."""
    rr = rng(17)
    y = 0
    while y < L.H:
        h = rr.choice((7, 8, 8, 9))
        x = -rr.randint(0, 10)
        while x < L.WALK_X0:
            w = rr.randint(10, 17)
            tone = "soot_3" if rr.random() < 0.8 else "soot_2"
            for yy in range(y, y + h):
                for xx in range(x, x + w):
                    if 0 <= xx < L.WALK_X0:
                        c.set(xx, yy, tone)
            # joints (bottom and right), a lit top edge over the left part, a lit left edge on top rows
            c.hline(x, x + w - 1, y + h - 1, "soot_2" if tone == "soot_3" else "soot_1")
            c.vline(x + w - 1, y, y + h - 1, "soot_2" if tone == "soot_3" else "soot_1")
            lit = "iron_0" if tone == "soot_3" else "soot_3"
            c.hline(x + 1, x + int(w * rr.uniform(0.35, 0.7)), y, lit)
            c.vline(x, y + 1, y + 2, lit)
            if rr.random() < 0.12:    # cracked stone
                cx = x + rr.randint(3, max(3, w - 4))
                c.line(cx, y + 1, cx + rr.choice((-2, 2)), y + h - 2, "soot_2")
            x += w
        y += h
    # coal dust and wear stains: irregular blobs of the darker tone
    for i, (sx, sy, rx, ry) in enumerate([(20, 300, 18, 8), (36, 232, 10, 4), (14, 160, 9, 3), (40, 110, 7, 3)]):
        fill_shape(c, organic(sx, sy, rx, ry, 900 + i, 0.35), (sx - rx * 1.4, sy - ry * 1.4, sx + rx * 1.4, sy + ry * 1.4),
                   "soot_2", only=rgbset("soot_3"))


def courtyard(c: Canvas) -> list:
    """Paved yard with the boiler house, workshop, crates and coal. Returns chimney mouths for smoke.
    Leaves two open paved plots (layout.YARD_SLOTS) for producer buildings (coal mine, smelter)."""
    paved_yard(c)
    smoke = []
    ch = WO.chimney()
    # workshop (north): verdigris roof, iron front wall with lit windows; shadow on the paving
    wx, wy = 4, 40
    for y in range(wy + 40, wy + 43):
        c.hline(wx + 2, wx + 47, y, "soot_1")
    for y in range(wy, wy + 40):
        c.vline(wx + 46, y + 2, y + 2, "soot_1")
    for y in range(wy, wy + 26):
        for x in range(wx, wx + 46):
            c.set(x, y, "verdigris_0" if (x + y // 3) % 7 else "soot_3")
    c.hline(wx, wx + 45, wy, "verdigris_2")
    c.vline(wx, wy, wy + 25, "verdigris_1")
    for y in range(wy + 3, wy + 26, 5):
        c.hline(wx + 1, wx + 45, y, "verdigris_1")
    for y in range(wy + 26, wy + 40):
        for x in range(wx, wx + 46):
            c.set(x, y, "iron_1")
        c.set(wx, y, "iron_2")
    c.hline(wx, wx + 45, wy + 26, "iron_3")
    c.rect(wx + 6, wy + 30, wx + 12, wy + 39, "soot_0")
    c.rect(wx + 7, wy + 31, wx + 11, wy + 39, "ember_0")
    c.rect(wx + 30, wy + 30, wx + 40, wy + 37, "soot_1")
    c.rect(wx + 31, wy + 31, wx + 39, wy + 36, "ember_1")
    c.vline(wx + 35, wy + 31, wy + 36, "soot_1")
    c.frame(wx - 1, wy - 1, wx + 46, wy + 40, "soot_0")
    smoke.append((wx + 38, wy - 22))
    c.paste_over(ch, wx + 33, wy - 24)
    # boiler house (south): copper roof, brick front with the furnace mouth
    bx, by = 4, 238
    for y in range(by + 46, by + 49):
        c.hline(bx + 2, bx + 47, y, "soot_1")
    for y in range(by, by + 46):
        c.set(bx + 47, y + 2, "soot_1")
    for y in range(by, by + 30):
        for x in range(bx, bx + 46):
            c.set(x, y, "copper_1" if (x + (y // 4) * 2) % 8 else "copper_0")
    c.hline(bx, bx + 45, by, "copper_3")
    c.vline(bx, by, by + 29, "copper_2")
    for y in range(by + 4, by + 30, 4):
        c.hline(bx + 1, bx + 45, y, "copper_0")
    for y in range(by + 30, by + 46):
        for x in range(bx, bx + 46):
            c.set(x, y, "soot_3" if (y // 3 + x // 6) % 2 else "copper_0")
    c.hline(bx, bx + 45, by + 30, "copper_2")
    c.rect(bx + 14, by + 34, bx + 28, by + 45, "soot_0")
    c.rect(bx + 15, by + 36, bx + 27, by + 45, "ember_0")
    c.rect(bx + 17, by + 38, bx + 25, by + 45, "ember_1")
    c.rect(bx + 19, by + 41, bx + 23, by + 45, "ember_2")
    for x in range(bx + 15, bx + 28, 3):
        c.vline(x, by + 34, by + 45, "soot_1")
    c.frame(bx - 1, by - 1, bx + 46, by + 46, "soot_0")
    for (x, y) in [(bx + 4, by - 26), (bx + 32, by - 20)]:
        c.paste_over(ch, x, y)
        smoke.append((x + 5, y + 2))
    # feed pipe: boiler house -> wall, and a riser along the wall up to the workshop
    c.paste_over(WO.pipe_h(L.WALK_X0 - (bx + 46) + 2), bx + 46, by + 12)
    c.paste_over(WO.pipe_v(by + 12 - (wy + 30)), L.WALK_X0 - 6, wy + 30)
    c.paste_over(WO.valve_wheel(), L.WALK_X0 - 8, 200)
    # coal: a big heap by the furnace with a shovel, loose lumps; crates and barrels by the workshop
    c.paste_over(coal_heap(30, 13, 5), 2, 288)
    c.paste_over(from_ascii("..0\n.0n0\n0n0.\n0dc0\n0cb0\n.00."), 30, 286)
    for (x, y) in [(36, 300), (40, 297), (24, 304), (34, 306)]:
        c.set(x, y, "soot_0")
        c.set(x - 1, y - 1, "iron_0")
    for (x, y, s) in [(6, 84, 1), (17, 86, 2), (8, 80, 3)]:
        c.paste_over(crate(s), x, y)
    c.paste_over(barrel(), 34, 82)
    c.paste_over(barrel(), 41, 84)
    for (x, y, s) in [(38, 292, 4), (44, 300, 5)]:
        c.paste_over(crate(s), x, y)
    return smoke


# ------------------------------------------------------------------ the fortress side (all regions)

def fortress(c: Canvas, R: dict) -> list:
    """Bank, moat bed, broken bridge, courtyard, wall strip and steam main. Returns smoke points."""
    for y in range(L.H):
        c.set(L.BANK_X0, y, "soot_1")                       # wet line at the waterline
        for x in range(L.BANK_X0 + 1, L.BANK_X0 + 4):       # lit vertical face
            c.set(x, y, "iron_2")
        c.set(L.BANK_X0 + 1, y, "iron_3")
        if (y + 2) % 7 == 0:                                # block joints
            c.hline(L.BANK_X0 + 1, L.BANK_X0 + 3, y, "iron_1")
        for x in range(L.BANK_X0 + 4, L.BANK_X0 + 8):       # coping top
            c.set(x, y, "iron_1")
        c.set(L.BANK_X0 + 4, y, "iron_3")
        c.set(L.BANK_X0 + 5, y, "iron_2")
        if y % 9 == 4:
            c.hline(L.BANK_X0 + 4, L.BANK_X0 + 7, y, "iron_0")
        c.set(L.BANK_X0 + 8, y, R["shade"])                 # cast shadow on the field
        c.set(L.BANK_X0 + 9, y, R["dark"])
    water = WO.moat_frames()[0]
    for y in range(0, L.H, water.h):
        c.blit(water, L.MOAT_X0, y)
    gy = L.GATE_Y
    x_end = L.FIELD_X0 + 12
    for y in range(gy - 10, gy + 11):
        cut = L.BANK_X0 + ((y * 5) % 3)
        for x in range(cut, x_end):
            plank = (y - gy + 10) // 4
            c.set(x, y, "brass_1" if plank % 2 else "brass_0")
            if (y - gy + 10) % 4 == 0:
                c.set(x, y, "soot_3")
        c.set(cut, y, "brass_2")
    c.hline(L.BANK_X0, x_end, gy - 11, "soot_1")
    c.hline(L.BANK_X0, x_end, gy + 11, "soot_1")
    c.hline(L.BANK_X0, x_end, gy + 12, "soot_2")
    for x in (L.BANK_X0 + 3, x_end - 3):
        c.rect(x, gy - 13, x + 2, gy - 9, "copper_1")
        c.set(x, gy - 13, "copper_3")
        c.rect(x, gy + 10, x + 2, gy + 14, "copper_1")
        c.set(x, gy + 10, "copper_3")
    smoke = courtyard(c)
    ws = WO.wall_section()
    for y in range(0, L.H, 32):
        c.blit(ws, L.WALK_X0, y)
    for i, vy in enumerate(L.STEAM_VENTS_Y):
        if abs(vy - L.GATE_Y) < 30:
            continue
        c.paste_over(WO.steam_pipe(valve=(i % 4 == 1)), L.PIPE_X, vy - 10)
    bastion = WO.bastion()
    c.paste_over(bastion, L.WALK_X0 - 8, -16)
    c.paste_over(bastion, L.WALK_X0 - 8, L.H - 22)
    c.paste_over(WO.gatehouse(), L.WALK_X0 - 2, L.GATE_TOP)
    return smoke


def field_r4(c: Canvas) -> None:
    """«Часовой лес»: dark forest floor, copper leaf litter in drifts, mossy patches, a path of packed
    earth with inlaid brass cog-stones; brass trees with copper crowns frame the field in uneven
    clumps (dense on the ridges, a few standing in the field), fallen gears and springs."""
    import sprites_r4 as R4
    R = REGIONS[4]
    G = rgbset(R["ground"])
    for i, (x, y, rx, ry) in enumerate([(214, 118, 36, 14), (334, 236, 42, 13), (414, 150, 26, 11),
                                        (300, 70, 30, 9), (180, 246, 22, 9)]):
        px = blob_patch(c, x, y, rx, ry, 800 + i, "dust_0", only=G, rough=0.4, satellites=3)   # leaf drifts
        edge_shade(c, px, "dust_1", "soot_2")
        pset = set(px)                                       # leaf clumps piled inside the drift
        for (lx, ly) in poisson(int(x - rx), int(y - ry), int(x + rx), int(y + ry), 9.0, 810 + i):
            if (lx, ly) in pset:
                c.paste_over(R4.leaf_clump(lx * 7 + ly), lx - 4, ly - 3)
    for i, (x, y, rx, ry) in enumerate([(262, 156, 12, 5), (420, 236, 10, 4), (176, 96, 10, 4), (366, 114, 9, 4),
                                        (250, 290, 12, 4)]):
        px = blob_patch(c, x, y, rx, ry, 820 + i, "verdigris_0", only=G, rough=0.4, satellites=2)  # moss
        edge_shade(c, px, "verdigris_1", "soot_2")
    ridges(c, R, 14)
    d = road_mask(7)
    for x in range(L.FIELD_X0 - 2, L.W):
        for y in range(L.H):
            v = d(x, y)
            if v < 0:
                c.set(x, y, "dust_0")
            elif v < 1.6:
                c.set(x, y, "soot_2")
    scatter_details(c, R, 37, r=7.5, keep=lambda x, y: ridge_top(x) + 2 < y < ridge_bot(x) - 1, clump=0.8)
    rr = rng(41)
    stamps = []
    # fallen leaves as small clumps with an edge, gathered around the trees and the drifts (not noise)
    dens = WO.value_noise(L.W, L.H, 40, 43)
    for (x, y) in poisson(L.FIELD_X0 + 4, 0, L.W - 8, L.H, 9.0, 45):
        if ridge_top(x) + 4 < y < ridge_bot(x) - 2 and d(x, y) > 1 and dens[y][x] > 0.6 and rr.random() < 0.3:
            lc = R4.leaf_clump(x * 13 + y)
            stamps.append((y - 4, x, y - lc.h, lc))
    # a few dull half-buried gears along the path EDGES (never shiny, never mid-road)
    x = L.FIELD_X0 + 18
    while x < L.W - 10:
        side = rr.choice((-1, 1))
        cy = L.road_center(x) + side * (L.ROAD_HALF - rr.randint(1, 4))
        g = R4.buried_gear(x)
        c.paste_over(g, x, int(cy) - g.h // 2)
        x += rr.randint(40, 80)
    # roots crossing the path edge and stumps by the road: the forest is close
    for (x, side) in [(176, -1), (232, 1), (300, -1), (356, 1), (410, -1)]:
        cy = L.road_center(x)
        y0 = int(cy + side * (L.ROAD_HALF + 10))
        for k in range(rr.randint(1, 2)):        # a root snaking along the path edge
            ex = x + rr.choice((-1, 1)) * rr.randint(6, 12)
            ey = int(cy + side * (L.ROAD_HALF + rr.randint(0, 2)))
            c.line(x, y0 + 4, (x + ex) // 2, ey + side * 2, "brass_0")
            c.line((x + ex) // 2, ey + side * 2, ex, ey, "brass_0")
        st = R4.stump(x)
        stamps.append((y0 + 6, x - 6, y0 - 4, st))
    def tree_at(x, y, h, seed):
        t = R4.brass_tree(seed, h)
        R4.tree_shadow(c, x, y, max(10, h // 2))
        stamps.append((y, x - t.w // 2, y - t.h + 2, t))
    for i, x in enumerate(uneven_line(91, L.FIELD_X0 - 2, L.W - 10, gap=(0, 14), cluster=(1, 3))):
        tree_at(x, ridge_top(x) + rr.randint(-6, 6), rr.randint(20, 40), 300 + i)
    for i, x in enumerate(uneven_line(93, L.FIELD_X0 - 2, L.W - 10, gap=(2, 18), cluster=(1, 3))):
        tree_at(x, ridge_bot(x) + rr.randint(2, 14), rr.randint(18, 36), 400 + i)
    for (x, y, s_, h) in [(196, 92, 1, 36), (372, 112, 2, 26), (428, 252, 3, 40), (238, 280, 4, 22),
                          (168, 150, 5, 28), (330, 92, 6, 20)]:
        tree_at(x, y, h, 500 + s_)
    for (x, y, s_) in [(222, 112, 1), (388, 124, 2), (318, 256, 3), (430, 168, 5)]:
        g = R4.fallen_gear(s_ * 7)
        stamps.append((y, x, y - g.h, g))
    stamps.append((240, 330, 234, WO.decal_scrap(2)))
    stamp_all(c, stamps)


FIELDS = {1: field_r1, 2: field_r2, 3: field_r3, 4: field_r4}


def compose_bg(region: int = 1):
    R = REGIONS[region]
    c = Canvas(L.W, L.H, R["ground"])
    FIELDS[region](c)
    smoke = fortress(c, R)
    return c, smoke

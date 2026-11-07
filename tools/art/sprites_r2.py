"""Region 2 «Угольные копи»: enemies, towers, effects, the coal mine and the moat furnace.

Walkers face LEFT (toward the fortress); anchor = bottom-centre of the feet unless noted.
Enemy main colours are checked (gen_art) against the region-2 ground `dust_0`.
"""
import math

from pixel import Canvas, cloud, from_ascii, name_at, poisson, rim_light, rng
import sprites_towers as TW
import sprites_units as UN

# Жестяной латник and Подручный вожака were first drawn by the C2 view work (D-039); kept here (the guard
# now re-dresses the new hooded scavenger in brass scrap) so this module is the home of the region 1-2 cast.

# ------------------------------------------------------------------ Жестяной латник (tin knight), 16x22

KNIGHT_BODY = """
......RT........
.....0RT0.......
....00000000....
...0ddddddcc0...
...0d000dddc0...
...0ddddddcc0...
...0cdddcbbb0...
....0bbbbbb0....
..00dddddddd00..
.0hg0ddhddddcb0.
.0hgg0ddddddcb0.
.0ggf0dddddcbb0.
.0gff0ccccccb0..
..0f00bbbbbbb0..
...0..0aaaaaa0..
"""
KNIGHT_LEGS = [
    ("....0cc0.0cc0...", "...0cc0...0cc0..", "..0bbb0...0bbb0.", "..00000...00000."),
    ("......0cc0c0....", "......0cccc0....", ".....0bbbb0.....", ".....000000.....",),
    ("....0cc0.0cc0...", "....0cc0..0cc0..", "...0bbb0..0bbb0.", "...00000..00000.",),
    ("......0c0cc0....", "......0cccc0....", "......0bbbb0....", "......000000....",),
]


def knight_frames() -> list:
    frames = []
    for i in range(4):
        c = Canvas(16, 22)
        legs = Canvas(16, 4)
        for k, row in enumerate(KNIGHT_LEGS[i]):
            legs.ascii(0, k, row)
        c.paste_over(legs, 0, 18)
        bob = -1 if i % 2 else 0
        c.paste_over(from_ascii(KNIGHT_BODY), 0, 3 + bob)
        rim_light(c)
        frames.append(c)
    return frames


# ------------------------------------------------------------------ Подручный вожака (guard), 16x20

def guard_frames() -> list:
    """The scavenger's build in copper scrap armour with an iron pot helmet and a club."""
    frames = []
    for i, f in enumerate(UN.scavenger_frames()):
        c = f.copy()
        c.recolor({"verdigris_2": "brass_2", "verdigris_1": "brass_1", "verdigris_0": "brass_0",
                   "ember_2": "iron_3", "ember_1": "iron_2"})
        bob = 0 if i % 2 == 0 else -1
        # pot helmet over the hood
        c.ascii(2, 1 + bob, [
            "..0000..",
            ".0ddcb0.",
            "0ddccbb0",
            "00000000",
        ])
        # club raised in the front hand
        c.ascii(0, 6 + bob, [
            "0n0",
            "0n0",
            "0m0",
            "0m0",
        ])
        frames.append(c)
    return frames



# ------------------------------------------------------------------ Крот-шахтёр (mole miner), 20x20

MOLE_BODY = """
.......0000.........
......0hhgg0........
.....0hhggff0...00..
....0TNhgggf0..0dc0.
...0eeeeeeeee00dc0..
..0ooponnooonn0c0...
.0pppoo0onnnnn0n0...
0ppppo0Noonnnnn0n0..
.00ppoooonnnnnn0n0..
...00oooonnnnn0n0...
....0MMLLMMLLL0.....
...0pp0MMMMLLL0.....
..0pp00MMMMLLLL0....
...00.0LMMMLLLL0....
......0LLLLLLLL0....
"""
MOLE_LEGS = [
    ["......0n0..0n0.....", ".....0nn0..0nn0....", "....0pp00..0pp0...."],
    [".......0n00n0......", ".......0nn0n0......", "......0pp0pp0......"],
    [".....0n0....0n0....", "....0nn0....0nn0...", "...0pp0....0pp0...."],
    [".......0n00n0......", "......0nn00n0......", "......0pp0pp0......"],
]


def mole_frames() -> list:
    out = []
    for i, legs in enumerate(MOLE_LEGS):
        c = Canvas(20, 20)
        for k, row in enumerate(legs):
            c.ascii(0, 17 + k, row)
        c.paste_over(from_ascii(MOLE_BODY), 0, 2 + (1 if i % 2 else 0))
        c.outline("soot_0")
        rim_light(c)
        out.append(c)
    return out


def _dirt(c: Canvas, cx: float, base: int, w: float, h: float, seed: int) -> None:
    """Fresh soil heap (lighter than the coal ground so it reads): lit top-left, clods."""
    rr = rng(seed)
    for y in range(int(base - h), base + 1):
        k = (base - y) / max(1.0, h)
        half = w * math.sqrt(max(0.0, 1 - k)) * (1 + 0.1 * math.sin(y * 2.1 + seed))
        for x in range(int(cx - half), int(cx + half) + 1):
            u = (x - (cx - half)) / max(1.0, 2 * half)
            name = "dust_2" if u < 0.35 and k > 0.3 else "dust_1" if u < 0.75 else "dust_0"
            c.set(x, y, name)
    for (x, y) in poisson(int(cx - w), int(base - h), int(cx + w), base + 1, 2.2, seed):
        if c.opaque(x, y) and rr.random() < 0.6:
            c.set(x, y, "soot_3")
            c.set(x - 1, y - 1, "parchment_0")


def mole_mound_frames() -> list:
    """20x12 dirt mound moving underground (the mole is invulnerable). 4-frame loop; slide it along the
    road at the mole's speed. Anchor = bottom-centre."""
    out = []
    for f in range(4):
        c = Canvas(20, 12)
        _dirt(c, 10 + (f % 2) * 0.5, 10, 7 + (f in (1, 2)), 4 + (f % 2), 30 + f)
        # tumbling clods on the leading (left) edge, a crack trail behind (right)
        for k, (dx, dy) in enumerate([(-8, -1), (-9, -3), (-7, -5)]):
            if (k + f) % 3 != 0:
                c.set(10 + dx - f % 2, 9 + dy + (f + k) % 2, "dust_2" if k % 2 else "dust_1")
        for x in range(15, 20):
            if (x + f) % 3:
                c.set(x, 10 + (x % 2), "soot_2")
        c.outline("soot_1")
        out.append(c)
    return out


def mole_burrow_frames(walk0: Canvas) -> list:
    """5 frames: the mole dives into the ground (dirt flies up), ending as the mound. Anchor = feet."""
    out = []
    for i in range(5):
        c = Canvas(24, 24)
        depth = (0, 4, 9, 14, 20)[i]
        src = walk0.img
        ground = 21
        for y in range(walk0.h):
            ty = y + 2 + depth
            if ty >= ground - (2 if i else 0):
                continue
            for x in range(walk0.w):
                p = src.getpixel((x, y))
                if p[3]:
                    c.px[2 + x, ty] = p
        if i > 0:
            _dirt(c, 12, ground + 1, 6 + i, 2 + i * 0.8, 40 + i)
            for k, (vx, vy) in enumerate([(-6, -5), (5, -7), (-3, -9), (7, -3), (0, -11)]):
                t = i / 4
                c.set(12 + vx * (0.5 + t), ground - 3 + vy * (0.4 + t * 0.6) + 5 * t * t,
                      "dust_2" if k % 2 else "dust_1")
        c.outline("soot_0")
        out.append(c)
    return out


def mole_emerge_frames(walk0: Canvas) -> list:
    """5 frames: the mound bursts and the mole climbs out (reverse of burrow, with a bigger spray)."""
    b = mole_burrow_frames(walk0)
    out = [b[4].copy(), b[3].copy(), b[2].copy(), b[1].copy(), b[0].copy()]
    for i, c in enumerate(out[1:4]):
        for k, (dx, dy) in enumerate([(-8, -14), (8, -15), (-4, -18), (5, -19), (0, -21)]):
            c.set(12 + dx * (0.6 + i * 0.25), 21 + dy * (0.5 + i * 0.2) + i * i, "dust_2" if k % 2 else "parchment_0")
    return out


# ------------------------------------------------------------------ Вагонетка (runaway mine cart), 28x20

def wagon_frames() -> list:
    """A heavy self-propelled mine cart: plough at the front (left), two headlamp 'eyes', coal heap,
    a little boiler + chimney at the back. Wheels turn; coal jiggles; exhaust puffs."""
    out = []
    for f in range(4):
        c = Canvas(28, 20)
        bob = 1 if f % 2 else 0
        top, bot = 6 + bob, 14 + bob
        for y in range(top, bot + 1):
            inset = (y - top) // 3
            for x in range(4 + inset, 23 - inset):
                c.set(x, y, "iron_2")
            c.set(4 + inset, y, "iron_3")
            c.set(22 - inset, y, "iron_1")
        c.hline(4, 22, top, "brass_3")
        c.hline(4, 22, top + 1, "brass_2")
        c.hline(6, 20, bot, "iron_1")
        for x in (7, 12, 17):
            c.vline(x, top + 2, bot - 1, "iron_1")
            c.set(x, top + 3, "iron_3")
        # headlamps (angry eyes) on the front plate
        c.set(5, top + 4, "ember_2")
        c.set(6, top + 4, "parchment_2")
        c.set(5, top + 5, "ember_1")
        c.line(4, top + 3, 7, top + 2, "soot_0")
        # plough / cowcatcher
        for k in range(5):
            c.hline(1 + k // 2, 4, bot - 3 + k, "iron_3" if k == 0 else "iron_1")
        c.set(1, bot + 1, "iron_0")
        # coal heap that jiggles
        rr = rng(5 + f)
        for x in range(5, 22):
            hh = int(2 + 2 * math.sin(math.pi * (x - 4) / 18) + (rr.random() < 0.3))
            for y in range(top - hh, top):
                c.set(x, y, "soot_1" if (x + y + f) % 3 else "soot_0")
            if rr.random() < 0.3:
                c.set(x, top - hh, "steam_0")
        # boiler + chimney at the back
        c.rect(22, top - 3, 26, bot - 2, "copper_2")
        c.vline(22, top - 3, bot - 2, "copper_3")
        c.vline(26, top - 3, bot - 2, "copper_1")
        c.hline(22, 26, top, "brass_2")
        c.rect(24, top - 7, 25, top - 4, "iron_1")
        c.set(24, top - 7, "iron_3")
        if f % 2 == 0:
            c.set(24, top - 9, "steam_2")
            c.set(25, top - 10, "steam_3")
        else:
            c.set(25, top - 9, "steam_3")
        # wheels with turning spokes
        for wx in (8, 18):
            c.disc(wx, 16, 3.3, "soot_1")
            c.disc(wx, 16, 2.3, "iron_1")
            c.set(wx, 16, "brass_2")
            for k in range(2):
                ang = (f / 4 + k / 2) * math.pi
                c.set(wx + round(math.cos(ang) * 2), 16 + round(math.sin(ang) * 2), "iron_3")
        c.outline("soot_0")
        rim_light(c)
        out.append(c)
    return out


# ------------------------------------------------------------------ Угольный голем + уголёк

GOLEM = """
.........0000............
......000cddc000.........
.....0cdcbbbcdbc0........
....0cdd0RT0RTb00........
....0cbb0QR0QRbb0.......
.000cbbbbbbbbbbb0000.....
0cdc0ccbbbbbbbbb0dcc0....
0dcb00cbbQbbbbb00cbbc0...
0cbbc0cbbRTbbbbb0cbbb0...
0cbbb0ccbbQbbbbc0cbbbc0..
0dcbb00cbbbbbbbc00bbbb0..
.0cbbc0ccbbbbbcc0bbbc0...
.0cbb00ccbbbQbbc00bbb0...
..0cc0.0ccbbRbbb0.0cc0...
..0000.0ccbbbbbb0.0000...
.......0cbbb0cbbb0.......
"""
GOLEM_LEGS = [
    ["......0ccb0.0cbb0.......", ".....0ccbb0..0cbb0......", ".....0000.....0000......"],
    ["......0ccb00cbb0........", "......0ccb0cbb0.........", "......00000000.........."],
    [".....0ccb0...0cbb0......", "....0ccbb0....0cbb0.....", "....0000.......0000....."],
    ["......0ccb00cbb0........", ".......0cbbcbb0.........", "......00000000.........."],
]


def _facet(c: Canvas, seed: int) -> None:
    """Re-shade the body (iron_* pixels) as faceted anthracite: Voronoi facets with a random normal each,
    lit from the top-left; facet seams dark. Ember pixels (cracks, eyes) are kept."""
    pts = poisson(0, 0, c.w, c.h, 4.2, seed)
    rr = rng(seed)
    normals = [(rr.uniform(-1, 1), rr.uniform(-1, 1)) for _ in pts]
    src = c.copy()
    for y in range(c.h):
        for x in range(c.w):
            p = src.get(x, y)
            if not p[3]:
                continue
            n = name_at(src, x, y)
            if not n or not n.startswith(("iron", "steam")):
                continue
            ds = sorted(((px - x) ** 2 + (py - y) ** 2, i) for i, (px, py) in enumerate(pts))
            i = ds[0][1]
            seam = ds[1][0] - ds[0][0] < 3
            nx, ny = normals[i]
            lit = -(nx * 0.6 + ny * 0.8) + (0.35 if n in ("iron_3", "steam_3") else 0)
            name = "iron_3" if lit > 0.75 else "iron_2" if lit > -0.25 else "iron_1" if lit > -0.7 else "soot_3"
            if seam:
                name = "soot_2"
            c.set(x, y, name)


def golem_frames() -> list:
    """24x24 anthracite golem: faceted blue-grey coal with dark seams, ember cracks, ember eyes."""
    out = []
    for i, legs in enumerate(GOLEM_LEGS):
        c = Canvas(24, 24)
        for k, row in enumerate(legs):
            c.ascii(0, 21 + k, row)
        body = from_ascii(GOLEM.translate(str.maketrans("bcd", "cdv")))
        c.paste_over(body, 0, 4 + (1 if i % 2 else 0))
        _facet(c, 3)
        if i % 2:      # crack glow flickers
            c.set(10, 13, "ember_2")
        c.outline("soot_0")
        out.append(c)
    return out


UGOLEK = """
...0000...
..0QRRT0..
.0QRTTvT0.
.0R0TT0R0.
.0QRRTRQ0.
..0QQRQ0..
"""


def ugolek_frames() -> list:
    """10x10 «уголёк»: a hot coal chunk on stubby legs (golem split child). 4-frame scurry."""
    legs = [("..0b0.0b0.", ".0b0...0b0"), ("...0b0b0..", "...0b0b0.."),
            ("..0b0.0b0.", "..0b0..0b0"), ("...0bb0...", "...0bb0...")]
    out = []
    for i in range(4):
        c = Canvas(10, 10)
        c.ascii(0, 7, [legs[i][0].replace("b", "1")])
        c.ascii(0, 8, [legs[i][1].replace("b", "1")])
        c.paste_over(from_ascii(UGOLEK), 0, 1 + (i % 2))
        # soot crust flecks
        c.set(3, 2 + (i % 2), "soot_2")
        c.set(6, 5 + (i % 2), "soot_2")
        if i % 2 == 0:   # a spark pops off
            c.set(8, 0, "ember_2")
        out.append(c)
    return out


def golem_split_frames() -> list:
    """32x28 golem shatter: chunks fly out, two glowing «угольки» drop out of the dust. 6 frames,
    anchor (16, 25). Spawn the two ugolek_walk enemies at frame 4 at x-6 / x+6."""
    chunks = [(-9, -10), (8, -11), (-12, -4), (11, -5), (-4, -13), (4, -9), (-7, -2), (6, -1)]
    out = []
    for f in range(6):
        c = Canvas(32, 28)
        t = (f + 1) / 6
        if f < 4:
            cloud(c, 16, 20 - f, 4 + f * 1.4, seed=91, alpha=(230, 200, 150, 90)[f],
                  dark="soot_2", mid="soot_3", light="iron_0", tail=False)
        for k, (vx, vy) in enumerate(chunks):
            x = 16 + vx * t * 1.3
            y = 18 + vy * t * 1.6 + 16 * t * t
            if y > 26:
                continue
            c.ascii(int(x), int(y), ["dc", "cb"] if (k + f) % 2 else ["c.", "bc"])
            if k % 3 == 0 and f < 3:
                c.set(int(x) + 1, int(y) + 1, "ember_2")
        if f >= 2:   # two glowing children land left and right
            for sx in (10, 22):
                yy = min(22, 12 + (f - 2) * 4)
                c.ascii(sx - 2, yy, [".RT.", "QRTR", ".QQ."])
        c.outline("soot_0")
        out.append(c)
    return out


# ------------------------------------------------------------------ Бур-Великан (drill boss), 56x44

def drill_boss(frame: int, mode: str = "walk") -> Canvas:
    """Front (left): a huge drill cone; right behind it a tall riveted FRONT ARMOUR PLATE with brass edges
    (direct shots hit it: ×0.3); then a copper boiler body with a cab and a chimney; caterpillar tracks.
    mode: walk (drill spins, treads roll), hit (sparks on the plate, body jolts), retreat (drill stopped,
    treads reversed, heavy smoke)."""
    c = Canvas(56, 44)
    jolt = 1 if mode == "hit" and frame == 0 else 0
    ox = jolt
    # tracks
    ty0, ty1 = 34, 41
    for x in range(10, 52):
        for y in range(ty0, ty1 + 1):
            c.set(x + ox, y, "soot_2")
    c.hline(10 + ox, 51 + ox, ty0, "iron_1")
    c.hline(10 + ox, 51 + ox, ty1, "soot_1")
    step = frame if mode != "retreat" else -frame
    for x in range(11, 51):
        if (x + step * 2) % 4 == 0:
            c.vline(x + ox, ty0 + 1, ty1 - 1, "iron_0")
            c.set(x + ox, ty0, "iron_2")
    for wx in (14, 22, 30, 38, 46):
        c.disc(wx + ox, 38, 2.4, "iron_2")
        c.set(wx + ox, 38, "brass_2")
        c.set(wx + ox - 1, 37, "iron_3")
    # body: copper boiler (cylinder seen from the side), lit from the top-left
    for y in range(12, 34):
        for x in range(24, 53):
            if x > 48 and (x - 48) ** 2 + max(0, 16 - y) ** 2 > 18:
                continue        # rounded rear end
            v = (y - 12) / 21
            name = "copper_3" if v < 0.18 else "copper_2" if v < 0.5 else "copper_1" if v < 0.85 else "copper_0"
            c.set(x + ox, y, name)
    c.disc(29 + ox, 11, 3.2, "brass_1")        # steam dome
    c.disc(28.5 + ox, 10.5, 2.0, "brass_2")
    c.set(28 + ox, 9, "brass_3")
    c.rect(26 + ox, 12, 32 + ox, 12, "brass_0")
    for x in (31, 39, 47):
        c.vline(x + ox, 12, 33, "copper_0")
        for y in range(14, 33, 4):
            c.set(x + 1 + ox, y, "copper_3")
    # cab on top with a lit window
    c.rect(34 + ox, 3, 47 + ox, 12, "iron_2")
    c.vline(47 + ox, 4, 12, "iron_1")
    c.hline(34 + ox, 47 + ox, 3, "iron_3")
    c.vline(34 + ox, 3, 12, "iron_2")
    c.rect(37 + ox, 5, 44 + ox, 9, "soot_0")
    c.rect(38 + ox, 6, 43 + ox, 9, "ember_1")
    c.hline(38 + ox, 43 + ox, 6, "ember_2")
    c.vline(40 + ox, 6, 9, "soot_1")
    # chimney with smoke
    c.rect(48 + ox, 0, 51 + ox, 13, "iron_1")
    c.vline(48 + ox, 0, 13, "iron_3")
    c.hline(47 + ox, 52 + ox, 0, "brass_2")
    # FRONT ARMOUR PLATE: tall, slightly slanted, brass edges, big rivets
    for y in range(6, 36):
        x0 = 15 + (y - 6) // 6
        for x in range(x0, x0 + 9):
            c.set(x + ox, y, "iron_2")
        c.set(x0 + ox, y, "brass_3")
        c.set(x0 + 1 + ox, y, "brass_2")
        c.set(x0 + 8 + ox, y, "brass_0")
    c.hline(15 + ox, 23 + ox, 6, "brass_3")
    c.hline(15 + ox, 24 + ox, 7, "brass_2")
    for (rx, ry) in [(18, 10), (21, 10), (18, 17), (21, 17), (19, 24), (22, 24), (20, 31), (23, 31)]:
        c.set(rx + ox, ry, "iron_3")
        c.set(rx + ox + 1, ry + 1, "iron_0")
    c.hline(17 + ox, 23 + ox, 20, "iron_1")
    # the drill: a cone pointing left, spiral grooves that scroll while it spins
    cy = 24
    spin = frame if mode == "walk" else (frame if mode == "hit" else 0)
    for x in range(0, 16):
        half = (x + 1) * 7 / 16
        for y in range(int(cy - half), int(cy + half) + 1):
            v = (y - (cy - half)) / max(1, 2 * half)
            name = "iron_3" if v < 0.3 else "iron_2" if v < 0.78 else "iron_1"
            band = int((x * 0.8 + (y - cy) * 1.1 + spin * 1.5) // 2.5) % 2
            if band and x > 1:
                name = {"iron_3": "iron_2", "iron_2": "iron_1", "iron_1": "iron_0"}[name]
            c.set(x + ox, y, name)
    c.set(0 + ox, cy, "steam_3")
    for y in range(cy - 7, cy + 8):     # collar between drill and plate
        c.set(15 + ox, y, "brass_1")
        c.set(16 + ox, y, "brass_2")
    c.outline("soot_0")
    rim_light(c)
    big = Canvas(60, 54)
    Y = 10
    big.paste_over(c, 0, Y)
    c = big
    # chimney smoke (heavier and darker when retreating)
    puffs = 2 if mode != "retreat" else 3
    for k in range(puffs):
        t = ((frame + k * 2) % 4) / 4
        a = int((200 if mode == "retreat" else 170) * (1 - t * 0.6))
        cloud(c, 50 + ox + t * 5 + k, Y - 2 - t * 7 - k * 2, 2.0 + t * 2.0 + (1 if mode == "retreat" else 0),
              seed=140 + k, alpha=a, dark="soot_2", mid="soot_3", light="iron_0" if mode == "retreat" else "iron_1",
              tail=False)
    if mode == "walk" and frame % 2 == 0:
        for (dx, dy) in [(-1, -3), (-2, 3), (0, 5), (2, -5)]:
            c.set(dx + 2, Y + cy + dy, "dust_2")     # grit thrown off the drill tip
    if mode == "hit":   # sparks burst off the front plate
        for (sx, sy) in [(13, Y + 12), (12, Y + 22)]:
            r0 = 1 + frame * 2
            c.set(sx, sy, "parchment_2")
            for (dx, dy) in [(-1, 0), (0, -1), (0, 1), (-2, -2), (-2, 2), (-3, 0)]:
                c.set(sx + dx * (1 + frame), sy + dy * (1 + frame), "ember_2" if r0 < 3 else "ember_1")
    if mode == "retreat":
        # nose-up tilt while reversing: front columns lifted up to 3 px (reads at a glance vs walk)
        tilted = Canvas(c.w, c.h)
        for x in range(c.w):
            dy = -max(0, round((54 - x) / 6.5))
            for y in range(c.h):
                p = c.get(x, y)
                if p[3] and 0 <= y + dy < c.h:
                    tilted.px[x, y + dy] = p
        c = tilted
        # dust thrown up in front of the tracks (they spin backwards), drifting forward-left
        for k in range(3):
            t = ((frame + k) % 4) / 4
            cloud(c, 6 + k * 9 - t * 6, Y + 38 - t * 5 - k, 2.6 + t * 2.6, seed=160 + k,
                  alpha=int(235 * (1 - t * 0.6)), dark="dust_1", mid="dust_2", light="parchment_0", tail=False)
        for (dx, dy) in [(4, 30), (12, 28), (2, 26)]:
            c.set(dx - frame, Y + dy - frame % 2, "dust_2")
    return c


def drill_boss_frames() -> dict:
    return {
        "walk": [drill_boss(i, "walk") for i in range(4)],
        "hit": [drill_boss(i, "hit") for i in range(2)],
        "retreat": [drill_boss(i, "retreat") for i in range(4)],
    }


# ------------------------------------------------------------------ towers: Пароструй, Котлобой

def steamjet(tier: int, phase: int) -> Canvas:
    """Пароструй: boiler drum + gauge, a neck pipe and a big flared nozzle pointing right (tier 2: twin)."""
    t = TW.TIERS[tier]
    c = Canvas(TW.W, TW.H)
    TW.base(c, tier)
    TW.side_pipes(c, tier)
    m, tr = t["metal"], t["trim"]
    shake = (0, -1, 1)[phase]
    TW.stack(c, tier, 4, phase == 1)
    # vertical boiler drum behind (left)
    for y in range(12 if tier < 2 else 9, 27):
        for x in range(7, 15):
            u = (x - 7) / 7
            c.set(x, y, tr[3] if u < 0.2 else tr[2] if u < 0.55 else tr[1] if u < 0.85 else tr[0])
    top = 12 if tier < 2 else 9
    for x in range(7, 15):
        c.set(x, top - 1, tr[2] if x < 11 else tr[1])
    c.hline(8, 13, top - 2, tr[3])
    for y in (top + 4, top + 10):
        c.hline(7, 14, y, tr[0])
    TW.gauge(c, 8, top + 5)
    # safety valve pops on fire
    c.set(11, top - 3 - (1 if phase == 1 else 0), "brass_3")
    if phase == 1:
        c.set(11, top - 5, "steam_3")
        c.set(12, top - 6, "steam_2")
    noz = (19,)
    flare = 0.45 if tier < 2 else 0.62
    if tier == 2:      # a second drum and a pressure line
        for y in range(15, 27):
            for x in range(1, 7):
                u = (x - 1) / 5
                c.set(x, y, tr[3] if u < 0.25 else tr[2] if u < 0.6 else tr[1])
        c.hline(2, 5, 14, tr[3])
        c.hline(6, 8, 18, "copper_2")
    for ny in noz:
        ny += shake
        c.hline(15, 21, ny, m[3])
        c.hline(15, 21, ny + 1, m[2])
        c.hline(15, 21, ny + 2, m[1])
        c.hline(15, 21, ny + 3, m[0])
        c.rect(18, ny - 1, 19, ny + 4, tr[2])
        c.set(18, ny - 1, tr[3])
        # flared cone 22..29: grows from 4 to 10 px tall
        for x in range(22, 30):
            half = 2 + (x - 22) * flare
            for y in range(int(ny + 1.5 - half), int(ny + 1.5 + half) + 1):
                v = (y - (ny + 1.5 - half)) / max(1, 2 * half)
                c.set(x, y, tr[3] if v < 0.25 else tr[2] if v < 0.6 else tr[1])
        c.vline(29, int(ny + 1.5 - 2 - 7 * flare), int(ny + 1.5 + 2 + 7 * flare), tr[0])
        c.vline(30, int(ny - 2), int(ny + 5), "soot_1")    # dark mouth
    if tier == 2:
        TW.pennant(c, 5, 0, 1 if phase == 1 else 0)
    c.outline("soot_0")
    TW.MUZZLE[f"steam_jet_t{tier}"] = (31, 21)
    if phase == 1:
        for ny in noz:
            for k, (dx, dy) in enumerate([(0, 0), (0, 2), (0, 4), (1, 1), (1, 3)]):
                c.set(30 + dx, ny + dy - 1 + shake, "steam_3" if k % 2 == 0 else "steam_2")
    elif phase == 2:
        for ny in noz:
            c.set(31, ny + 1, "steam_2")
            c.set(30, ny - 2, "steam_1")
    return c


def _boiler(c: Canvas, x: float, y: float, r: float, fuse: bool = True) -> None:
    c.shaded_disc(x, y, r, ["copper_0", "copper_1", "copper_2", "copper_3"])
    c.hline(int(x - r + 1), int(x + r - 1), int(y), "brass_1")
    c.set(int(x - r + 1), int(y), "brass_3")
    c.set(int(x + 1), int(y - 2), "copper_3")
    if fuse:
        c.set(int(x + r - 1), int(y - r), "iron_2")
        c.set(int(x + r), int(y - r - 1), "ember_2")


def boilerbomb(tier: int, phase: int) -> Canvas:
    """Котлобой: a side-view CATAPULT on the turret base. A-frame trestle, a throwing arm on a torsion
    spring drum, a bucket at the arm's end carrying a small riveted boiler with a lit fuse.
    0 cocked + loaded (arm down-back), 1 thrown (arm swung up-forward, bucket empty, steam blow),
    2 returning (arm halfway, the next boiler waits on the deck). Tier 0 timber, 1 iron with brass drum,
    2 gilded, bigger boiler, pennant."""
    t = TW.TIERS[tier]
    c = Canvas(TW.W, TW.H)
    TW.base(c, tier)
    TW.side_pipes(c, tier)
    m, tr = t["metal"], t["trim"]
    TW.stack(c, tier, 3, phase == 1)
    wood = ("copper_0", "copper_1", "copper_2", "copper_3")
    beam = wood if tier == 0 else m
    px, py = 16, 13                     # pivot
    # A-frame trestle (two legs + cross beam), lit left side
    for (x0, y0) in ((9, 26), (23, 26)):
        c.line(x0, y0, px, py + 1, beam[2])
        c.line(x0 + 1, y0, px + 1, py + 1, beam[1])
    c.hline(11, 21, 21, beam[1])
    c.hline(11, 21, 20, beam[3])
    c.rect(8, 25, 24, 26, beam[0])
    c.hline(8, 24, 25, beam[2])
    # throwing arm
    ang = {0: 200, 1: 300, 2: 250}[phase]
    a = math.radians(ang)
    ln = 13
    ex, ey = px + math.cos(a) * ln, py + math.sin(a) * ln * 0.9
    bx, by = px - math.cos(a) * 4, py - math.sin(a) * 4     # short back end
    c.line(round(bx), round(by), round(ex), round(ey), beam[3] if tier == 0 else tr[2])
    c.line(round(bx), round(by) + 1, round(ex), round(ey) + 1, beam[1] if tier == 0 else tr[0])
    # bucket at the end (always opens upward)
    cx, cy = round(ex), round(ey)
    for x in range(cx - 3, cx + 4):
        c.set(x, cy + 1, beam[1])
        c.set(x, cy + 2, beam[0])
    c.set(cx - 3, cy, beam[2])
    c.set(cx + 3, cy, beam[1])
    # torsion spring drum at the pivot (rope coil at tier 0)
    c.disc(px, py, 2.6, "parchment_0" if tier == 0 else tr[1])
    c.set(px - 1, py - 1, "parchment_1" if tier == 0 else tr[3])
    c.set(px, py, "soot_1")
    big = tier == 2
    if phase == 0:
        _boiler(c, cx, cy - 2, 4.0 if big else 3.4)
    elif phase == 2:
        _boiler(c, 5, 22, 2.8, fuse=False)
    if tier == 2:
        TW.pennant(c, 26, 6, 1 if phase == 1 else 0)
    c.outline("soot_0")
    TW.MUZZLE[f"boiler_t{tier}"] = (round(px + math.cos(math.radians(300)) * ln), round(py + math.sin(math.radians(300)) * ln * 0.9) - 3)
    if phase == 1:
        cloud(c, cx + 2, cy - 2, 2.6, seed=150, alpha=255)
    return c


# ------------------------------------------------------------------ effects

def steam_cone_frames(n: int = 4) -> list:
    """80x36 semi-transparent steam cone from the Пароструй nozzle (anchor (0, 18) = nozzle mouth), loops.
    Lumpy union-of-discs silhouette whose bulges stream right; lit top rim, shaded bottom rim, dense
    core near the nozzle fading toward the tip."""
    W, H = 80, 36
    P = 14.0
    out = []
    for f in range(n):
        off = f * P / n
        discs = []
        for xi in range(0, 74):
            s_ = float(xi)
            k = s_ / 73
            ph = ((s_ - off) / P) % 1.0
            r = (2.0 + 13.0 * k ** 0.85) * (0.84 + 0.22 * math.sin(math.tau * ph))
            if xi > 52:       # the far end frays and thins out instead of ending in a flat edge
                r *= max(0.0, (73 - xi) / 21) ** 0.6
                if math.sin(math.tau * (s_ - off) / 7.0) > 0.2:
                    continue
            yy = 18 + 1.5 * math.sin((s_ - off) / 9.0) * k
            discs.append((s_ + 1, yy, r, k))

        def inside(px, py):
            for (x, y, r, k) in discs:
                if abs(px - x) <= r and (px - x) ** 2 + (py - y) ** 2 <= r * r:
                    return k
            return None
        c = Canvas(W, H)
        for py in range(H):
            for px in range(W):
                k = inside(px + 0.5, py + 0.5)
                if k is None:
                    continue
                a = int(215 - 165 * k)
                if inside(px - 0.5, py - 1.6) is None:
                    name = "steam_3"
                elif inside(px + 1.0, py + 2.0) is None:
                    name = "steam_1"
                else:
                    name = "steam_2"
                c.set(px, py, name, a)
        # scalding droplets
        rr = rng(10 + f)
        for _ in range(6):
            x = rr.randint(10, 70)
            y = int(18 + rr.uniform(-1, 1) * (3 + x * 0.15))
            c.set(x, y, "teal_2")
        out.append(c)
    return out


def boiler_bomb_frames() -> list:
    """11x11 thrown boiler, tumbling (4 frames): riveted copper tank, brass band, hissing fuse."""
    out = []
    for f in range(4):
        c = Canvas(11, 11)
        c.shaded_disc(5, 6, 3.8, ["copper_0", "copper_1", "copper_2", "copper_3"])
        a = f * math.pi / 4
        for k in (-3, -2, -1, 0, 1, 2, 3):
            c.set(round(5 + math.cos(a) * k), round(6 + math.sin(a) * k), "brass_1")
        c.set(round(5 + math.cos(a + 1.57) * 2), round(6 + math.sin(a + 1.57) * 2), "copper_3")
        c.outline("soot_0")
        fx, fy = round(5 + math.cos(a - 1.2) * 5), round(6 + math.sin(a - 1.2) * 5)
        c.set(fx, fy, "ember_2" if f % 2 else "parchment_2")
        c.set(1 + f % 2, 0, "steam_2")
        out.append(c)
    return out


def boiler_explosion_frames() -> list:
    """48x48 boiler blast, 7 frames (anchor (24, 36)): white-hot flash, fire + scalding steam,
    rivets and copper shards flying out in arcs, then a steam-and-smoke mushroom with torn wisps."""
    out = []
    rivets = [(-14, -12), (13, -14), (-18, -4), (17, -6), (-8, -18), (7, -19), (-20, 3), (19, 2), (0, -21)]
    specs = [
        [(24, 34, 5, "hot")],
        [(24, 32, 10, "hot"), (16, 35, 5, "fire"), (32, 35, 5, "fire")],
        [(24, 30, 12, "fire"), (13, 34, 7, "fire"), (35, 34, 7, "fire"), (24, 25, 7, "hot"), (8, 37, 4, "steam")],
        [(24, 25, 11, "smoke"), (12, 33, 8, "steam"), (36, 33, 8, "steam"), (24, 31, 7, "fire")],
        [(24, 21, 12, "smoke"), (11, 31, 8, "steam"), (37, 31, 8, "steam"), (24, 31, 6, "steam")],
        [(24, 17, 11, "smoke_thin"), (10, 29, 7, "steam_thin"), (38, 28, 6, "steam_thin")],
        [(23, 13, 8, "smoke_thin"), (9, 26, 5, "steam_thin"), (39, 25, 4, "steam_thin")],
    ]
    tones = {
        "hot": ("ember_2", "parchment_2", "steam_3", 255),
        "fire": ("ember_1", "ember_2", "parchment_2", 255),
        "smoke_hot": ("soot_2", "iron_0", "ember_1", 255),
        "smoke": ("iron_0", "iron_1", "steam_1", 230),
        "smoke_thin": ("iron_1", "steam_1", "steam_2", 140),
        "steam": ("steam_1", "steam_2", "steam_3", 220),
        "steam_thin": ("steam_1", "steam_2", "steam_3", 130),
    }
    for fi, spec in enumerate(specs):
        c = Canvas(48, 48)
        for (x, y, r, tone, *_) in spec:
            d, mid, l, a = tones[tone]
            cloud(c, x, y, r, seed=100 + fi * 7 + int(x), alpha=a, dark=d, mid=mid, light=l, tail=fi >= 3)
        if fi in (1, 2):
            c.disc(23.5, 33 - fi, 3 + fi, "parchment_2")
        if fi >= 1:
            t = fi / 6
            for k, (vx, vy) in enumerate(rivets):
                x = 24 + vx * (0.35 + t * 1.0)
                y = 32 + vy * (0.35 + t * 1.0) + 26 * t * t
                if 0 <= y < 47:
                    if k % 3 == 2:      # copper shard
                        c.ascii(int(x), int(y), ["po", ".n"] if (k + fi) % 2 else ["op", "n."])
                    else:               # rivet (domed head) with a hot trail
                        c.ascii(int(x), int(y), ["0d0", "0ba", ".0."] if (k + fi) % 2 else ["0dc0", ".00."])
                        if fi < 4:
                            c.set(x - vx * 0.08, y - vy * 0.08, "ember_2")
                            c.set(x - vx * 0.15, y - vy * 0.15, "ember_1")
        out.append(c)
    return out


def burning_puddle_frames() -> list:
    """32x14 burning puddle (boiler oil + coal) left by the Котлобой: dark pool, flame tongues flicker,
    sparks rise. 4-frame loop; anchor (16, 10). Lives ~3 s."""
    out = []
    flames = [(5, 0), (9, 2), (13, 1), (17, 3), (21, 0), (25, 2), (11, 3), (19, 1)]
    for f in range(4):
        c = Canvas(32, 14)
        c.ellipse(16, 10, 14, 3.2, "soot_1")
        c.ellipse(15, 9.6, 11, 2.2, "soot_0")
        for x in range(5, 27, 4):
            c.set(x + f % 2, 9, "steam_0")      # oily sheen
        c.hline(4, 27, 13, "soot_2")
        for k, (x, ph) in enumerate(flames):
            h = (2, 4, 6, 3)[(f + ph) % 4]
            if (k + f) % 4 == 3:
                continue
            for y in range(h):
                yy = 10 - y
                w = 1 if y < h - 2 else 0
                for dx in range(-w, w + 1):
                    c.set(x + dx + (1 if y > h // 2 and k % 2 else 0), yy,
                          "parchment_2" if y == 0 and w else "ember_2" if y < h - 2 else "ember_1")
        for k in range(3):
            c.set(6 + k * 9 + f * 2 % 5, 2 + (f + k) % 3, "ember_2" if k % 2 else "ember_1")
        out.append(c)
    return out


def geyser_frames() -> list:
    """24x60 geyser eruption by the moat (anchor (12, 57)), 6 frames, once: cracks bubble, a spurt,
    a tall boiling column with spray, collapse, a hanging steam cloud over a wet spot."""
    out = []
    heights = [0, 12, 40, 52, 30, 0]
    for f in range(6):
        c = Canvas(24, 60)
        base = 57
        # wet ground + crack
        c.ellipse(12, base, 9, 2.4, "teal_0" if f else "soot_2")
        c.hline(7, 16, base, "soot_0")
        c.set(9, base - 1, "soot_0")
        c.set(14, base + 1, "soot_0")
        h = heights[f]
        if f == 0:
            for (x, y) in [(10, base - 1), (13, base - 2), (15, base - 1)]:
                c.set(x, y, "teal_2")
                c.set(x, y - 1, "steam_3")
        if h:
            for y in range(base - h, base):
                k = (base - y) / h
                half = 2.4 + 1.8 * (1 - k) + (2.2 if k > 0.88 else 0) + 0.8 * math.sin(y * 0.7 + f * 2)
                xc = 12 + 0.8 * math.sin(y * 0.33 + f)
                for x in range(int(xc - half), int(xc + half) + 1):
                    u = (x - (xc - half)) / max(1, 2 * half)
                    name = "steam_3" if u < 0.28 else "teal_2" if u < 0.7 else "teal_1"
                    if (y + f) % 7 == 0 and 0.3 < u < 0.7:
                        name = "steam_3"            # rising bands of foam
                    c.set(x, y, name)
            # crown of spray
            for (dx, dy) in [(-5, 2), (5, 1), (-3, -2), (4, -3), (-7, 6), (7, 5), (0, -4), (-8, 10), (8, 9),
                             (-6, -1), (6, -2), (-2, -5), (3, -6)]:
                c.set(12 + dx, base - h + dy, "steam_3" if dx % 2 else "teal_2")
            cloud(c, 12, base - h + 2, 3.5, seed=125 + f, alpha=230)
            cloud(c, 12, base - 3, 4 + f, seed=120 + f, alpha=210)
        if f >= 4:
            cloud(c, 12, base - 14 - (f - 4) * 8, 6 + (f - 4) * 2, seed=130 + f, alpha=(200, 120)[f - 4])
            for (dx, dy) in [(-6, -4), (6, -6), (-2, -9)]:
                c.set(12 + dx, base + dy, "teal_2")
        out.append(c)
    return out


def coal_chunk_fly_frames() -> list:
    """8x8 coal lump tumbling toward the coal counter (5 frames), like gear_coin_fly."""
    shapes = [
        ["..000...", ".0c210..", "0c22110.", "0c21110.", ".021100.", "..0000.."],
        ["...00...", "..0c10..", ".0c2110.", "0c22110.", ".011110.", "..0000.."],
        [".0000...", "0cc210..", "0c21110.", ".0211100", "..011110", "...0000."],
        ["..0000..", ".0c2210.", ".02211.0", ".0211110", "..00000.", "........"],
        ["...00...", "..0c10..", ".0c2110.", "0c22110.", ".011110.", "..0000.."],
    ]
    out = []
    for i, s in enumerate(shapes):
        c = Canvas(8, 8)
        c.ascii(0, 1, s)
        c.set(2 + i % 3, 2, "steam_0")
        out.append(c)
    return out


# ------------------------------------------------------------------ buildings

def coal_mine_frames(n: int = 6) -> list:
    """50x60 «Угольная шахта» for a courtyard yard slot (anchor (25, 59)). A timber headframe with a big
    winding wheel that turns, the cable down into the shaft house, and a little cart running on a rail
    from the shaft to a coal heap and back."""
    out = []
    for f in range(n):
        c = Canvas(50, 60)
        # paving shadow
        for y in range(56, 60):
            c.hline(4, 49, y, "soot_2")
        # shaft house (3/4 box): roof + front
        c.rect(4, 30, 26, 41, "copper_1")
        c.hline(4, 26, 30, "copper_3")
        for y in range(33, 42, 3):
            c.hline(5, 26, y, "copper_0")
        # masonry front: stone courses 3 px high, staggered joints, lit top edge of each stone
        c.rect(4, 42, 26, 55, "iron_0")
        for row, y0 in enumerate(range(43, 56, 3)):
            off = (row * 3) % 6
            for y in range(y0, min(56, y0 + 3)):
                c.hline(4, 26, y, "iron_1" if (row % 2) else "iron_0")
            c.hline(4, 26, y0, "iron_2" if row % 2 else "iron_1")
            if y0 + 2 < 56:
                c.hline(4, 26, y0 + 2, "soot_2")
            for x in range(4 + off, 27, 6):
                c.vline(x, y0, min(55, y0 + 2), "soot_2")
        c.hline(4, 26, 42, "copper_2")
        c.rect(11, 46, 18, 55, "soot_0")            # shaft door, dark
        c.rect(12, 47, 17, 55, "soot_1")
        c.set(14, 48, "ember_1")                    # a lamp deep in the shaft
        # headframe: two timber legs and braces rising from the shaft house
        for (x0, x1) in ((6, 13), (24, 17)):
            c.line(x0, 41, x1, 6, "copper_2")
            c.line(x0 + 1, 41, x1 + 1, 6, "copper_1")
        for y in (16, 26):
            xa = 6 + (13 - 6) * (41 - y) / 35
            xb = 24 + (17 - 24) * (41 - y) / 35
            c.hline(round(xa), round(xb) + 1, y, "copper_1")
            c.set(round(xa), y, "copper_3")
        c.line(9, 30, 20, 18, "copper_0")
        # winding wheel at the top, turning
        wx, wy, wr = 15.5, 7.5, 6.5
        for y in range(0, 15):
            for x in range(8, 24):
                d = math.hypot(x - wx, y - wy)
                if wr - 1.4 <= d <= wr:
                    c.set(x, y, "iron_2" if (x - wx) + (y - wy) < 0 else "iron_1")
        for k in range(4):
            ang = f / n * math.pi / 2 + k * math.pi / 4
            for r in range(1, 6):
                c.set(round(wx + math.cos(ang) * r), round(wy + math.sin(ang) * r), "iron_3" if k == 0 else "iron_1")
        c.set(15, 7, "brass_3")
        c.set(16, 8, "brass_1")
        # cable from the wheel down into the shaft house and off to the winding engine
        c.vline(9, 8, 30, "soot_1")
        c.line(22, 7, 44, 28, "soot_1")
        # winding engine shed (right) with a small chimney
        c.rect(34, 28, 47, 36, "iron_1")
        c.hline(34, 47, 28, "iron_3")
        c.rect(34, 37, 47, 45, "iron_0")
        c.hline(34, 47, 37, "iron_2")
        c.rect(37, 39, 40, 44, "ember_0")
        c.set(38, 40, "ember_2")
        c.rect(43, 21, 45, 28, "iron_1")
        c.vline(43, 21, 28, "iron_3")
        if f % 2 == 0:
            c.set(44, 19, "iron_0")
            c.set(45, 18, "iron_1")
        else:
            c.set(43, 19, "iron_1")
            c.set(44, 17, "iron_0")
        # rail from the shaft to the coal heap, and the cart running on it
        for x in range(18, 48):
            c.set(x, 53, "iron_3")
            c.set(x, 54, "iron_0")
            if x % 3 == 0:
                c.set(x, 55, "copper_0")
        heap = Canvas(16, 9)
        for y in range(9):
            half = 7.5 * math.sqrt(y / 8)
            for x in range(int(8 - half), int(8 + half) + 1):
                heap.set(x, y, "soot_1" if (x + y) % 3 else "soot_0")
        for (x, y) in [(6, 3), (9, 5), (4, 7), (11, 7), (8, 1)]:
            heap.set(x, y, "iron_0")
        heap.outline("soot_0")
        c.paste_over(heap, 33, 47)
        pos = [0, 4, 8, 12, 8, 4][f % 6]
        cx0 = 20 + pos
        cart = Canvas(10, 7)
        cart.rect(0, 2, 8, 4, "iron_2")
        cart.hline(0, 8, 1, "iron_3")
        if pos < 9:
            cart.hline(1, 7, 0, "soot_1")
            cart.set(3, 0, "iron_0")
        cart.disc(2, 5, 1.2, "soot_1")
        cart.disc(6, 5, 1.2, "soot_1")
        cart.outline("soot_0")
        c.paste_over(cart, cx0, 47)
        c.outline("soot_0")
        out.append(c)
    return out


def moat_furnace(state: str, f: int) -> Canvas:
    """14x20 «Топка рва»: an iron fire door set in the wall's shadowed outer face, with a brick arch and a
    coal chute. Anchor (0, 0) = (face_x0, furnace_y). state: off / warm / hot (hot throws sparks and
    lights a reflection on the water at its foot, x 12..13)."""
    c = Canvas(14, 20)
    # brick arch
    for y in range(2, 16):
        for x in range(0, 12):
            edge = y < 4 or x < 2 or x > 9
            if edge:
                c.set(x, y, "copper_0" if (x + y // 2) % 3 else "soot_3")
    c.hline(1, 10, 2, "copper_1")
    # door
    c.rect(2, 4, 9, 15, "iron_0")
    c.hline(2, 9, 4, "iron_1")
    c.vline(2, 4, 15, "iron_1")
    glow = {"off": ("soot_0", "soot_1"), "warm": ("ember_0", "ember_1"), "hot": ("ember_1", "ember_2")}[state]
    for k, y in enumerate((7, 9, 11, 13)):
        name = glow[1] if (k + f) % 3 else glow[0]
        if state == "hot" and (k + f) % 2 == 0:
            name = "parchment_2" if k == 3 else "ember_2"
        c.hline(3, 8, y, name)
    c.set(8, 5, "brass_2")      # latch
    c.set(9, 6, "brass_0")
    # coal chute above
    c.rect(4, 0, 7, 1, "iron_1")
    c.set(4, 0, "iron_3")
    # sill + ash
    c.hline(1, 10, 16, "iron_1")
    c.hline(1, 10, 17, "soot_2")
    if state != "off":
        c.set(4 + f % 3, 17, "ember_0")
    if state == "hot":
        for (dx, dy) in [(3, -1), (6, -2), (8, 0)]:
            if (dx + f) % 2:
                c.set(dx, dy + 2, "ember_2")
        for y in range(6, 15, 2):
            c.set(12, y + f % 2, "ember_1")
            c.set(13, y + 1 - f % 2, "ember_0")
    return c


def moat_furnace_frames(state: str) -> list:
    return [moat_furnace(state, f) for f in range(1 if state == "off" else 3)]

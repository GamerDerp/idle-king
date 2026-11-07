"""Effects, projectiles, pickups, icons and the Steam Lens reticle."""
import math

from pixel import Canvas, from_ascii
from sprites_world import puff


# ------------------------------------------------------------------ projectiles

def bullet() -> Canvas:
    return from_ascii("""
.00000.
0hggff0
0ggffe0
.00000.
""")


def rivet() -> Canvas:
    return from_ascii("""
.000....
0dc0000.
0ccbbba0
0cb0000.
.000....
""")


def shell_frames() -> list:
    out = []
    for i in range(2):
        c = Canvas(9, 9)
        c.shaded_disc(4, 5, 3.6, ["soot_1", "iron_0", "iron_1", "iron_2"], outline="soot_0")
        c.set(3, 3, "iron_3")
        c.set(6, 1, "brass_1")
        c.set(7, 0, "ember_2" if i == 0 else "steam_3")
        c.set(6, 0, "ember_1" if i == 0 else None)
        out.append(c)
    return out


# ------------------------------------------------------------------ ground shadows

def shadow(rx: float, ry: float) -> Canvas:
    """Soft-edged contact shadow (semi-transparent soot): a solid core and a 1 px lighter rim."""
    w, h = int(rx * 2) + 2, int(ry * 2) + 2
    c = Canvas(w, h)
    cx, cy = (w - 1) / 2, (h - 1) / 2
    for y in range(h):
        for x in range(w):
            d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
            if d <= 0.55:
                c.set(x, y, "soot_0", 110)
            elif d <= 1.0:
                c.set(x, y, "soot_0", 70)
    return c


# ------------------------------------------------------------------ hit / explosion / steam / splash

def spark_frames() -> list:
    """8x8 hit sparks, 3 frames."""
    f0 = from_ascii("""
........
...T....
....T...
.TTvT...
...vTT..
...T....
....T...
........
""")
    f1 = from_ascii("""
..T.....
....T.T.
.R......
...v....
R.....T.
.....R..
..T.....
......R.
""")
    f2 = from_ascii("""
.R......
......R.
........
........
Q.......
.......Q
........
..Q..R..
""")
    return [f0, f1, f2]


def explosion_frames() -> list:
    """32x32 explosion, 6 frames: flash -> fireball -> smoke -> wisps."""
    frames = []
    specs = [
        [(16, 17, 4, "fire_hot")],
        [(16, 16, 8, "fire_hot"), (11, 19, 4, "fire"), (21, 19, 4, "fire")],
        [(16, 14, 10, "fire"), (10, 19, 6, "fire"), (22, 19, 6, "fire"), (16, 11, 5, "fire_hot")],
        [(16, 12, 10, "smoke_hot"), (9, 18, 6, "smoke"), (23, 18, 6, "smoke"), (16, 16, 4, "fire")],
        [(16, 10, 10, "smoke"), (8, 17, 6, "smoke"), (24, 16, 6, "smoke")],
        [(15, 8, 7, "smoke_thin"), (7, 14, 4, "smoke_thin"), (25, 13, 4, "smoke_thin")],
    ]
    tones = {
        "fire_hot": ("ember_2", "parchment_2", "steam_3", 255),
        "fire": ("ember_1", "ember_2", "parchment_2", 255),
        "smoke_hot": ("soot_2", "iron_0", "ember_1", 255),
        "smoke": ("soot_2", "soot_3", "iron_0", 235),
        "smoke_thin": ("soot_3", "iron_0", "iron_1", 150),
    }
    debris = [(4, 6), (27, 5), (2, 20), (29, 22), (10, 2), (22, 1)]
    for fi, spec in enumerate(specs):
        c = Canvas(32, 32)
        for (x, y, r, tone) in spec:
            d, m, l, a = tones[tone]
            puff(c, x, y, r, a, d, m, l)
        if fi in (1, 2):
            c.disc(16, 18 - fi, 2.5 + fi, "steam_3")
        if fi >= 2:
            for k, (x, y) in enumerate(debris):
                t = fi - 2
                dx = (x - 16) * (0.6 + 0.25 * t) + 16
                dy = (y - 16) * (0.6 + 0.25 * t) + 16 + t * t
                c.set(dx, dy, "ember_2" if t < 2 else "soot_1")
                if k % 2 == 0:
                    c.set(dx + 1, dy, "copper_1")
        frames.append(c)
    return frames


def steam_puff_frames() -> list:
    """16x16 steam puff (scald / tower build), 4 frames."""
    out = []
    for i in range(4):
        c = Canvas(16, 16)
        r = 2.5 + i * 1.6
        a = (255, 255, 200, 120)[i]
        puff(c, 8, 9 - i * 0.7, r, a)
        if i < 3:
            puff(c, 4 + i * 0.3, 11 - i, r * 0.55, a)
            puff(c, 12 - i * 0.3, 11 - i, r * 0.5, a)
        out.append(c)
    return out


def splash_frames() -> list:
    """24x28 splash when someone falls into the boiling moat, 5 frames (anchor bottom-centre)."""
    out = []
    for i in range(5):
        c = Canvas(24, 28)
        # ripple ring on the water
        rx = 3 + i * 2.0
        for x in range(24):
            for y in range(20, 28):
                d = ((x - 12) / rx) ** 2 + ((y - 24) / (rx * 0.4)) ** 2
                if 0.65 < d <= 1.0:
                    c.set(x, y, "steam_3" if y < 24 else "teal_2")
        if i <= 2:
            # water column
            h = (8, 14, 10)[i]
            for y in range(24 - h, 24):
                w = 2 if y < 24 - h + 2 else 3
                for x in range(12 - w, 12 + w):
                    c.set(x, y, "teal_2" if x < 12 else "teal_1")
                c.set(12 - w, y, "steam_3")
            # droplets flying out
            for (dx, dy) in [(-6, -4), (6, -5), (-4, -9), (5, -10), (-8, 0), (8, -1)]:
                k = i + 1
                c.set(12 + dx * k / 2, 22 + dy * k / 2 + k * k * 0.7, "teal_2" if dx < 0 else "steam_2")
        if i >= 2:
            puff(c, 12, 18 - (i - 2) * 3, 3 + (i - 2) * 1.5, (255, 220, 150)[i - 2])
            puff(c, 8, 20 - (i - 2) * 2, 2 + (i - 2), (255, 200, 130)[i - 2])
        out.append(c)
    return out


# ------------------------------------------------------------------ pickups

def gear_coin_frames() -> list:
    """10x10 spinning gear coin, 4 frames (front, 3/4, edge, 3/4)."""
    out = []
    for i, sx in enumerate((1.0, 0.6, 0.2, 0.6)):
        c = Canvas(10, 10)
        cx, cy = 4.5, 4.5
        for y in range(10):
            for x in range(10):
                dx = (x - cx) / max(sx, 0.2)
                dy = y - cy
                r = math.hypot(dx, dy)
                ang = math.atan2(dy, dx)
                outer = 4.6 if math.cos(ang * 6) > 0.1 else 3.7
                if r <= outer:
                    lit = -(x - cx) * 0.6 - dy * 0.8
                    name = "brass_3" if lit > 1.5 else "brass_2" if lit > -1.0 else "brass_1"
                    if r < 1.4 and sx > 0.5:
                        name = "brass_0"
                    c.set(x, y, name)
        if i == 2:
            c.vline(4, 0, 9, "brass_2")
            c.vline(5, 0, 9, "brass_1")
            c.set(4, 1, "brass_3")
        c.outline("soot_0")
        out.append(c)
    return out


# ------------------------------------------------------------------ resource icons 16x16

def icon_gears() -> Canvas:
    c = Canvas(16, 16)
    for (cx, cy, r, teeth, ramp, hole) in [(10.0, 10.0, 5.4, 8, ("brass_1", "brass_2", "brass_3"), 1.6),
                                           (4.6, 4.6, 4.2, 6, ("brass_0", "brass_1", "brass_2"), 1.2)]:
        for y in range(16):
            for x in range(16):
                dx, dy = x - cx, y - cy
                d = math.hypot(dx, dy)
                ang = math.atan2(dy, dx)
                outer = r if math.cos(ang * teeth) > -0.15 else r - 1.4
                if hole < d <= outer:
                    lit = -(dx * 0.6 + dy * 0.8)
                    name = ramp[2] if lit > 1.0 else ramp[1] if lit > -1.6 else ramp[0]
                    if d <= hole + 1.0:
                        name = "brass_0"
                    if c.opaque(x, y) and ramp[0] == "brass_0":
                        continue  # small gear sits behind the big one
                    c.set(x, y, name)
    c.outline("soot_0")
    return c


def icon_blueprint() -> Canvas:
    return from_ascii("""
................
..00000000000...
.0hxyyyyyyyy0...
0hgxvxxxxvxx0...
0gfxvxvvvvxx0...
0fexvxvxxvxx0...
.0exvvvxxvxx0...
..0xxxxxvvvx0...
..0xvvxxvxxx0...
..0xvxvxvvvx00..
..0xvvxxxxxx0hh0
..0xxxvvvvvx0gf0
..0xxxxxxxxx0fe0
..0wwwwwwwwwwe0.
...00000000000..
................
""")


def icon_coal() -> Canvas:
    return from_ascii("""
................
................
......000.......
.....0c210......
....0cc2210.....
...00c22210000..
..0bc0221100c10.
.0cc221110c2210.
.0c22211102221Q0
.0b2221110211RT0
..0211100211110.
...01110021110..
....00000000.0..
................
................
................
""")


def icon_copper() -> Canvas:
    return from_ascii("""
................
................
................
................
.....000000000..
....0pppppppo0..
...0ppoooooon00.
..0pooooooonn0m0
.000000000000nm0
.0pppppppppp0m0.
0poooooooooon00.
0onnnnnnnnnnm0..
0mmmmmmmmmmmm0..
.0000000000000..
................
................
""")


def icon_springs() -> Canvas:
    return from_ascii("""
................
.....00000......
....0dddcc0.....
....0ab00ba0....
.....0ddcc00....
....0cb000ba0...
.....0ddcc00....
....0cb000ba0...
.....0ddcc00....
....0cb000ba0...
.....0ddcc00....
....0cb000ba0...
.....0ddcc0.....
....0aabbba0....
.....000000.....
................
""")


def icon_ether() -> Canvas:
    return from_ascii("""
................
......0000......
......0ee0......
......0hf0......
.....00vu00.....
....0vuuuut0....
...0vyyyxxxt0...
..0vyvyyxxxwt0..
..0uyyXyyxxwt0..
..0uyXyyxxxwt0..
..0uyyyxxxwwt0..
...0txxxxwwt0...
....0ttttts0....
.....000000.....
................
................
""")


def icon_seal() -> Canvas:
    return from_ascii("""
................
.....00000......
...00RRRRR00....
..0RRTRRRRRQ0...
.0RRRh0h0hRRQ0..
.0RTRhhhhhRRQ0..
.0RRRhgggfRRQ0..
.0RRRggffeRQQ0..
.0RRRRRRRRRQQ0..
..0RRRRRRRQQ0...
...0QQRRRQQ0....
....00RRR00.....
.....0RQ0QQ0....
....0QQ00QQ0....
....000..000....
................
""")


# ------------------------------------------------------------------ damage-type icons 12x12

def icon_dmg_impact() -> Canvas:
    """Удар: a heavy bullet hitting, with impact lines."""
    return from_ascii("""
............
..0.....0...
...0...0....
............
.0000000....
0ghhhgf00.0.
0gggggfe0.00
0ffffffe0.0.
.0000000....
............
...0...0....
..0.....0...
""")


def icon_dmg_steam() -> Canvas:
    """Пар: three wavy rising wisps over a cloud."""
    return from_ascii("""
..0..0..0...
.0v00v00v0..
.0u00u00u0..
..0u00u00u0.
..0u00u00u0.
.0u00u00u0..
.00000000...
.0vvvvuut0..
0vvuuuuuut0.
0uuuuuuttt0.
.0tttttts0..
..0000000...
""")


def icon_dmg_spark() -> Canvas:
    return from_ascii("""
......000...
.....0hh0...
....0hh0....
...0hh0.....
..0hhhhh0...
..00000hh0..
....0hh00...
...0hg0.....
..0hg0......
..0g0.......
..00........
............
""")


def icon_dmg_blast() -> Canvas:
    return from_ascii("""
.....0......
....0T0..0..
.0..0T0.0T0.
.0T00RT00T0.
..0RRTTRR0..
000RTvvTR000
0TRRTvvTRRT0
.00RRTTRR00.
..0TRRRRT0..
.0T00RR00T0.
.00..0T0.00.
......0.....
""")


# ------------------------------------------------------------------ Steam Lens reticle 32x32

def lens_frames() -> list:
    """44x44 Steam Lens reticle, 3-frame shimmer: brass ring, outward ticks, glass rim, glare."""
    out = []
    S = 44
    cx, cy, R = 21.5, 21.5, 17.0
    for f in range(3):
        c = Canvas(S, S)
        for y in range(S):
            for x in range(S):
                dx, dy = x - cx, y - cy
                d = math.hypot(dx, dy)
                if R - 2.0 <= d <= R:
                    lit = -(dx * 0.6 + dy * 0.8) / R
                    c.set(x, y, "brass_3" if lit > 0.45 else "brass_2" if lit > -0.25 else "brass_1")
                elif R - 3.0 <= d < R - 2.0:
                    c.set(x, y, "teal_2", 150)
        # ticks: long at N/E/S/W, short at diagonals (outward), with a bolt at the long ones
        for ang in range(0, 360, 45):
            a = math.radians(ang)
            long = ang % 90 == 0
            for k in range(1, 5 if long else 3):
                rr = R + k
                c.set(round(cx + math.cos(a) * rr), round(cy + math.sin(a) * rr), "brass_2" if k > 1 else "brass_1")
        # minor ticks inside the ring every 15 deg
        for ang in range(0, 360, 15):
            if ang % 45 == 0:
                continue
            a = math.radians(ang)
            c.set(round(cx + math.cos(a) * (R - 3.5)), round(cy + math.sin(a) * (R - 3.5)), "brass_1", 200)
        # shimmer: a glare arc that slides around the top-left of the glass
        a0 = math.radians(195 + f * 22)
        for k in range(7):
            a = a0 + k * 0.1
            rr = R - 6
            c.set(round(cx + math.cos(a) * rr), round(cy + math.sin(a) * rr), "steam_3", 220 if 1 <= k <= 5 else 130)
        # heat motes inside (the lens burns)
        for (mx, my) in [(18, 25), (26, 18), (24, 27)][f:f + 1]:
            c.set(mx, my, "ember_2", 210)
            c.set(mx + 1, my - 1, "ember_1", 160)
        # centre cross
        c.set(21, 21, "brass_3")
        c.set(22, 22, "brass_1")
        c.set(21, 22, "brass_2")
        c.set(22, 21, "brass_2")
        c.outline("soot_0")
        out.append(c)
    return out

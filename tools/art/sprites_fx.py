"""Effects, projectiles, pickups, icons and the Steam Lens reticle."""
import math

from pixel import Canvas, cloud, from_ascii
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
    """32x32 explosion, 6 frames: flash -> fireball -> smoke with curls -> torn wisps."""
    frames = []
    specs = [
        [(16, 17, 4, "fire_hot", 1)],
        [(16, 16, 8, "fire_hot", 2), (11, 19, 4, "fire", 3), (21, 19, 4, "fire", 4)],
        [(16, 14, 9, "fire", 5), (10, 19, 6, "fire", 6), (22, 19, 6, "fire", 7), (15, 11, 5, "fire_hot", 8)],
        [(16, 12, 9, "smoke_hot", 9), (9, 18, 6, "smoke", 10), (23, 18, 6, "smoke", 11), (16, 16, 4, "fire", 12)],
        [(16, 10, 9, "smoke", 13), (8, 16, 6, "smoke", 14), (24, 15, 5, "smoke", 15)],
        [(15, 8, 6, "smoke_thin", 16), (7, 13, 4, "smoke_thin", 17), (25, 12, 3.5, "smoke_thin", 18)],
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
        for (x, y, r, tone, seed) in spec:
            d, m, l, a = tones[tone]
            cloud(c, x, y, r, seed=seed, alpha=a, dark=d, mid=m, light=l, tail=fi >= 3)
        if fi in (1, 2):
            c.disc(15.5, 17 - fi, 2 + fi, "steam_3")
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
    """16x16 steam puff (scald / tower build), 4 frames, irregular with a torn tail."""
    out = []
    for i in range(4):
        c = Canvas(16, 16)
        r = 2.5 + i * 1.5
        a = (255, 255, 200, 120)[i]
        cloud(c, 8, 9 - i * 0.7, r, seed=31, alpha=a, tail=i >= 1)
        if i < 3:
            cloud(c, 4 + i * 0.3, 11 - i, r * 0.5, seed=32, alpha=a, tail=False)
        out.append(c)
    return out


def steam_push_frames() -> list:
    """30x22 «пар отбрасывает врага»: a gust shoves east from the curtain. 5 frames, anchor (3, 14) = the
    enemy's feet (the gust starts just behind/left of it). Speed streaks + a fat puff, then torn wisps."""
    out = []
    for i in range(5):
        c = Canvas(30, 22)
        t = i / 4
        a = (235, 225, 200, 150, 90)[i]
        cx = 5 + t * 16
        cloud(c, cx, 12 - t * 2, 3.2 + t * 2.6, seed=71 + (i > 2), alpha=a, tail=i >= 2)
        if i < 3:
            cloud(c, cx - 3, 15 - t, 2.0 + t * 1.2, seed=73, alpha=a, tail=False)
        for k, (dy, ln) in enumerate([(-4, 6), (0, 9), (4, 5), (7, 4)]):   # speed streaks
            x0 = int(cx + 4 + t * 4 + (k % 2) * 2)
            if i < 4:
                for x in range(x0, min(30, x0 + ln - i)):
                    c.set(x, 12 + dy, "steam_3" if x - x0 < 2 else "steam_2", a)
        for (dx, dy) in [(-2, 3), (2, 5), (6, 4)][: 3 - min(i, 3)]:   # hot droplets
            c.set(int(cx + dx + t * 6), 16 + dy - i, "teal_2")
        out.append(c)
    return out


def muzzle_smoke_frames() -> list:
    """14x14 grey-white smoke ring that puffs out of a muzzle and rises/fades. 5 frames, anchor (3, 9):
    spawn at the tower's manifest 'muzzle' point on frame 1 of the tower's fire animation."""
    out = []
    for i in range(5):
        c = Canvas(14, 14)
        t = i / 4
        a = (240, 220, 180, 130, 70)[i]
        cloud(c, 4 + t * 4, 9 - t * 4, 2.2 + t * 2.6, seed=81, alpha=a, dark="iron_1", mid="steam_1",
              light="steam_2", tail=i >= 2)
        if i == 0:
            c.set(2, 9, "ember_2")
            c.set(3, 8, "parchment_2")
        out.append(c)
    return out


def scrap_burst_frames() -> list:
    """32x32 kill burst: gears, bolts and plate shards fly out and fall, with a dust puff. 6 frames."""
    parts = [
        (-7, -9, "gear"), (6, -10, "plate"), (-10, -4, "bolt"), (9, -5, "bolt"),
        (-3, -12, "plate"), (3, -8, "gear_s"), (-6, -2, "bolt"), (7, -1, "plate"),
    ]
    out = []
    for f in range(6):
        c = Canvas(32, 32)
        t = (f + 1) / 6.0
        if f < 4:
            cloud(c, 16, 22 - f, 3 + f * 1.3, seed=41, alpha=(230, 200, 150, 90)[f],
                  dark="dust_2", mid="parchment_0", light="parchment_1", tail=False)
        for k, (vx, vy, kind) in enumerate(parts):
            x = 16 + vx * t * 1.4
            y = 20 + vy * t * 1.6 + 14 * t * t
            if y > 30:
                continue
            spin = (f + k) % 2
            if kind == "gear":
                c.ascii(int(x) - 2, int(y) - 2, ([".h.g.", "hhggf", ".gef.", "hggff", ".g.f."] if spin else
                                                 ["h.g.g", ".hgg.", "gg.ff", ".gff.", "g.f.f"]))
            elif kind == "gear_s":
                c.ascii(int(x) - 1, int(y) - 1, [".h.", "hgf", ".f."] if spin else ["h.g", ".f.", "g.f"])
            elif kind == "plate":
                c.ascii(int(x) - 2, int(y) - 1, ["ppoo", "oonn"] if spin else ["po.", "on.", ".nm"])
            else:
                c.ascii(int(x), int(y), ["dc", "cb"] if spin else ["d.", "cb"])
        c.outline("soot_0")
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
            cloud(c, 12, 18 - (i - 2) * 3, 3 + (i - 2) * 1.5, seed=51, alpha=(255, 220, 150)[i - 2], tail=i > 2)
            cloud(c, 8, 20 - (i - 2) * 2, 2 + (i - 2), seed=52, alpha=(255, 200, 130)[i - 2], tail=False)
        out.append(c)
    return out


# ------------------------------------------------------------------ pickups

def gear_coin_frames(size: int = 10, widths=(1.0, 0.6, 0.2, 0.6)) -> list:
    """Spinning gear coin (front, 3/4, edge, 3/4). 10x10 for drops, 8x8 x5 frames for the flying pickup."""
    out = []
    k = size / 10.0
    for i, sx in enumerate(widths):
        c = Canvas(size, size)
        cx, cy = (size - 1) / 2, (size - 1) / 2
        for y in range(10):
            for x in range(10):
                dx = (x - cx) / max(sx, 0.2)
                dy = y - cy
                r = math.hypot(dx, dy)
                ang = math.atan2(dy, dx)
                outer = (4.6 if math.cos(ang * 6) > 0.1 else 3.7) * k
                if r <= outer:
                    lit = -(x - cx) * 0.6 - dy * 0.8
                    name = "brass_3" if lit > 1.5 else "brass_2" if lit > -1.0 else "brass_1"
                    if r < 1.4 * k and sx > 0.5:
                        name = "brass_0"
                    c.set(x, y, name)
        if sx < 0.3:
            m = size // 2 - 1
            c.vline(m, 0, size - 1, "brass_2")
            c.vline(m + 1, 0, size - 1, "brass_1")
            c.set(m, 1, "brass_3")
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

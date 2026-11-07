"""C2 additions: the rest of the region 1-2 cast and the region-2 tower pair.

Enemies (face LEFT, anchor = feet): Жестяной латник (knight), Подручный вожака (guard),
Крот-шахтёр (mole). Towers (guns RIGHT, 32x40, anchor (16, 37), 3 tiers, 2 frames):
Пароструй (steam_jet), Котлобой (boiler).
"""
from pixel import Canvas, from_ascii, rim_light
import sprites_towers as TW
import sprites_units as UN

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
        c.recolor({"verdigris_2": "copper_3", "verdigris_1": "copper_2", "verdigris_0": "copper_1",
                   "ember_2": "iron_3", "ember_1": "iron_2"})
        bob = 0 if i % 2 == 0 else -1
        # pot helmet over the hood
        c.ascii(3, 0 + bob, [
            "..00000...",
            ".0dddcb0..",
            "0ddcccbb0.",
            "000000000.",
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


# ------------------------------------------------------------------ Крот-шахтёр (mole miner), 20x15

MOLE_BODY = """
.........0000.......
........0hhhg0......
.......0hhgggf0.....
...0TT0000000000....
...0TT0MMMMMMMLL00..
..0LLMMMMMMMMMMMLL0.
.0ppLMMNMMMMMMMMLL0.
0pp00MMMMMMMMMMMLLL0
.00.0LMMMMMMMMMMLLL0
....0LLLLMMMMMLLLL0.
.....00LLLLLLLLLL0..
"""
MOLE_FEET = [
    ("....0NN0....0NN0...", "....0000....0000..."),
    (".....0NN0..0NN0....", ".....0000..0000...."),
    ("...0NN0.....0NN0...", "...0000.....0000..."),
    (".....0NN0..0NN0....", ".....0000..0000...."),
]


def mole_frames() -> list:
    frames = []
    for i in range(4):
        c = Canvas(20, 15)
        for k, row in enumerate(MOLE_FEET[i]):
            c.ascii(0, 12 + k, row)
        bob = -1 if i % 2 else 0
        c.paste_over(from_ascii(MOLE_BODY), 0, 2 + bob)
        c.set(5, 7 + bob, "soot_0")      # eye
        # pickaxe over the shoulder
        c.ascii(12, 0 + bob, ["..0.", ".0c0", "0c0.", ".0n0"])
        rim_light(c)
        frames.append(c)
    return frames


# ------------------------------------------------------------------ Пароструй (steam jet tower)

def steam_jet(tier: int, fire: bool) -> Canvas:
    t = TW.TIERS[tier]
    m, tr = t["metal"], t["trim"]
    c = Canvas(TW.W, TW.H)
    TW.base(c, tier)
    TW.side_pipes(c, tier)
    TW.stack(c, tier, 4, fire)
    # upright boiler tank with a domed top
    c.rect(9, 12, 18, 26, m[1])
    c.vline(9, 12, 26, m[3])
    c.vline(10, 12, 26, m[2])
    c.vline(18, 12, 26, m[0])
    for y in (15, 20, 24):
        c.hline(9, 18, y, tr[1])
        c.set(9, y, tr[3])
    c.hline(10, 17, 11, m[2])
    c.hline(11, 16, 10, m[3])
    c.set(13, 9, tr[3])
    c.set(14, 9, tr[2])
    TW.gauge(c, 11, 16)
    # flared nozzle(s) to the right
    nozzles = (19,) if tier < 1 else ((19,) if tier == 1 else (16, 22))
    for ny in nozzles:
        for x in range(19, 30):
            half = 1 + (x - 19) * 3 // 10
            for y in range(ny - half, ny + half + 1):
                rel = (y - (ny - half)) / max(1, 2 * half)
                c.set(x, y, m[3] if rel < 0.25 else m[2] if rel < 0.6 else m[1] if rel < 0.85 else m[0])
        c.vline(29, ny - 4, ny + 4, tr[2])
        c.set(29, ny - 4, tr[3])
        c.vline(22, ny - 2, ny + 2, tr[1])
        if fire:
            for (dx, dy) in ((1, 0), (2, -2), (2, 2), (1, -3), (1, 3)):
                c.set(29 + dx, ny + dy, "steam_3" if dy % 2 == 0 else "steam_2")
    if tier == 2:
        TW.pennant(c, 6, 4, 1 if fire else 0)
    c.outline("soot_0")
    return c


# ------------------------------------------------------------------ Котлобой (boiler thrower)

def _boiler_ball(c: Canvas, cx: float, cy: float) -> None:
    c.shaded_disc(cx, cy, 4.2, ["copper_0", "copper_1", "copper_2", "copper_3"])
    c.hline(int(cx) - 3, int(cx) + 3, int(cy), "brass_2")
    c.set(int(cx) - 2, int(cy) - 3, "brass_3")
    c.set(int(cx), int(cy) - 5, "iron_2")      # little valve
    c.set(int(cx), int(cy) - 4, "iron_1")


def boiler(tier: int, fire: bool) -> Canvas:
    t = TW.TIERS[tier]
    m, tr = t["metal"], t["trim"]
    c = Canvas(TW.W, TW.H)
    TW.base(c, tier)
    TW.side_pipes(c, tier)
    TW.stack(c, tier, 4, fire)
    # A-frame of riveted beams
    c.line(9, 26, 14, 14, tr[1])
    c.line(10, 26, 15, 14, tr[2])
    c.line(21, 26, 16, 14, tr[0])
    c.line(20, 26, 15, 14, tr[1])
    c.hline(11, 20, 21, m[1])
    c.disc(15, 14, 1.6, m[3])
    # throwing arm: cocked back (idle) or swung forward (fire)
    if fire:
        c.line(15, 14, 26, 9, m[2])
        c.line(15, 15, 26, 10, m[0])
        c.rect(25, 8, 27, 11, tr[2])
        c.set(28, 7, "steam_3")
        c.set(29, 9, "steam_2")
    else:
        c.line(15, 14, 7, 7, m[2])
        c.line(15, 15, 7, 8, m[0])
        _boiler_ball(c, 7 if tier < 2 else 6, 5 if tier < 2 else 5)
        if tier == 2:
            c.set(10, 1, "steam_2")
            c.set(11, 0, "steam_3")
    # counterweight box
    c.rect(17, 16, 21, 20, m[1])
    c.hline(17, 21, 16, m[3])
    c.set(18, 18, t["rivet"])
    if tier == 2:
        TW.gauge(c, 22, 21)
        TW.pennant(c, 24, 4, 1 if fire else 0)
    c.outline("soot_0")
    return c


def r2_towers() -> dict:
    out = {}
    for name, fn in (("steam_jet", steam_jet), ("boiler", boiler)):
        for tier in range(3):
            out[f"{name}_t{tier}"] = [fn(tier, False), fn(tier, True)]
    return out

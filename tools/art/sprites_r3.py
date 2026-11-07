"""Region 3 «Медные болота» starters: Механожаба, Тесла-катушка, Рикошетная пушка and their effects.

Enemy main colours are checked (gen_art) against the region-3 ground `verdigris_0`.
"""
import math

from pixel import Canvas, cloud, from_ascii, rim_light, rng
import sprites_towers as TW

# ------------------------------------------------------------------ Механожаба (mechanical toad)

# Side view, facing LEFT: a broad flat head with a WIDE mouth seam running back to the cheek, brass
# goggle-eyes on top, an ember throat sac, a copper body with patina blotches, and big FOLDED hind legs
# with an iron coil spring between thigh and shin (that is what launches the hop).
TOAD_HEAD = """
.......00...00.......
......0hg0.0hg0......
.....0hyxh0hxxh0.....
...00pphhpppphhp00...
..0ppppppppppoooon0..
.0pppppppppoooooonn0.
.00000000000000onnn0.
.0RRRTRRpppp0oonnnnn0
..0QRRRQ0ppp0onnVnnnn0
...00000.000onnnnnVnn0
"""
TOAD_FRONT = """
...0pp0.
..0pp0..
.0ppp0..
.00000..
"""


def _toad(phase: str) -> Canvas:
    """phase: sit, crouch, leap, air, land."""
    c = Canvas(26, 30)
    gy = 28                       # ground line
    lift = {"sit": 0, "crouch": 0, "leap": 5, "air": 13, "land": 0}[phase]
    sq = {"sit": 0, "crouch": 1, "leap": -1, "air": 0, "land": 2}[phase]
    hx, hy = 1, gy - 15 - lift + sq
    head = from_ascii(TOAD_HEAD)
    # body: an egg sloping back and down behind the head
    for y in range(hy + 4, hy + 14 - sq):
        for x in range(10, 23):
            if ((x - 15.5) / 7.5) ** 2 + ((y - (hy + 9)) / (5.2 - sq * 0.4)) ** 2 <= 1:
                v = (y - (hy + 4)) / 9
                c.set(x, y, "copper_3" if v < 0.25 else "copper_2" if v < 0.7 else "copper_1")
    for (x, y) in [(14, hy + 6), (18, hy + 8), (16, hy + 10), (20, hy + 6)]:
        c.set(x, y, "verdigris_1")
        c.set(x + 1, y, "verdigris_2")
    c.paste_over(head, hx, hy)
    # front leg under the jaw
    if phase != "air":
        fl = from_ascii(TOAD_FRONT)
        c.paste_over(fl, 4, gy - 3 + (0 if phase != "leap" else -2))
    # hind leg: thigh (copper) + iron spring + long foot, folded (sit/crouch/land), stretched (leap), tucked (air)
    if phase in ("sit", "crouch", "land"):
        ty = gy - 9 + sq
        c.disc(20, ty, 3.6, "copper_2")
        c.disc(19.4, ty - 0.8, 2.2, "copper_3")
        coils = 3 if sq == 0 else 2
        for k in range(coils + 1):
            yy = ty + 3 + k * (5 - sq) // (coils + 1) + 0
            c.hline(15, 19, yy, "iron_3" if k % 2 == 0 else "iron_1")
        c.hline(9, 21, gy - 1, "copper_1")
        c.hline(10, 20, gy - 2, "copper_2")
        c.set(9, gy - 2, "copper_2")
    elif phase == "leap":
        # thigh up-back, spring stretched diagonally, foot pushing off behind
        c.disc(21, hy + 11, 3.2, "copper_2")
        for k in range(6):
            c.set(22 + k // 2 + (k % 2), hy + 14 + k, "iron_3" if k % 2 == 0 else "iron_1")
        c.hline(23, 25, gy - 1, "copper_1")
        c.set(22, gy - 2, "copper_2")
    else:  # air: legs tucked under, spring compact
        c.disc(19, hy + 12, 3.0, "copper_2")
        c.hline(13, 18, hy + 15, "iron_3")
        c.hline(13, 18, hy + 16, "iron_1")
        c.hline(11, 20, hy + 17, "copper_1")
    if phase == "land":
        for (dx, dy) in [(1, 0), (24, 0), (3, -2), (22, -2)]:
            c.set(dx, gy + dy, "dust_1")
    c.outline("soot_0")
    rim_light(c)
    return c


def toad_frames() -> list:
    """26x30 hop cycle, 5 frames (anchor (12, 28) = ground under the toad, constant):
    0 sit, 1 crouch (spring compressed), 2 leap (stretched, off the ground), 3 airborne (13 px up, legs
    tucked - not a ground target), 4 land (squash, mud flecks)."""
    return [_toad(p) for p in ("sit", "crouch", "leap", "air", "land")]


# ------------------------------------------------------------------ Тесла-катушка

def tesla(tier: int, phase: int) -> Canvas:
    """Tesla coil: ceramic insulator stack, a copper-wound coil, a brass sphere (toroid at tier 2).
    0 idle (faint crawl), 1 charge (arcs crawl over the sphere), 2 fire (a bolt leaves to the right)."""
    t = TW.TIERS[tier]
    c = Canvas(TW.W, TW.H)
    TW.base(c, tier)
    m, tr = t["metal"], t["trim"]
    TW.side_pipes(c, tier)
    # insulator discs (ceramic, parchment) at the bottom of the coil
    for k, y in enumerate((24, 22, 20)):
        c.hline(11, 20, y, "parchment_1")
        c.hline(11, 20, y + 1, "parchment_0")
        c.set(11, y, "parchment_2")
    # copper coil (horizontal windings, lit left)
    top = 9 if tier < 2 else 7
    for y in range(top, 20):
        for x in range(12, 20):
            u = (x - 12) / 7
            name = "copper_3" if u < 0.25 else "copper_2" if u < 0.6 else "copper_1"
            if (y - top) % 2:
                name = {"copper_3": "copper_2", "copper_2": "copper_1", "copper_1": "copper_0"}[name]
            c.set(x, y, name)
    c.hline(11, 20, 19, tr[1])
    c.hline(11, 20, top, tr[2])
    # sphere / toroid
    if tier < 2:
        c.shaded_disc(15.5, top - 3, 4.2 if tier == 0 else 4.8, list(tr))
    else:
        for y in range(top - 6, top):
            for x in range(8, 24):
                d = ((x - 15.5) / 7.5) ** 2 + ((y - (top - 3)) / 3.0) ** 2
                if d <= 1:
                    lit = -(x - 15.5) / 7.5 - (y - (top - 3)) / 3.0
                    c.set(x, y, tr[3] if lit > 0.6 else tr[2] if lit > -0.2 else tr[1])
        c.disc(15.5, top - 6, 2.0, tr[2])
        c.set(15, top - 7, tr[3])
    # tier 1+: brass ground rods beside the coil
    if tier >= 1:
        for x in (8, 23):
            c.vline(x, 16, 26, tr[1])
            c.set(x, 15, tr[3])
    if tier == 2:
        TW.pennant(c, 25, 8, 1 if phase == 2 else 0)
    c.outline("soot_0")
    sy = top - 3
    TW.MUZZLE[f"tesla_t{tier}"] = (20, sy)
    rr = rng(tier * 10 + phase)
    arcs = {0: 1, 1: 4, 2: 3}[phase]
    for _ in range(arcs):     # little arcs crawling over the sphere
        a = rr.uniform(-math.pi, 0.3)
        x, y = 15.5 + math.cos(a) * 5, sy + math.sin(a) * 4
        for k in range(3):
            c.set(round(x), round(y), "steam_3" if k == 0 else "teal_2")
            x += math.cos(a) * 1.2 + rr.uniform(-0.8, 0.8)
            y += math.sin(a) * 1.2 + rr.uniform(-0.8, 0.8)
    if phase == 2:   # the bolt leaving to the right
        x, y = 20, sy
        while x < 32:
            c.set(x, y, "parchment_2")
            c.set(x, y + 1, "teal_2")
            x += 1
            y += rr.choice((-1, 0, 0, 1))
        c.set(20, sy - 1, "steam_3")
    return c


def tesla_arc_frames() -> list:
    """16x16 crackling hit/charge burst (3-frame loop), anchor (8, 8)."""
    out = []
    for f in range(3):
        c = Canvas(16, 16)
        rr = rng(60 + f)
        for k in range(5):
            a = k * math.tau / 5 + f * 0.6 + rr.uniform(-0.3, 0.3)
            x, y = 8.0, 8.0
            for s in range(rr.randint(4, 7)):
                x += math.cos(a) + rr.uniform(-0.7, 0.7)
                y += math.sin(a) + rr.uniform(-0.7, 0.7)
                c.set(round(x), round(y), "steam_3" if s < 2 else "teal_2")
        c.set(8, 8, "parchment_2")
        c.set(7, 8, "steam_3")
        c.set(8, 7, "steam_3")
        out.append(c)
    return out


def chain_lightning_frames() -> list:
    """32x9 chain-lightning SEGMENT (3-frame flicker). Both ends sit on the centre line (y = 4), so
    segments tile end to end; stretch/rotate one per enemy-to-enemy link (anchor (0, 4))."""
    out = []
    for f in range(3):
        c = Canvas(32, 9)
        rr = rng(70 + f)
        y = 4
        pts = []
        for x in range(32):
            if 0 < x < 31 and x % 3 == 0:
                y = max(1, min(7, y + rr.choice((-2, -1, 1, 2))))
            if x >= 29:
                y = 4 + (1 if x == 29 and y > 4 else 0)
            pts.append((x, y))
        for (x, y) in pts:
            c.set(x, y - 1, "teal_2")
            c.set(x, y + 1, "teal_1")
        for (x, y) in pts:
            c.set(x, y, "parchment_2" if (x + f) % 5 else "steam_3")
        # a forked twig
        fx = rr.randint(8, 22)
        fy = pts[fx][1]
        for k in range(3):
            c.set(fx + k, fy - 1 - k if f % 2 else fy + 1 + k, "teal_2" if k else "steam_3")
        out.append(c)
    return out


# ------------------------------------------------------------------ Рикошетная пушка

def ricochet(tier: int, phase: int) -> Canvas:
    """Рикошетная пушка: a FIELD GUN, not a turret - a big spoked carriage wheel, a trail beam, a short fat
    bronze barrel cocked up ~15 deg with a bell muzzle, and a tall funnel hopper of balls over the breech.
    Tier 2: twin hoppers, gilding, pennant. 0 idle, 1 fire (recoil 2, flash), 2 recover (smoke)."""
    t = TW.TIERS[tier]
    c = Canvas(TW.W, TW.H)
    TW.base(c, tier)
    TW.side_pipes(c, tier)
    m, tr = t["metal"], t["trim"]
    TW.stack(c, tier, 3, phase == 1)
    rec = TW.RECOIL[phase]
    # trail beam to the deck
    c.line(5, 26, 14, 20, m[2])
    c.line(5, 27, 14, 21, m[0])
    # barrel along a slope: x 10..26, rising 4 px; bell over the last 3 px
    for i in range(0, 17):
        x = 10 + i - rec
        yc = 19 - i * 0.26
        half = 3.4 - i * 0.06 if i < 14 else 4.3
        for y in range(int(yc - half), int(yc + half) + 1):
            v = (y - (yc - half)) / max(1, 2 * half)
            c.set(x, y, "copper_3" if v < 0.22 else "copper_2" if v < 0.6 else "copper_1" if v < 0.86 else "copper_0")
    mx = 26 - rec
    c.vline(mx + 1, 11, 19, "soot_1")
    for x in (13 - rec, 20 - rec):
        yc = 19 - (x + rec - 10) * 0.26
        c.vline(x, int(yc - 3), int(yc + 3), tr[1])
        c.set(x, int(yc - 3), tr[3])
    # carriage wheel (spoked), in front of the barrel's base
    wx, wy = 14, 23
    for y in range(wy - 5, wy + 6):
        for x in range(wx - 5, wx + 6):
            d = math.hypot(x - wx, y - wy)
            if 3.9 <= d <= 5.2:
                c.set(x, y, tr[2] if (x - wx) + (y - wy) < 0 else tr[0])
    for k in range(4):
        ang = k * math.pi / 4 + (0.4 if phase == 1 else 0)
        for r in range(1, 4):
            c.set(round(wx + math.cos(ang) * r), round(wy + math.sin(ang) * r), m[1])
            c.set(round(wx - math.cos(ang) * r), round(wy - math.sin(ang) * r), m[1])
    c.disc(wx, wy, 1.2, tr[3])
    # funnel hopper(s) over the breech with balls showing
    for hx in ((9,) if tier < 2 else (5, 12)):
        for k, y in enumerate(range(5, 15)):
            half = 4 - k * 0.3
            c.hline(round(hx - half), round(hx + half), y, tr[1])
            c.set(round(hx - half), y, tr[3])
            c.set(round(hx + half), y, tr[0])
        c.hline(hx - 4, hx + 4, 5, tr[3])
        for (bx, by) in ((hx - 2, 4), (hx + 1, 3), (hx + 2, 5)):
            c.disc(bx, by, 1.3, "iron_1")
            c.set(bx - 1, by - 1, "iron_3")
    if tier == 2:
        TW.pennant(c, 26, 3, 1 if phase == 1 else 0)
    c.outline("soot_0")
    TW.MUZZLE[f"ricochet_t{tier}"] = (29, 15)
    if phase == 1:
        TW.flash(c, mx + 2, 15, big=True)
    elif phase == 2:
        TW.wisp(c, mx + 1, 12)
    return c


def ricochet_ball_frames() -> list:
    """8x8 iron ball with a brass band, spinning (4 frames). Anchor (4, 4)."""
    out = []
    for f in range(4):
        c = Canvas(8, 8)
        c.shaded_disc(3.5, 3.5, 3.4, ["soot_2", "iron_0", "iron_1", "iron_2"])
        a = f * math.pi / 4
        for k in (-2, -1, 0, 1, 2):
            c.set(round(3.5 + math.cos(a) * k), round(3.5 + math.sin(a) * k), "brass_2")
        c.set(2, 2, "iron_3")
        c.outline("soot_0")
        out.append(c)
    return out


def bounce_spark_frames() -> list:
    """16x12 spark where the ricochet ball bounces off an enemy (4 frames, once), anchor (8, 8)."""
    out = []
    rays = [(-6, -4), (6, -4), (-4, -6), (4, -6), (0, -7), (-7, 0), (7, -1)]
    for f in range(4):
        c = Canvas(16, 12)
        t = (f + 1) / 4
        for k, (dx, dy) in enumerate(rays):
            for s in range(2):
                x, y = 8 + dx * (t - s * 0.15), 8 + dy * (t - s * 0.15) + 3 * t * t
                if 0 <= y < 12:
                    c.set(round(x), round(y), ("parchment_2", "brass_3", "ember_2", "ember_1")[min(3, f + s)])
        if f < 2:
            c.set(8, 8, "parchment_2")
            c.hline(6, 10, 9, "brass_3" if f == 0 else "brass_1")
        out.append(c)
    return out


def icon_copper() -> Canvas:
    """16x16 Медь resource icon: two stacked copper ingots (trapezoid bars) with a lit top face."""
    c = from_ascii("""
................
................
......000000000.
.....0pppppppo0.
....0poooooooon0
....0000000000m0
...0pppppppppo0.
..0ppoooooooonn0
.00000000000n0m0
.0pppppppppp0mm0
0ppoooooooooon00
0onnnnnnnnnnnm0.
0mmmmmmmmmmmmm0.
.0000000000000..
................
................
""")
    assert (c.w, c.h) == (16, 16)
    return c


# ------------------------------------------------------------------ Аптекарь (apothecary), 18x24

APOTH = """
........000.......
.......01110......
.......01110......
......0000000.....
......0cLMcbb0....
.0000MMMNcbbb0....
0NMMMMMLLccbb0....
.0000LLL0ccbb0....
.......0cccbb0....
......0dccccbb0...
...000dccccccb0...
.0wxdd0ccccccb0e..
.0xy00dcccccbb0f..
.0ww0.dcccccbb0e..
..00..dccccbbb0...
......dcccccbbb0..
......0dccccbbb0..
.......000000000..
"""
APOTH_LEGS = [
    ["........0a0.0a0...", ".......0a0...0a0..", "......011....0110.", "......000....0000."],
    ["........0aa0a0....", "........0a0a0.....", ".......0110110....", ".......00000000..."],
    ["........0a0.0a0...", "........0a0..0a0..", ".......0110...011.", ".......0000...000."],
    ["........0aaa0.....", "........0aa0......", ".......01100......", ".......00000......"],
]


def apothecary_frames() -> list:
    """Аптекарь: a tall dark-grey frock coat (iron), a top hat, a LONG bone-coloured beak mask with a teal
    lens, a brass alembic flask on his back, and the front arm held out with a glowing teal flask (he
    heals neighbours). 4-frame walk, faces left."""
    out = []
    for i, legs in enumerate(APOTH_LEGS):
        c = Canvas(18, 24)
        for k, row in enumerate(legs):
            c.ascii(0, 20 + k, row)
        c.paste_over(from_ascii(APOTH), 0, 3 + (1 if i % 2 else 0))
        bob = 1 if i % 2 else 0
        c.set(9, 7 + bob, "teal_2")    # mask lens
        c.set(10, 7 + bob, "teal_1")
        if i % 2 == 0:                 # flask bubbles
            c.set(2, 12 + bob, "steam_3")
            c.set(3, 13 + bob, "teal_2")
        c.outline("soot_0")
        rim_light(c)
        out.append(c)
    return out


def heal_plus_frames() -> list:
    """9x14 «+» that rises over each HEALED neighbour (5 frames, once), anchor (4, 13) = its head top."""
    out = []
    for f in range(5):
        c = Canvas(9, 14)
        y = 9 - f * 2
        big = f < 3
        name = "parchment_2" if f in (1, 2) else "verdigris_2"
        arm = 2 if big else 1
        for k in range(-arm, arm + 1):
            c.set(4 + k, y, name)
            c.set(4, y + k, name)
        c.outline("verdigris_0")
        if f < 4:
            c.set(1, y + 3, "verdigris_2")
            c.set(7, y + 4, "teal_2")
        out.append(c)
    return out


def heal_pulse_frames() -> list:
    """40x24 heal pulse from the Аптекарь (5 frames, once), anchor (20, 16) = his feet: a flat ring
    spreading over the ground (patina green / teal), with small «+» crosses rising off it."""
    out = []
    for f in range(5):
        c = Canvas(40, 24)
        rx, ry = 4 + f * 4, 1.8 + f * 1.4
        for y in range(24):
            for x in range(40):
                d = ((x + 0.5 - 20) / rx) ** 2 + ((y + 0.5 - 16) / ry) ** 2
                if 0.45 < d <= 1.0:                       # a thick 2-3 px band
                    inner = d < 0.7
                    near = y < 16
                    if f < 3:
                        name = "parchment_2" if inner and near else "verdigris_2" if near else "teal_2"
                    else:
                        name = "verdigris_2" if near else "verdigris_1"
                    c.set(x, y, name, 255 if f < 4 else 180)
        for k, (dx, dy) in enumerate([(-8, -2), (7, -4), (0, -7), (-4, -10), (9, -11)]):
            if k > f + 1:
                continue
            x, y = 20 + dx, 14 + dy - f * 2
            if 1 <= y < 22:
                name = "verdigris_2" if (k + f) % 2 else "parchment_2"
                for (ox, oy) in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)):
                    c.set(x + ox, y + oy, name)
        out.append(c)
    return out


# ------------------------------------------------------------------ Водолаз (diver), 18x24

DIVER = """
......000000......
.....0pppoon0.....
....0pp0000nn0....
...0pp0wyxx0nn0...
...0p0wyxxww0nm0..
...0p0xxwwww0nm0..
...0pp0xwww0onm0..
....0ppp000oonm0..
.....0ppooonnm00..
....0hhgggggff0e0.
...0vuuuuuuutt0f0.
..0vu0uuuuuttt0e0.
..0uu0uuuuuttt0e0.
..0pp0uuuuutts0f0.
...00vuuuuuttt00..
....0vuuuuutts0...
....0uuuuuuttt0...
.....000000000....
"""
DIVER_LEGS = [
    ["......0a0.0a0.....", ".....0a0...0a0....", "....0cba...0cba...", "....0000...0000..."],
    ["......0aa0a0......", "......0a0a0.......", ".....0cbacba......", ".....00000000....."],
    ["......0a0.0a0.....", "......0a0..0a0....", ".....0cba...0cba..", ".....0000...0000.."],
    ["......0aaa0.......", "......0aa0........", ".....0cbba0.......", ".....000000......."],
]
DIVER_BARE_HEAD = """
.......0000.......
......0nnnn0......
.....0ppppnn0.....
.....0p0pp0n0.....
.....0ppppon0.....
......0pnpo0......
.......0000.......
"""


def diver_frames(helmet: bool = True) -> list:
    """Водолаз: a big riveted copper diving helmet with a teal porthole (the SHIELD: only steam/spark
    removes it), canvas suit, brass collar, air hose to a tank on the back, lead boots.
    helmet=False: the helmet is gone - a small bare head shows (after diver_helmet_break)."""
    out = []
    for i, legs in enumerate(DIVER_LEGS):
        c = Canvas(18, 24)
        for k, row in enumerate(legs):
            c.ascii(0, 20 + k, row)
        body = from_ascii(DIVER)
        bob = 1 if i % 2 else 0
        if helmet:
            c.paste_over(body, 0, 2 + bob)
            if i % 2 == 0:
                c.set(8, 1 + bob, "steam_3")       # an air bubble from the valve
        else:
            torso = Canvas(18, 24)
            torso.paste_over(body, 0, 0)
            for y in range(0, 9):
                for x in range(18):
                    torso.set(x, y, None)
            c.paste_over(torso, 0, 2 + bob)
            c.paste_over(from_ascii(DIVER_BARE_HEAD), 0, 4 + bob)
        c.outline("soot_0")
        rim_light(c)
        out.append(c)
    return out


def helmet_break_frames() -> list:
    """28x26 shield break (6 frames, once), anchor (14, 22) = the diver's feet: the copper helmet bursts
    open - a hiss of steam, the porthole glass shards and rivets fly, the dented shell drops behind."""
    out = []
    shards = [(-8, -8, "glass"), (7, -9, "glass"), (-10, -2, "rivet"), (9, -3, "rivet"), (-3, -12, "copper"),
              (4, -11, "copper"), (-6, -5, "glass"), (11, -7, "copper")]
    for f in range(6):
        c = Canvas(28, 26)
        t = (f + 1) / 6
        if f < 4:
            cloud(c, 14, 8 - f, 3 + f * 1.4, seed=171, alpha=(240, 220, 170, 100)[f], tail=f > 1)
        if f == 0:
            c.disc(14, 8, 4.5, "copper_2")
            c.disc(13, 7, 2.0, "teal_2")
            for (x, y) in ((10, 6), (17, 9), (14, 12)):
                c.set(x, y, "parchment_2")
        for k, (vx, vy, kind) in enumerate(shards):
            x = 14 + vx * t * 1.4
            y = 8 + vy * t * 1.3 + 18 * t * t
            if y > 25:
                continue
            if kind == "glass":
                c.set(x, y, "teal_2" if (k + f) % 2 else "steam_3")
                c.set(x + 1, y + (f % 2), "teal_1")
            elif kind == "rivet":
                c.ascii(int(x), int(y), ["dc", "cb"])
            else:
                c.ascii(int(x), int(y), ["po", "nm"] if (k + f) % 2 else ["op.", ".nm"])
        if f >= 2:   # the empty shell rolls away behind (right)
            hx = 16 + f * 2
            c.ellipse(hx, 21, 3.4, 2.6, "copper_2")
            c.set(hx - 1, 20, "copper_3")
            c.ellipse(hx + 1, 21, 1.4, 1.2, "soot_1")
        c.outline("soot_0")
        out.append(c)
    return out


# ------------------------------------------------------------------ Медный Спрут (boss)

OCTO_ROOTS = [(6, 33), (9, 39), (15, 44)]      # ends of the escort arms (attach tentacle_segment here)


def octopus(frame: int, cuts: int = 0) -> Canvas:
    """64x48 Медный Спрут, facing left: a tall riveted copper mantle bulging up and back, big brass-rimmed
    porthole eyes with slit pupils low at the front, a crown of valves, curling skirt tentacles that
    paddle. Three thick ESCORT arms reach forward-left; the escort tentacles (tentacle_segment /
    tentacle_tip) continue from their ends (manifest 'roots'). `cuts` = arms severed (stumps, 0..3)."""
    c = Canvas(64, 48)
    cx, cy, rx, ry = 38, 21, 19, 17
    # skirt tentacles (behind the mantle), curling at the tips
    for k in range(7):
        x0 = 24 + k * 5
        sway = math.sin((frame + k * 1.3) * math.pi / 2)
        side = 1 if k % 2 else -1
        for s_ in range(12):
            t = s_ / 11
            x = x0 + sway * 1.5 * t + side * (t ** 3) * 4
            y = 33 + s_ - (t ** 4) * 3
            w = 2.0 - t * 1.4
            c.disc(x, y, max(0.6, w), "copper_2" if s_ % 4 else "copper_1")
            if s_ % 3 == 1:
                c.set(round(x - side), round(y), "verdigris_2")
    # escort arms forward-left (before the mantle so the mantle overlaps their roots)
    starts = [(20, 30), (22, 34), (27, 37)]
    for i, ((sx, sy), (ex, ey)) in enumerate(zip(starts, OCTO_ROOTS)):
        if i < cuts:
            mx, my = (sx * 2 + ex) / 3, (sy * 2 + ey) / 3
            for s_ in range(8):
                t = s_ / 7
                c.disc(sx + (mx - sx) * t, sy + (my - sy) * t, 3.0 - t * 0.6, "copper_2")
            c.disc(mx, my, 2.0, "copper_0")
            c.disc(mx - 0.5, my, 1.2, "ember_1")
            c.set(round(mx), round(my) + 3 + frame % 2, "soot_0")      # oil drips from the stump
            c.set(round(mx), round(my) + 5 + frame % 2, "soot_1")
            continue
        for s_ in range(14):
            t = s_ / 13
            x = sx + (ex - sx) * t + math.sin(t * 3 + frame) * 0.8
            y = sy + (ey - sy) * t
            c.disc(x, y, 3.0 - t * 1.1, "copper_2")
            c.set(round(x), round(y - 2 + t), "copper_3")
            if s_ % 3 == 2:
                c.set(round(x + 1), round(y + 2 - t), "verdigris_2")
    # mantle: an egg tilted back (taller at the rear)
    for y in range(0, 40):
        for x in range(14, 60):
            u = (x - cx) / rx
            v = (y - cy) / (ry * (1 + 0.22 * u))
            if u * u + v * v <= 1 and y < 37:
                lit = -u * 0.8 - v
                name = "copper_3" if lit > 0.8 else "copper_2" if lit > -0.1 else "copper_1" if lit > -0.8 else "copper_0"
                c.set(x, y, name)
    for k, (x0, y0) in enumerate([(30, 6), (38, 4), (46, 7)]):          # plate seams with rivets
        for r in range(0, 26):
            x, y = x0 - r // 5 + k, y0 + r
            if c.opaque(x, y) and c.get(x, y)[:3] != (0, 0, 0):
                c.set(x, y, "copper_0")
                if r % 5 == 2:
                    c.set(x + 1, y, "copper_3")
    for (x, y) in [(50, 14), (51, 15), (51, 16), (52, 18), (44, 30), (45, 31), (33, 12)]:
        c.set(x, y, "verdigris_1")
    # big porthole eyes, low at the front, slit pupils
    for (ex, ey) in ((22, 25), (31, 25)):
        c.disc(ex, ey, 4.6, "brass_2")
        c.disc(ex - 0.3, ey - 0.3, 3.4, "teal_1")
        c.set(ex - 2, ey - 2, "brass_3")
        c.hline(ex - 2, ex + 1, ey, "soot_0" if frame % 4 != 3 else "teal_0")   # slit pupil (blinks)
        c.set(ex - 1, ey - 2, "steam_3")
        c.set(ex + 2, ey + 2, "teal_0")
    # crown of brass valves
    for (vx, vy) in ((32, 6), (40, 3), (48, 6)):
        c.rect(vx, vy - 3, vx + 2, vy, "brass_2")
        c.set(vx, vy - 3, "brass_3")
    c.outline("soot_0")
    if frame % 2 == 0:
        cloud(c, 41 + frame // 2, 0, 2.2, seed=180 + frame, alpha=200, tail=False)
    rim_light(c)
    return c


def octopus_frames() -> dict:
    return {f"cut{k}": [octopus(i, k) for i in range(4)] for k in range(4)}


def tentacle_segment_frames() -> list:
    """16x10 escort tentacle segment (4 frames ripple), anchor (0, 5): chain them from a boss root to the
    tip; each segment is 14 px long (overlap 2), rotate along the path. Copper with patina suckers."""
    out = []
    for f in range(4):
        c = Canvas(16, 10)
        for x in range(16):
            yc = 5 + 1.5 * math.sin((x + f * 4) / 16 * math.tau)
            w = 2.6 - x * 0.04
            for y in range(int(yc - w), int(yc + w) + 1):
                v = (y - (yc - w)) / max(1, 2 * w)
                c.set(x, y, "copper_3" if v < 0.3 else "copper_2" if v < 0.7 else "copper_1")
            if x % 4 == 1:
                c.set(x, int(yc + w), "verdigris_2")
        c.outline("soot_0")
        out.append(c)
    return out


def tentacle_tip_frames() -> list:
    """18x14 escort tentacle tip gripping the road (4 frames), anchor (16, 7) = where it joins the last
    segment: the arm tapers to the left and curls down into a hook that digs in, then pulls."""
    out = []
    for f in range(4):
        c = Canvas(18, 14)
        curl = (0.0, 0.25, 0.5, 0.25)[f]
        x, y, a = 16.0, 7.0, math.pi            # heading left
        for s_ in range(16):
            t = s_ / 15
            w = 2.4 - t * 1.9
            c.disc(x, y, max(0.6, w), "copper_2")
            c.set(round(x), round(y - w * 0.6), "copper_3")
            if s_ % 4 == 2 and w > 1:
                c.set(round(x), round(y + w), "verdigris_2")
            if t > 0.45:
                a -= 0.33 + curl * 0.2              # curl down/back into a hook
            x += math.cos(a) * 0.95
            y += -math.sin(a) * 0.95
        c.outline("soot_0")
        if f in (1, 2):
            c.set(2, 13, "dust_1")
            c.set(5, 13, "dust_1")
        out.append(c)
    return out


def tentacle_sever_frames() -> list:
    """28x22 a tentacle is cut (5 frames, once), anchor (14, 14): ember sparks, a spurt of black oil, the
    loose end flips away and drops."""
    out = []
    for f in range(5):
        c = Canvas(28, 22)
        t = (f + 1) / 5
        for k, (vx, vy) in enumerate([(-7, -6), (6, -8), (-9, 1), (8, 0), (0, -10)]):
            x, y = 14 + vx * t, 14 + vy * t + 8 * t * t
            c.set(x, y, "ember_2" if f < 3 else "ember_1")
        for k in range(4 + f):
            c.set(14 + k - f, 14 - 2 + k % 3 + f, "soot_0")
        ex, ey = 18 + f * 2, 8 + f * f // 2
        for s in range(6):
            c.disc(ex + s, ey + math.sin(s + f) * 1.5, 1.6, "copper_2")
        c.outline("soot_0")
        out.append(c)
    return out


# ------------------------------------------------------------------ producer: Медеплавильня

def smelter_frames(n: int = 6) -> list:
    """50x60 «Медеплавильня» for a yard slot (anchor (25, 59)): a brick furnace with a tall chimney, a
    crucible on a gantry that tips and pours molten copper into ingot moulds; finished ingots stack up.
    6-frame loop: pour glows and flickers, smoke rises, the stream wobbles."""
    out = []
    for f in range(n):
        c = Canvas(50, 60)
        for y in range(56, 60):
            c.hline(3, 49, y, "soot_2")
        # furnace body: brick courses
        c.rect(4, 26, 26, 55, "copper_0")
        for row, y0 in enumerate(range(26, 56, 3)):
            c.hline(4, 26, y0, "copper_1")
            for x in range(4 + (row % 2) * 3, 27, 6):
                c.vline(x, y0, y0 + 2, "soot_2")
        c.vline(4, 26, 55, "copper_2")
        # fire mouth
        c.rect(9, 42, 20, 55, "soot_0")
        c.rect(10, 45, 19, 55, "ember_0")
        c.rect(11, 47, 18, 55, "ember_1" if f % 2 else "ember_0")
        c.rect(13, 50, 16, 55, "ember_2")
        c.hline(9, 20, 42, "iron_1")
        # chimney
        c.rect(8, 4, 15, 25, "copper_1")
        c.vline(8, 4, 25, "copper_2")
        c.vline(15, 4, 25, "copper_0")
        for y in (8, 15, 22):
            c.hline(8, 15, y, "iron_1")
        c.hline(7, 16, 3, "iron_2")
        cloud(c, 12 + f % 3, 1, 2.2, seed=190 + f, alpha=200, dark="soot_2", mid="soot_3", light="iron_0", tail=False)
        # crucible on trunnions between two short iron posts (no gantry), tilting toward the mould
        for px_ in (29, 44):
            c.rect(px_, 22, px_ + 1, 46, "iron_1")
            c.vline(px_, 22, 46, "iron_2")
            c.disc(px_ + 0.5, 27, 1.6, "brass_2")
        c.hline(29, 45, 46, "iron_0")
        tilt = (0, 1, 2, 2, 1, 0)[f]
        cx, cy = 37, 27
        for y in range(cy - 5, cy + 5):
            for x in range(cx - 5, cx + 6):
                if ((x - cx) / 5.2) ** 2 + ((y - cy) / 4.6) ** 2 <= 1:
                    xx = x - (y - cy) * tilt // 3
                    c.set(xx, y, "iron_2" if x < cx - 1 else "iron_1" if x < cx + 3 else "iron_0")
        c.hline(cx - 5 - tilt, cx + 4 - tilt, cy - 5, "ember_2")       # molten surface
        c.hline(cx - 4 - tilt, cx + 3 - tilt, cy - 4, "ember_1")
        c.hline(30, 43, cy, "brass_1")                                  # trunnion axle
        # pour stream into the mould
        if tilt:
            for y in range(cy - 3, 47):
                c.set(cx - 6 - tilt + (y % 2 if f % 2 else 0), y, "ember_2" if y % 3 else "parchment_2")
        # moulds and stacked ingots
        c.rect(30, 47, 46, 50, "iron_0")
        c.hline(30, 46, 47, "iron_1")
        for x in (31, 36, 41):
            c.rect(x, 48, x + 3, 49, "ember_1" if (x // 5 + f) % 3 == 0 else "copper_2")
        for k, (ix, iy) in enumerate([(32, 54), (38, 54), (35, 52)]):
            if k <= f % 4:
                c.rect(ix, iy, ix + 4, iy + 1, "copper_2")
                c.hline(ix, ix + 4, iy, "copper_3")
        c.outline("soot_0")
        out.append(c)
    return out


# ------------------------------------------------------------------ Заряжающий автоматон

def automaton_frames() -> list:
    """12x16 spring-man that runs along the wall walkway carrying a shell (6-frame run, faces RIGHT; flip
    for the other way). Brass barrel body, a wind-up key turning on its back, iron legs. Anchor (6, 15)."""
    out = []
    key = [["h.", "hg", "h."], [".h", "gh", ".h"], ["hh", "g.", ".."], ["..", "g.", "hh"]]
    legs = [((-2, 0), (2, -1)), ((-1, -1), (1, 0)), ((0, -1), (0, 0)), ((2, -1), (-2, 0)), ((1, 0), (-1, -1)),
            ((0, 0), (0, -1))]
    for f in range(6):
        c = Canvas(12, 16)
        bob = 1 if f in (2, 5) else 0
        # legs
        for k, (dx, dy) in enumerate(legs[f]):
            x0 = 5 + k * 2
            c.line(x0, 10 + bob, x0 + dx, 14 + dy, "iron_2" if k == 0 else "iron_1")
            c.set(x0 + dx, 15 + dy, "iron_0")
            c.set(x0 + dx + 1, 15 + dy, "iron_0")
        # barrel body
        for y in range(4 + bob, 11 + bob):
            for x in range(4, 9):
                u = (x - 4) / 4
                c.set(x, y, "brass_3" if u < 0.25 else "brass_2" if u < 0.7 else "brass_1")
        c.hline(4, 8, 7 + bob, "brass_0")
        # head: a little gauge face
        c.disc(6, 2 + bob, 1.8, "iron_2")
        c.set(6, 2 + bob, "parchment_2")
        c.set(7, 2 + bob, "ember_1")
        # wind-up key on the back (left), turning
        c.ascii(1, 5 + bob, key[f % 4])
        # arms holding a shell in front
        c.disc(10, 7 + bob, 1.5, "soot_1")
        c.set(9, 6 + bob, "iron_1")
        c.line(8, 6 + bob, 9, 7 + bob, "iron_2")
        c.outline("soot_0")
        out.append(c)
    return out


def wet_metal_frames() -> list:
    """16x16 «Мокрый металл» (5 frames, once), anchor (8, 10): a scalded (wet) enemy hit by a spark -
    droplets flash white, blue-white sparks crackle across the wet surface, then a puff of steam."""
    out = []
    drops = [(3, 6), (12, 5), (6, 12), (11, 11), (8, 3)]
    for f in range(5):
        c = Canvas(16, 16)
        rr = rng(200 + f)
        for k, (x, y) in enumerate(drops):
            if f < 3:
                c.set(x, y + f, "teal_2")
                c.set(x, y + f - 1, "steam_3" if (k + f) % 2 else "parchment_2")
        if f in (1, 2, 3):
            for _ in range(3):
                x, y = 8.0, 9.0
                a = rr.uniform(0, math.tau)
                for s in range(rr.randint(3, 5)):
                    x += math.cos(a) * 1.3 + rr.uniform(-0.6, 0.6)
                    y += math.sin(a) * 1.3 + rr.uniform(-0.6, 0.6)
                    c.set(round(x), round(y), "steam_3" if s < 2 else "brass_3")
            c.set(8, 9, "parchment_2")
        if f >= 3:
            cloud(c, 8, 7 - (f - 3) * 2, 2.5 + (f - 3), seed=210, alpha=(200, 120)[f - 3], tail=False)
        out.append(c)
    return out

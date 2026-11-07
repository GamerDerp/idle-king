"""Region 3 «Медные болота» starters: Механожаба, Тесла-катушка, Рикошетная пушка and their effects.

Enemy main colours are checked (gen_art) against the region-3 ground `verdigris_0`.
"""
import math

from pixel import Canvas, from_ascii, rim_light, rng
import sprites_towers as TW

# ------------------------------------------------------------------ Механожаба (mechanical toad)

TOAD_SIT = """
....00....00......
...0hg0..0hg0.....
..0hyx0000yxh0....
..0gx0pppp0xg0....
.0pppppppppoooo0..
0ppVpppooopooVoo0.
0pppppoooooooooo0.
.0RRpooooooonnnn0.
..00oooVoonnnnVn0.
...0ooooonnnnnn0..
..0pp0onnnnn0pp0..
.0pp00000000.0pp0.
.000..........000.
"""
TOAD_CROUCH = """
..................
....00....00......
...0hg0..0hg0.....
..0hyx0000yxh0....
.0pgx0pppp0xgo0...
0pppppppppooooo0..
0ppVppooopooVooo0.
0RRpppoooooooonn0.
.00ooVoooonnnVnn0.
.0pp0ooonnnnnn0pp0
0pp000000000000pp0
000............000
"""
TOAD_LEAP = """
.....00....00.....
....0hg0..0hg0....
...0hyx0000yxh0...
...0gx0pppp0xg0...
..0pppppppppooo0..
.0ppVpppooopooV0..
.0pppppooooooooo0.
..0RRpooooooonnn0.
...00oooVoonnnn0..
....0ooooonnnn0...
...0pp0onnnn0pp0..
..0pp0.0000.0ppp0.
.0pp0........0pp0.
.000..........000.
"""


def toad_frames() -> list:
    """20x28 hop cycle, 5 frames (anchor (9, 26) = ground under the toad, constant):
    0 sit, 1 crouch, 2 leap (stretched, 4 px up), 3 airborne (12 px up, legs tucked - not a ground
    target), 4 land (squash). Copper body with patina spots, brass goggle-eyes, ember throat."""
    out = []
    specs = [(TOAD_SIT, 13, 0), (TOAD_CROUCH, 14, 0), (TOAD_LEAP, 9, 1), (TOAD_SIT, 1, 2), (TOAD_CROUCH, 14, 3)]
    for i, (art, y, kind) in enumerate(specs):
        c = Canvas(20, 28)
        body = from_ascii(art)
        c.paste_over(body, 1, y)
        if kind == 2:   # airborne: legs folded under, little spring coils visible
            c.set(4, y + 11, "iron_2")
            c.set(14, y + 11, "iron_2")
        if kind == 3:   # landing splash of mud
            for (dx, dy) in [(0, 26), (18, 26), (2, 24), (16, 24)]:
                c.set(dx, dy, "dust_1")
        c.outline("soot_0")
        rim_light(c)
        out.append(c)
    return out


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
    """Squat bronze cannon with a flared bell muzzle and a ball hopper on top; tier 2: twin hoppers,
    gilding, pennant. 0 idle, 1 fire (recoil 2, flash), 2 recover (smoke)."""
    t = TW.TIERS[tier]
    c = Canvas(TW.W, TW.H)
    TW.base(c, tier)
    TW.side_pipes(c, tier)
    m, tr = t["metal"], t["trim"]
    TW.stack(c, tier, 4, phase == 1)
    rec = -TW.RECOIL[phase]
    # carriage
    c.rect(8, 20, 20, 25, m[1])
    c.hline(8, 20, 20, m[3])
    c.vline(8, 20, 25, m[2])
    c.vline(20, 21, 25, m[0])
    # barrel: copper/bronze, fat, slightly tapered, bell muzzle
    for x in range(10 + rec, 27 + rec):
        u = (x - 10 - rec) / 16
        half = 3.6 - u * 0.8
        if x > 24 + rec:
            half = 4.2
        for y in range(int(19 - half), int(19 + half) + 1):
            v = (y - (19 - half)) / max(1, 2 * half)
            c.set(x, y, "copper_3" if v < 0.25 else "copper_2" if v < 0.6 else "copper_1" if v < 0.85 else "copper_0")
    for x in (14 + rec, 21 + rec):
        c.vline(x, 15, 23, tr[1])
        c.set(x, 15, tr[3])
    c.vline(27 + rec, 15, 23, "soot_1")
    c.disc(13, 22, 2.2, tr[1])
    c.set(12, 21, tr[3])
    # hopper with balls
    for hx in ((12,) if tier < 2 else (9, 16)):
        c.rect(hx, 9, hx + 6, 14, tr[1])
        c.hline(hx, hx + 6, 9, tr[3])
        c.vline(hx, 9, 14, tr[2])
        for (bx, by) in ((hx + 2, 8), (hx + 4, 7)):
            c.disc(bx, by, 1.4, "iron_1")
            c.set(bx - 1, by - 1, "iron_3")
    if tier == 2:
        TW.pennant(c, 25, 5, 1 if phase == 1 else 0)
    c.outline("soot_0")
    TW.MUZZLE[f"ricochet_t{tier}"] = (29, 19)
    if phase == 1:
        TW.flash(c, 28 + rec, 19, big=True)
    elif phase == 2:
        TW.wisp(c, 28 + rec, 16)
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
    """16x16 Медь resource icon: two stacked copper ingots with a bright sheen and a wire coil."""
    return from_ascii("""
................
................
.......00000000.
......0ppppppo00
.....0poooooon0m0
....0000000000mm0
....0pppppppp0m0.
...0poooooooonn0.
..00000000000nm0.
..0pppppppppp0m0.
.0poooooooooon00.
.0onnnnnnnnnnm0..
.0mmmmmmmmmmmm0..
..000000000000...
................
................
""")

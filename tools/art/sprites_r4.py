"""Region 4 «Часовой лес» (clockwork forest): enemies, towers, the Clock Tower mechanism, Пружины icon.

Walkers face LEFT; anchor = bottom-centre of the feet (for the flyer: the GROUND point under it).
Enemy main colours are checked (gen_art) against the region-4 ground `soot_3`.
"""
import math

from pixel import Canvas, cloud, from_ascii, rim_light, rng
import sprites_towers as TW


# ------------------------------------------------------------------ Часовой жук (clock beetle), 14x11

def beetle_frames() -> list:
    """Small swarm bug: a domed brass shell with a tiny clock dial on its back, a split seam, iron legs
    that scuttle (4 frames, fast), red jewel eyes at the front (left)."""
    out = []
    legs = [((-1, 1), (1, 0), (0, 1)), ((1, 0), (-1, 1), (1, 1)), ((-1, 0), (1, 1), (0, 0)), ((1, 1), (-1, 0), (-1, 1))]
    for f in range(4):
        c = Canvas(14, 11)
        bob = f % 2
        for k, (dx, dy) in enumerate(legs[f]):
            x = 4 + k * 3
            c.line(x, 7 - bob, x + dx - 1, 9 + dy, "iron_1")
            c.set(x + dx - 1, 10, "iron_0")
        for y in range(1 - bob + 1, 9 - bob):
            for x in range(2, 13):
                if ((x - 7.5) / 5.5) ** 2 + ((y - (7 - bob)) / 5.0) ** 2 <= 1:
                    lit = -(x - 7.5) / 5.5 - (y - 4) / 4
                    c.set(x, y, "brass_3" if lit > 0.9 else "brass_2" if lit > -0.3 else "brass_1")
        c.vline(8, 2 - bob + 1, 7 - bob, "brass_0")           # wing-case seam
        c.disc(10, 5 - bob, 1.6, "parchment_2")               # clock dial
        c.set(10, 4 - bob, "soot_1")
        c.set(11, 5 - bob, "soot_1")
        c.rect(1, 5 - bob, 2, 7 - bob, "iron_1")             # head
        c.set(1, 5 - bob, "ember_2")
        c.set(0, 4 - bob + (f % 2), "iron_2")                # antenna
        c.outline("soot_0")
        rim_light(c)
        out.append(c)
    return out


# ------------------------------------------------------------------ Заводной олень (clockwork stag), 28x26

def _stag(phase: int, dash: bool = False) -> Canvas:
    """Copper body, brass gear-antlers, a wind-up key in its back, iron legs. dash: body stretched,
    legs extended fore and aft, motion streaks behind (it lunges every 2 s)."""
    c = Canvas(30 if dash else 28, 28)
    ox = 2 if dash else 0
    bob = (0, -1, 0, 1)[phase % 4] if not dash else -1
    by = 15 + bob
    # legs
    if dash:
        lg = [((9, by + 4), (2, by + 10)), ((12, by + 4), (6, by + 11)), ((21, by + 4), (28, by + 9)),
              ((23, by + 4), (29, by + 11))]
    else:
        sw = (2, 0, -2, 0)[phase % 4]
        lg = [((9, by + 4), (8 - sw, 26)), ((12, by + 4), (12 + sw, 26)), ((20, by + 4), (19 + sw, 26)),
              ((23, by + 4), (24 - sw, 26))]
    for k, (a, b) in enumerate(lg):
        c.line(a[0] + ox * 0, a[1], b[0], b[1], "iron_2" if k % 2 == 0 else "iron_1")
        c.set(b[0], min(27, b[1] + 1), "iron_0")
    # body: an elongated copper barrel
    bw = 18 if not dash else 21
    for y in range(by - 4, by + 5):
        for x in range(7, 7 + bw):
            if ((x - (7 + bw / 2)) / (bw / 2)) ** 2 + ((y - by) / 4.6) ** 2 <= 1:
                v = (y - (by - 4)) / 8
                c.set(x, y, "copper_3" if v < 0.3 else "copper_2" if v < 0.7 else "copper_1")
    for x in (12, 18):
        c.vline(x, by - 3, by + 3, "copper_0")
        c.set(x + 1, by - 2, "copper_3")
    # wind-up key on the back
    kx = 17
    c.vline(kx, by - 7, by - 4, "iron_2")
    c.ascii(kx - 2, by - 10, ["hh.hh", "hgfgf", ".hgf."] if phase % 2 == 0 else [".hhh.", ".hgf.", ".hgf."])
    # neck + head (left): short thick neck
    c.line(9, by - 2, 6, by - 6, "copper_2")
    c.line(10, by - 2, 7, by - 6, "copper_2")
    c.line(11, by - 2, 8, by - 5, "copper_1")
    c.rect(1, by - 9, 7, by - 6, "copper_2")
    c.hline(2, 7, by - 9, "copper_3")
    c.set(0, by - 7, "copper_1")                              # muzzle
    c.set(1, by - 6, "copper_1")
    c.set(4, by - 8, "ember_2")                               # eye
    c.set(7, by - 10, "copper_1")                             # ear
    # branching brass antlers, a tiny gear on the main tine
    for (pts, n) in (([(5, by - 10), (4, by - 13), (2, by - 15), (1, by - 18)], "brass_2"),
                     ([(4, by - 13), (6, by - 16)], "brass_2"), ([(2, by - 15), (0, by - 16)], "brass_1"),
                     ([(6, by - 10), (8, by - 13), (10, by - 15), (12, by - 18)], "brass_3"),
                     ([(8, by - 13), (7, by - 16)], "brass_3"), ([(10, by - 15), (12, by - 15)], "brass_2")):
        for (a, b) in zip(pts, pts[1:]):
            c.line(a[0], a[1], b[0], b[1], n)
    for t in range(8):
        a = t / 8 * math.tau
        c.set(round(12 + math.cos(a) * 1.6), round(by - 20 + math.sin(a) * 1.6), "brass_3" if t % 2 else "brass_1")
    # tail
    c.set(25 if not dash else 28, by - 3, "parchment_1")
    c.outline("soot_0")
    if dash:   # motion streaks behind
        for k, y in enumerate((by - 3, by, by + 3)):
            c.hline(26, 29, y, "steam_2")
    rim_light(c)
    return c


def stag_frames() -> dict:
    return {"walk": [_stag(i) for i in range(4)], "dash": [_stag(i, True) for i in range(3)]}


# ------------------------------------------------------------------ Механокукушка (flying cuckoo)

def _cuckoo(f: int) -> Canvas:
    """22x16 carved-wood cuckoo with copper-plate wings, parchment chest, brass beak and a pendulum tail."""
    c = Canvas(22, 16)
    wing = (-4, -1, 3, -1)[f % 4]          # up, mid, down, mid
    # far wing (behind)
    for k in range(7):
        c.line(11, 7, 15 + k // 2, 7 + wing - 2 + k // 3, "copper_0")
    # body
    for y in range(4, 12):
        for x in range(5, 18):
            if ((x - 11) / 6.5) ** 2 + ((y - 8) / 3.6) ** 2 <= 1:
                v = (y - 4) / 7
                c.set(x, y, "copper_3" if v < 0.2 else "copper_2" if v < 0.8 else "copper_1")
    c.ellipse(9, 9, 3.5, 2.2, "parchment_1")                 # chest
    c.set(8, 8, "parchment_2")
    # head + beak + eye
    c.disc(5, 5, 2.8, "copper_2")
    c.set(4, 4, "copper_3")
    c.hline(0, 2, 5, "brass_3")
    c.set(1, 6, "brass_1")
    c.set(5, 4, "soot_0")
    c.set(4, 4, "parchment_2")
    # tail with a little brass pendulum
    c.line(17, 7, 21, 5, "copper_1")
    c.line(17, 8, 21, 7, "copper_0")
    c.vline(18, 10, 12, "iron_1")
    c.disc(18, 13, 1.2, "brass_2")
    # near wing: overlapping copper plates
    for k in range(4):
        x0 = 9 + k * 2
        c.line(x0, 7, x0 + 3, 7 + wing - 3 + k, "copper_3" if k == 0 else "copper_2")
        c.line(x0 + 1, 7, x0 + 4, 7 + wing - 3 + k, "copper_1")
    c.outline("soot_0")
    rim_light(c)
    return c


CUCKOO_ALT = 20     # how high the bird flies above its ground anchor (art px)


def cuckoo_frames() -> list:
    """22x40 frames: the bird flies CUCKOO_ALT px above the anchor (11, 38) = its ground point; bobs 1 px.
    Draw `cuckoo_shadow` at the same anchor (under the units): the gap between bird and shadow is what
    makes it read as airborne. Only lens / tesla / mortar hit it."""
    out = []
    for f in range(4):
        c = Canvas(22, 40)
        b = _cuckoo(f)
        c.paste_over(b, 0, 38 - CUCKOO_ALT - 14 + (1 if f == 2 else 0))
        out.append(c)
    return out


def cuckoo_shadow_frames() -> list:
    """22x6 bird-shaped soft shadow on the ground (wings spread / folded with the flap), anchor (11, 3)."""
    out = []
    for f in range(4):
        c = Canvas(22, 6)
        span = (9, 6, 3, 6)[f]
        c.ellipse(12, 3, 5.5, 1.8, "soot_0", 220)
        for x in range(12 - span, 13 + span):
            if abs(x - 12) > 3:
                c.set(x, 2 + (1 if abs(x - 12) > span - 2 else 0), "soot_0", 190)
        out.append(c)
    return out


def cuckoo_down_frames() -> list:
    """26x40 shot down (5 frames, once), anchor (13, 38) = ground: the bird tumbles out of the air,
    shedding feathers and a cog, and smashes on the ground in splinters."""
    out = []
    bird = _cuckoo(1)
    for f in range(5):
        c = Canvas(26, 40)
        y = 38 - CUCKOO_ALT - 14 + f * f * 1.6
        if f < 4:
            img = bird.img.rotate(-35 * f, expand=False)
            tmp = Canvas(22, 16)
            tmp.img = img
            tmp.px = img.load()
            c.paste_over(tmp, 2 + f, int(min(y, 24)))
        for k in range(f + 1):
            c.set(4 + k * 4, 10 + k * 3 + f * 2, "copper_2" if k % 2 else "parchment_1")
        if f == 4:
            for (dx, dy, n) in [(-6, 0, "copper_1"), (-3, -2, "copper_2"), (2, -1, "parchment_1"), (5, 0, "copper_1"),
                                (7, -3, "brass_2"), (-1, -4, "copper_2"), (0, 0, "copper_0")]:
                c.set(13 + dx, 37 + dy, n)
                c.set(14 + dx, 37 + dy, n)
            cloud(c, 13, 34, 3.0, seed=220, alpha=170, dark="dust_0", mid="dust_1", light="dust_2", tail=False)
        out.append(c)
    return out


# ------------------------------------------------------------------ boss: Часовщик + spring pylons

def clockmaker(frame: int, shield: bool = True) -> Canvas:
    """44x52 Часовщик, facing left: a tall automaton in a long brass-buttoned teal coat, a big clock face
    for a head (hands spin), a magnifier monocle, a giant winding key held like a staff. Walk 4 frames."""
    c = Canvas(44, 52)
    sw = (2, 0, -2, 0)[frame % 4]
    # legs
    for k, x0 in enumerate((17, 25)):
        dx = sw if k == 0 else -sw
        c.line(x0, 38, x0 + dx, 49, "iron_2" if k == 0 else "iron_1")
        c.line(x0 + 1, 38, x0 + dx + 1, 49, "iron_1")
        c.rect(x0 + dx - 2, 49, x0 + dx + 2, 50, "iron_0")
    # coat (a long cone)
    for y in range(18, 42):
        k = (y - 18) / 23
        half = 6 + k * 8
        for x in range(int(22 - half), int(22 + half) + 1):
            u = (x - (22 - half)) / max(1, 2 * half)
            c.set(x, y, "teal_2" if u < 0.2 else "teal_1" if u < 0.7 else "teal_0")
    for y in range(20, 41, 4):
        c.set(19 + (y - 20) // 8, y, "brass_3")              # buttons
    c.vline(21, 19, 41, "teal_0")
    c.hline(10, 34, 41, "brass_1")
    # collar + shoulders
    c.rect(14, 16, 30, 19, "brass_2")
    c.hline(14, 30, 16, "brass_3")
    # clock head
    hx, hy = 22, 9
    c.disc(hx, hy, 8.0, "brass_1")
    c.disc(hx, hy, 6.6, "parchment_2")
    c.disc(hx + 1, hy + 1, 5.5, "parchment_1")
    c.disc(hx, hy, 5.2, "parchment_2")
    for t in range(12):
        a = t / 12 * math.tau
        c.set(round(hx + math.cos(a) * 5), round(hy + math.sin(a) * 5), "soot_2" if t % 3 else "soot_0")
    for (ln, sp) in ((4, 1.0), (3, 0.25)):
        a = -math.pi / 2 + frame * sp * math.pi / 2
        for r in range(ln + 1):
            c.set(round(hx + math.cos(a) * r), round(hy + math.sin(a) * r), "soot_0")
    c.set(hx, hy, "ember_1")
    c.disc(hx - 6, hy + 3, 2.0, "brass_2")                   # monocle magnifier
    c.set(hx - 6, hy + 3, "teal_2")
    # the giant key as a staff (front arm)
    kx = 9 + (1 if frame % 2 else 0)
    c.vline(kx, 12, 46, "brass_1")
    c.vline(kx + 1, 12, 46, "brass_0")
    c.ascii(kx - 4, 6, [".hhh.hhh.", "hgggfgggf", "hgf0f0fgf", ".gff.ffe.", "....gf..."])
    c.line(kx + 1, 24, 15, 22, "teal_1")                       # arm
    c.disc(kx + 1, 24, 1.5, "iron_2")                          # hand
    c.outline("soot_0")
    rim_light(c)
    return c


def clockmaker_frames() -> list:
    return [clockmaker(i) for i in range(4)]


def pylon_frames(broken: bool = False) -> list:
    """14x28 spring-shield pylon (one of 3 around the Часовщик; anchor (7, 27)). Intact (4 frames): a brass
    post with a wound coil spring that hums and a teal arc at the top. Broken (2 frames): the spring
    has burst out of its post and hangs, sparking."""
    out = []
    for f in range(2 if broken else 4):
        c = Canvas(14, 28)
        c.rect(5, 6, 8, 25, "brass_1")
        c.vline(5, 6, 25, "brass_3")
        c.vline(8, 6, 25, "brass_0")
        c.rect(2, 24, 11, 26, "iron_1")
        c.hline(2, 11, 24, "iron_3")
        if not broken:
            for k, y in enumerate(range(8, 23, 2)):
                c.hline(3, 10, y + (f % 2 if k % 2 else 0) * 0, "iron_3" if (k + f) % 2 else "iron_2")
            c.disc(6.5, 4, 2.6, "brass_2")
            c.set(6, 3, "brass_3")
            for k in range(3):
                a = (f + k * 1.3) * 1.1
                c.set(round(6.5 + math.cos(a) * 4), round(4 + math.sin(a) * 3), "teal_2" if k % 2 else "steam_3")
        else:
            pts = [(6, 8), (9, 10), (11, 13), (10, 16), (12, 19), (11, 22)]
            for i, (x, y) in enumerate(pts):
                c.hline(x - 2, x + 1, y, "iron_3" if i % 2 else "iron_2")
            c.set(5, 5, "brass_0")
            c.set(7, 6, "brass_0")
            if f == 0:
                c.set(9, 7, "ember_2")
                c.set(11, 9, "parchment_2")
        c.outline("soot_0")
        out.append(c)
    return out


def pylon_break_frames() -> list:
    """28x28 pylon breaks (5 frames, once), anchor (14, 26): the coil snaps loose with a twang - brass
    bits, a teal flash and a puff."""
    out = []
    for f in range(5):
        c = Canvas(28, 28)
        t = (f + 1) / 5
        if f < 2:
            c.disc(14, 12, 4 + f * 3, "teal_2", 200)
            c.disc(14, 12, 2 + f * 2, "steam_3")
        for k, (vx, vy) in enumerate([(-9, -8), (8, -10), (-11, 0), (10, -2), (-3, -12), (5, -6)]):
            x, y = 14 + vx * t, 12 + vy * t + 12 * t * t
            c.ascii(int(x), int(y), ["hg", "gf"] if k % 2 else ["dc"])
        if f >= 2:
            cloud(c, 14, 18 - f, 3 + f, seed=230, alpha=(200, 150, 90)[f - 2], tail=False)
        out.append(c)
    return out


def shield_dome_frames() -> list:
    """64x40 shield dome around the Часовщик while any pylon stands (4-frame loop, anchor (32, 36)):
    a translucent teal ellipse with a turning ring of brass gear-teeth along its rim."""
    out = []
    for f in range(4):
        c = Canvas(64, 40)
        for y in range(40):
            for x in range(64):
                d = ((x + 0.5 - 32) / 30) ** 2 + ((y + 0.5 - 22) / 18) ** 2
                if d <= 1:
                    if d > 0.86:
                        c.set(x, y, "teal_2", 190 if y < 22 else 120)
                    elif d > 0.7 and y < 16:
                        c.set(x, y, "steam_3", 60)
        for t in range(28):
            a = t / 28 * math.tau + f * math.tau / 112
            if t % 2 == 0:
                c.set(round(32 + math.cos(a) * 30.5), round(22 + math.sin(a) * 18.5), "brass_3")
        out.append(c)
    return out


# ------------------------------------------------------------------ towers: Пилометатель, Заводной голем

def saw_thrower(tier: int, phase: int) -> Canvas:
    """Пилометатель: a spring sling on the turret base launches circular saw discs. A magazine of discs
    stands behind; the launch arm holds the next disc. 0 loaded, 1 thrown (arm forward, disc gone),
    2 reloading (a disc slides into the arm). Tier 2: twin magazine, gilded, pennant."""
    t = TW.TIERS[tier]
    c = Canvas(TW.W, TW.H)
    TW.base(c, tier)
    TW.side_pipes(c, tier)
    m, tr = t["metal"], t["trim"]
    TW.stack(c, tier, 3, phase == 1)
    # magazine of discs (stack seen edge-on)
    for k, mx in enumerate((7,) if tier < 2 else (5, 10)):
        for i in range(4):
            y = 24 - i * 3
            c.hline(mx - 3, mx + 3, y, "iron_3" if i % 2 else "iron_2")
            c.hline(mx - 3, mx + 3, y + 1, "iron_0")
        c.vline(mx - 4, 13, 25, tr[1])
        c.vline(mx + 4, 13, 25, tr[1])
    # slide rail + launch arm
    c.rect(12, 21, 27, 23, m[1])
    c.hline(12, 27, 21, m[3])
    arm_x = {0: 18, 1: 25, 2: 15}[phase]
    c.rect(arm_x - 1, 15, arm_x + 1, 22, tr[2])
    c.set(arm_x - 1, 15, tr[3])
    # spring behind the arm
    for k, x in enumerate(range(13, arm_x - 1)):
        c.set(x, 19 + (k % 2), tr[3] if k % 2 else tr[1])
    if phase != 1:
        dx = arm_x + 1 if phase == 0 else arm_x - 4
        _saw(c, dx + 3, 15, 4.0, 0)
    if tier == 2:
        TW.pennant(c, 26, 4, 1 if phase == 1 else 0)
    c.outline("soot_0")
    TW.MUZZLE[f"saw_t{tier}"] = (28, 15)
    if phase == 1:
        for (x, y) in ((28, 13), (29, 16), (27, 17)):
            c.set(x, y, "parchment_2")
    return c


def _saw(c: Canvas, cx: float, cy: float, r: float, rot: int) -> None:
    """A circular saw disc: steel with 12 teeth, a brass hub; rot rotates the teeth/glint by 15 deg steps."""
    for y in range(int(cy - r) - 2, int(cy + r) + 3):
        for x in range(int(cx - r) - 2, int(cx + r) + 3):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(dx, dy)
            a = math.atan2(dy, dx) + rot * math.pi / 12
            edge = r + (1.0 if (a * 12 / math.tau) % 1 < 0.45 else 0)
            if d <= edge:
                lit = -(dx * 0.6 + dy * 0.8) / r
                c.set(x, y, "steam_3" if d > r - 0.2 and lit > 0.2 else "iron_3" if lit > 0.3 else
                      "iron_2" if lit > -0.4 else "iron_1")
    c.disc(cx, cy, 1.4, "brass_2")
    c.set(int(cx), int(cy), "brass_0")
    ga = rot * math.pi / 6
    c.set(round(cx + math.cos(ga) * (r - 1.5)), round(cy + math.sin(ga) * (r - 1.5)), "parchment_2")


def saw_disc_frames() -> list:
    """12x12 flying saw disc, 4-frame spin, anchor (6, 6); it cuts through a line of enemies."""
    out = []
    for f in range(4):
        c = Canvas(12, 12)
        _saw(c, 6, 6, 4.0, f)
        c.outline("soot_0")
        out.append(c)
    return out


def golem_tower(tier: int, phase: int) -> Canvas:
    """Заводной голем: a clockwork brawler standing on an iron platform cantilevered over the moat
    (50x44, anchor (12, 41) = the platform's wall-side edge: place at (face_x1 + 1, y)). Barrel chest,
    a big riveted fist, a wind-up key on the back. 0 idle, 1 wind (key turns, crouch), 2 punch (arm
    shoots right on a piston, fist far out), 3 recover. Tiers: iron / brass trim / gilded, bigger fists."""
    t = TW.TIERS[tier]
    m, tr = t["metal"], t["trim"]
    c = Canvas(50, 44)
    # platform: grating deck + two diagonal brackets down to the wall
    c.rect(10, 38, 34, 40, "iron_1")
    c.hline(10, 34, 38, "iron_3")
    for x in range(12, 34, 3):
        c.set(x, 39, "soot_1")
    c.line(10, 41, 18, 43, "iron_2")
    c.line(10, 42, 16, 43, "iron_0")
    c.vline(10, 36, 43, "iron_2")
    crouch = 1 if phase == 1 else 0
    # legs
    c.rect(16, 31 + crouch, 18, 37, m[1])
    c.rect(24, 31 + crouch, 26, 37, m[1])
    c.vline(16, 31, 37, m[3])
    # torso: barrel chest
    ty = 16 + crouch
    for y in range(ty, ty + 16):
        for x in range(13, 30):
            if ((x - 21) / 8.5) ** 2 + ((y - (ty + 8)) / 8) ** 2 <= 1:
                u = (x - 13) / 16
                c.set(x, y, m[3] if u < 0.2 else m[2] if u < 0.55 else m[1] if u < 0.85 else m[0])
    for y in (ty + 4, ty + 11):
        c.hline(14, 28, y, tr[1])
    c.disc(21, ty + 8, 2.0, "parchment_2")               # chest gauge
    c.set(22, ty + 7, "ember_1")
    # head
    c.rect(18, ty - 5, 24, ty, m[2])
    c.hline(18, 24, ty - 5, m[3])
    c.hline(19, 23, ty - 3, "ember_1" if phase == 2 else "soot_1")   # eye slit lights up on the punch
    # key on the back
    ka = (0, 1, 0, 0)[phase]
    c.hline(10, 12, ty + 6, tr[2])
    c.ascii(7, ty + 3 + ka, ["hh", "hg", "gf", "ff"] if ka == 0 else ["hhh", ".g.", "fff"])
    # punching arm: shoulder at (28, ty+6); the piston extends right on phase 2
    ext = {0: 0, 1: -2, 2: 9, 3: 4}[phase]
    big = 3.6 + tier * 0.6
    sx, sy = 28, ty + 6
    c.rect(sx, sy - 1, sx + 4 + ext, sy + 1, "iron_2")
    c.hline(sx, sx + 4 + ext, sy - 1, "iron_3")
    fx = sx + 6 + ext
    c.disc(fx, sy, big, tr[2])
    c.disc(fx - 0.6, sy - 0.6, big - 1.4, tr[3])
    for k in range(3):
        c.set(int(fx + big - 1), int(sy - 2 + k * 2), tr[0])    # knuckles
    # the other arm hangs
    c.rect(11, ty + 7, 13, ty + 14, m[1])
    c.disc(12, ty + 15, 2.0, tr[1])
    if tier == 2:
        TW.pennant(c, 30, 2, 1 if phase == 2 else 0)
    c.outline("soot_0")
    if phase == 2:     # impact streaks
        for (dx, dy) in ((4, -3), (5, 0), (4, 3)):
            c.hline(int(fx + big + 1), int(fx + big + dx), sy + dy, "steam_3")
    TW.MUZZLE[f"golem_t{tier}"] = (int(sx + 15 + big), sy)
    return c


def punch_impact_frames() -> list:
    """20x20 punch shock (4 frames, once), anchor (10, 10): a ring with star spikes and a puff."""
    out = []
    for f in range(4):
        c = Canvas(20, 20)
        r = 2 + f * 2.2
        for t in range(24):
            a = t / 24 * math.tau
            c.set(round(10 + math.cos(a) * r), round(10 + math.sin(a) * r * 0.8),
                  "parchment_2" if f < 2 else "steam_2")
        if f < 2:
            for a in range(0, 360, 60):
                rad = math.radians(a + 30 * f)
                for k in range(2, 5):
                    c.set(round(10 + math.cos(rad) * (r + k)), round(10 + math.sin(rad) * (r + k)), "brass_3")
            c.disc(10, 10, 1.5, "parchment_2")
        out.append(c)
    return out


# ------------------------------------------------------------------ «Часовая башня» mechanism

def clock_tower(f: int, volley: int = -1) -> Canvas:
    """46x60 Clock Tower for a yard slot (anchor (23, 59)): a brick tower with a big clock face,
    a swinging pendulum in a glazed case below and two steam vents. 8-frame tick loop (minute hand
    steps, pendulum swings). volley >= 0: the «тик-так» volley flash frames (face lights up, the vents
    blow, rays burst)."""
    c = Canvas(46, 60)
    for y in range(56, 60):
        c.hline(4, 45, y, "soot_2")
    # tower body
    c.rect(8, 16, 38, 55, "copper_0")
    for row, y0 in enumerate(range(16, 56, 3)):
        c.hline(8, 38, y0, "copper_1")
        for x in range(8 + (row % 2) * 4, 39, 8):
            c.vline(x, y0, y0 + 2, "soot_2")
    c.vline(8, 16, 55, "copper_2")
    c.vline(38, 16, 55, "soot_3")
    # roof (pointed, verdigris) + finial
    for y in range(2, 17):
        half = (y - 2) * 1.25
        for x in range(int(23 - half), int(23 + half) + 1):
            u = (x - (23 - half)) / max(1, 2 * half)
            c.set(x, y, "verdigris_2" if u < 0.3 else "verdigris_1" if u < 0.7 else "verdigris_0")
    c.vline(23, 0, 2, "brass_3")
    # clock face
    fx, fy, r = 23, 26, 9.5
    lit = volley in (0, 1, 2)
    c.disc(fx, fy, r + 1.2, "brass_1")
    c.disc(fx, fy, r, "parchment_2" if not lit else "steam_3")
    c.disc(fx + 1, fy + 1, r - 1.5, "parchment_1" if not lit else "parchment_2")
    c.disc(fx, fy, r - 2.0, "parchment_2" if not lit else "steam_3")
    for t in range(12):
        a = t / 12 * math.tau
        rr_ = r - 1.2
        c.set(round(fx + math.cos(a) * rr_), round(fy + math.sin(a) * rr_), "soot_0" if t % 3 == 0 else "soot_2")
    step = f if volley < 0 else 0
    for (ln, a) in ((7, -math.pi / 2 + step * math.tau / 8), (4.5, -math.pi / 2 + math.tau * 0.3)):
        for k in range(int(ln) + 1):
            c.set(round(fx + math.cos(a) * k), round(fy + math.sin(a) * k), "soot_0")
    c.set(fx, fy, "brass_3")
    # pendulum case
    c.rect(18, 38, 28, 52, "soot_0")
    c.rect(19, 39, 27, 52, "teal_0")
    sw = math.sin(f / 8 * math.tau) * 3 if volley < 0 else 0
    c.line(23, 39, round(23 + sw), 47, "brass_1")
    c.disc(23 + sw, 48, 2.0, "brass_2")
    c.set(round(22 + sw), 47, "brass_3")
    c.hline(18, 28, 38, "brass_1")
    # steam vents
    for vx in (10, 34):
        c.rect(vx - 1, 32, vx + 1, 36, "iron_1")
        c.set(vx - 1, 32, "iron_3")
    c.outline("soot_0")
    if volley >= 0:
        a = (240, 200, 140, 80)[volley]
        for vx, side in ((10, -1), (34, 1)):
            cloud(c, vx + side * (2 + volley * 2), 30 - volley * 2, 2.5 + volley, seed=240 + vx, alpha=a, tail=False)
        if volley < 2:
            for k in range(8):
                ang = k / 8 * math.tau + 0.2
                for rr2 in range(int(r) + 2, int(r) + 5 + volley * 2):
                    c.set(round(fx + math.cos(ang) * rr2), round(fy + math.sin(ang) * rr2),
                          "parchment_2" if rr2 < r + 4 else "brass_3")
    return c


def clock_tower_frames() -> dict:
    return {"idle": [clock_tower(i) for i in range(8)], "volley": [clock_tower(0, v) for v in range(4)]}


def icon_springs() -> Canvas:
    """16x16 Пружины: an upright steel coil spring between two brass end caps; the front of every turn is
    lit (top-left light), the back of every turn is dark, so the coil reads as round."""
    c = Canvas(16, 16)
    for i in range(5):
        y0 = 4 + i * 2
        c.line(11, y0, 4, y0 + 1, "iron_0")               # back half of the turn
    for i in range(5):
        y0 = 4 + i * 2
        c.line(4, y0 + 1, 11, y0 + 2, "iron_2")           # front half
        c.set(5, y0 + 1, "iron_3")
        c.set(6, y0 + 1, "iron_3")
    for (y, n1, n2) in ((2, "brass_3", "brass_1"), (14, "brass_2", "brass_0")):
        c.hline(3, 12, y, n1)
        c.hline(3, 12, y + 1 if y == 2 else y - 1, n2)
        c.set(3, y, "brass_3")
    c.outline("soot_0")
    return c


# ------------------------------------------------------------------ background props

def brass_tree(seed: int, h: int = 30) -> Canvas:
    """Clockwork tree: a riveted brass trunk with bands, branching arms, a crown of copper-plate leaves
    with brass gears showing between them. Lit from the top-left; ~24 x h."""
    r = rng(seed)
    w = 32
    c = Canvas(w, h + 2)
    tx = w // 2
    # trunk
    for y in range(h // 2, h):
        half = 1.6 + (y - h / 2) / (h / 2) * 1.4
        for x in range(int(tx - half), int(tx + half) + 1):
            u = (x - (tx - half)) / max(1, 2 * half)
            c.set(x, y, "brass_3" if u < 0.25 else "brass_2" if u < 0.6 else "brass_1" if u < 0.85 else "brass_0")
    for y in range(h // 2 + 3, h, 5):
        c.hline(tx - 2, tx + 2, y, "brass_0")
    c.hline(tx - 4, tx + 4, h, "brass_0")
    c.set(tx - 4, h - 1, "brass_1")
    c.set(tx + 4, h - 1, "brass_1")
    # crown: copper leaf lobes
    # branches from the trunk top up into the crown
    for side in (-1, 1):
        c.line(tx, h // 2 + 2, tx + side * r.randint(5, 8), h // 2 - r.randint(3, 6), "brass_1")
    lobes = [(tx + r.uniform(-9, 9), r.uniform(h * 0.18, h * 0.5), r.uniform(4.0, 6.8)) for _ in range(r.randint(6, 8))]
    lobes.append((tx + r.uniform(-2, 2), h * 0.2, 6.0))
    lobes.sort(key=lambda l: -l[1])
    for (lx, ly, lr) in lobes:
        for y in range(int(ly - lr) - 1, int(ly + lr) + 2):
            for x in range(int(lx - lr) - 1, int(lx + lr) + 2):
                dx, dy = x + 0.5 - lx, y + 0.5 - ly
                if dx * dx + dy * dy <= lr * lr:
                    lit = -(dx * 0.6 + dy * 0.8) / lr
                    c.set(x, y, "copper_3" if lit > 0.45 else "copper_2" if lit > -0.2 else "copper_1" if lit > -0.7 else "copper_0")
    # leaf plate edges (small dark ticks) and gears peeking through
    for (lx, ly, lr) in lobes[::2]:
        c.set(int(lx + lr * 0.5), int(ly + lr * 0.3), "copper_0")
    for k in range(r.randint(1, 2)):
        gx, gy, gr = lobes[k][0], lobes[k][1], 2.4
        for t in range(12):
            a = t / 12 * math.tau
            rr_ = gr + (0.8 if t % 2 == 0 else 0)
            c.set(round(gx + math.cos(a) * rr_), round(gy + math.sin(a) * rr_), "brass_3" if a > 3 else "brass_2")
        c.set(int(gx), int(gy), "brass_0")
    c.outline("soot_0")
    return c


def fallen_gear(seed: int) -> Canvas:
    r = rng(seed)
    rad = r.uniform(3.0, 5.0)
    s = int(rad * 2 + 5)
    c = Canvas(s, s)
    cx = cy = s / 2
    teeth = r.choice((8, 10, 12))
    for y in range(s):
        for x in range(s):
            dx, dy = x + 0.5 - cx, (y + 0.5 - cy) * 1.6
            d = math.hypot(dx, dy)
            a = math.atan2(dy, dx)
            if rad * 0.35 < d <= rad + (0.9 if math.cos(a * teeth) > 0 else 0):
                lit = -(dx * 0.6 + dy * 0.5) / rad
                c.set(x, y, "brass_2" if lit > 0.2 else "brass_1" if lit > -0.4 else "brass_0")
    c.outline("soot_1")
    return c


def leaf_litter(c: Canvas, x0: int, y0: int, x1: int, y1: int, seed: int, keep) -> None:
    """Fallen copper leaves (tiny 2-3 px plates) scattered with blue noise."""
    from pixel import poisson as _p
    rr = rng(seed)
    for (x, y) in _p(x0, y0, x1, y1, 4.0, seed):
        if keep(x, y) and rr.random() < 0.14:
            n = rr.choice(("copper_1", "copper_1", "copper_2", "copper_0", "brass_1"))
            c.set(x, y, n)
            if rr.random() < 0.6:
                c.set(x + 1, y, n)
            if rr.random() < 0.3:
                c.set(x, y - 1, "copper_2" if n != "copper_2" else "copper_3")

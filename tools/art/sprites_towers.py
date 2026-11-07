"""Wall towers: Паровой стрелок (rifle), Клепальщик (riveter), Мортира (mortar).

Each type has 3 visual tiers: 0 iron, 1 brass, 2 gilded (extra pipes, gauges, pennant).
Sprite 32x40, 3 frames: 0 idle, 1 fire (barrel recoils 2 px, muzzle flash), 2 recover (barrel 1 px back,
smoke curling out of the muzzle). Anchor = (16, 37), the base's bottom centre. MUZZLE[sprite] = (x, y)
of the muzzle in frame pixels (for the muzzle_smoke fx and projectile spawn).
Guns point RIGHT (enemies come from the right).
"""
import math

from pixel import Canvas

TIERS = {
    0: {"trim": ("iron_0", "iron_1", "iron_2", "iron_3"), "metal": ("iron_0", "iron_1", "iron_2", "iron_3"),
        "rivet": "iron_3"},
    1: {"trim": ("brass_0", "brass_1", "brass_2", "brass_3"), "metal": ("iron_0", "iron_1", "iron_2", "iron_3"),
        "rivet": "brass_3"},
    2: {"trim": ("brass_0", "brass_1", "brass_2", "brass_3"), "metal": ("brass_0", "brass_1", "brass_2", "brass_3"),
        "rivet": "parchment_2"},
}
W, H = 32, 40
AX, AY = 16, 37
RECOIL = {0: 0, 1: 2, 2: 1}     # px the barrel slides back on frames 0 / 1 (fire) / 2 (recover)
MUZZLE = {}


def flash(c: Canvas, x: int, y: int, big: bool = False) -> None:
    """Muzzle flash: a hot core with a 4-point star and diagonal sparks (palette only, no glow)."""
    for dx in range(-1, 3 if big else 2):
        c.set(x + dx, y, "ember_2")
    for dx, dy in ((0, -1), (0, 1), (1, -1), (1, 1)):
        c.set(x + dx, y + dy, "ember_2")
    c.set(x, y, "parchment_2")
    c.set(x + 1, y, "parchment_2")
    for dx, dy in ((0, -2), (0, 2), (2, -2), (2, 2), (3 if big else 2, 0)):
        c.set(x + dx, y + dy, "ember_1")


def wisp(c: Canvas, x: int, y: int) -> None:
    """Smoke puff curling up out of the muzzle on the recover frame (opaque, lit top-left)."""
    for (dx, dy, n) in ((0, 0, "steam_1"), (1, 0, "steam_2"), (-1, -1, "steam_2"), (0, -1, "steam_3"),
                        (1, -1, "steam_2"), (2, -1, "steam_1"), (0, -2, "steam_3"), (1, -2, "steam_3"),
                        (2, -2, "steam_2"), (1, -3, "steam_2"), (2, -3, "steam_1"), (-1, 0, "iron_2"),
                        (3, -4, "steam_1")):
        c.set(x + dx, y + dy, n)


def base(c: Canvas, tier: int) -> None:
    """Round turret base: cylinder face + top deck, lit from the top-left."""
    t = TIERS[tier]
    cx, top, bot = 15.5, 27, 33
    rx, ry = 11.5, 4.5
    stone = ("soot_2", "soot_3", "iron_0", "iron_1") if tier == 0 else ("soot_3", "iron_0", "iron_1", "iron_2")
    # cylinder face
    for x in range(4, 28):
        u = (x - 4) / 23.0
        name = stone[3] if u < 0.15 else stone[2] if u < 0.5 else stone[1] if u < 0.85 else stone[0]
        yb = bot + int(ry * math.sqrt(max(0.0, 1 - ((x - cx) / rx) ** 2)))
        for y in range(top, yb + 1):
            c.set(x, y, name)
        # masonry courses
        for yy in (top + 3, top + 7):
            yy2 = yy + int(ry * math.sqrt(max(0.0, 1 - ((x - cx) / rx) ** 2)))
            if yy2 < yb:
                c.set(x, yy2, stone[0])
        # trim band at the top of the face
        yy = top + 1 + int(ry * math.sqrt(max(0.0, 1 - ((x - cx) / rx) ** 2)))
        c.set(x, yy, t["trim"][2] if u < 0.4 else t["trim"][1])
        c.set(x, yy + 1, t["trim"][0])
    # vertical joints on the face
    for x in (9, 15, 21):
        for k in range(2):
            yy = top + 4 + k + int(ry * math.sqrt(max(0.0, 1 - ((x - cx) / rx) ** 2)))
            c.set(x, yy, stone[0])
    # top deck ellipse
    for y in range(top - 5, top + 5):
        for x in range(4, 28):
            if ((x - cx) / rx) ** 2 + ((y - top) / ry) ** 2 <= 1.0:
                c.set(x, y, t["metal"][1])
    for y in range(top - 5, top + 5):
        for x in range(4, 28):
            d = ((x - cx) / rx) ** 2 + ((y - top) / ry) ** 2
            if 0.62 < d <= 1.0:
                lit = (x - cx) * -0.5 + (y - top) * -1.0
                c.set(x, y, t["trim"][3] if lit > 2 else t["trim"][2] if lit > -2 else t["trim"][1])
    # rivets on the rim
    for x in (7, 12, 19, 24):
        yy = top + int(3.6 * math.sqrt(max(0.0, 1 - ((x - cx) / rx) ** 2)))
        c.set(x, yy, t["rivet"])


def gauge(c: Canvas, x: int, y: int) -> None:
    c.disc(x + 1.5, y + 1.5, 2.0, "brass_1")
    c.set(x + 1, y + 1, "parchment_2")
    c.set(x + 2, y + 1, "parchment_2")
    c.set(x + 1, y + 2, "parchment_1")
    c.set(x + 2, y + 2, "ember_1")


def pennant(c: Canvas, x: int, y: int, wave: int) -> None:
    c.vline(x, y, y + 9, "iron_0")
    c.set(x, y - 1, "brass_3")
    rows = ["RRRR", "RRR.", "QR.."] if wave == 0 else ["RRR.", "RRRR", "QQ.."]
    c.ascii(x + 1, y, [r.replace("R", "R").replace("Q", "Q") for r in rows])


def stack(c: Canvas, tier: int, x: int, smoke: bool = False) -> None:
    """Exhaust stack behind the gun: none at tier 0, short at tier 1, tall with a brass crown at tier 2."""
    if tier == 0:
        return
    top = 11 if tier == 1 else 1
    for y in range(top, 22):
        c.set(x, y, "copper_3")
        c.set(x + 1, y, "copper_2")
        c.set(x + 2, y, "copper_1")
    for y in range(top + 4, 22, 5):
        c.hline(x, x + 2, y, "copper_0")
    c.hline(x - 1, x + 3, top, "brass_3" if tier == 2 else "copper_3")
    c.hline(x - 1, x + 3, top + 1, "brass_1" if tier == 2 else "copper_1")
    c.hline(x, x + 2, top - 1, "soot_0")
    if tier == 2:
        c.set(x - 1, top - 1, "brass_2")
        c.set(x + 3, top - 1, "brass_2")
    if smoke:
        c.set(x + 1, top - 2, "steam_1")
        c.set(x + 2, top - 3, "steam_2")


def side_pipes(c: Canvas, tier: int) -> None:
    """Extra copper pipes on the gilded tier (from the base into the gun body)."""
    if tier < 2:
        return
    c.vline(5, 16, 27, "copper_1")
    c.vline(6, 16, 27, "copper_3")
    c.vline(7, 16, 27, "copper_2")
    c.hline(5, 9, 15, "copper_2")
    c.hline(5, 9, 14, "copper_3")
    c.set(5, 15, "copper_1")


def rifle(tier: int, phase: int) -> Canvas:
    t = TIERS[tier]
    c = Canvas(W, H)
    fire = phase == 1
    base(c, tier)
    side_pipes(c, tier)
    m, tr = t["metal"], t["trim"]
    rec = -RECOIL[phase]
    stack(c, tier, 5, fire)
    # steam tank behind (left), round, with a gauge
    c.shaded_disc(10.5, 19.5, 5.2 + (1 if tier == 2 else 0), list(tr), outline=None)
    c.hline(6, 15, 19, tr[0])
    gauge(c, 8, 15)
    # turret head (bigger at tier 2)
    hy0 = 17 if tier < 2 else 14
    c.rect(12, hy0, 21, 25, m[1])
    c.hline(12, 21, hy0, m[3])
    c.vline(12, hy0, 25, m[2])
    c.hline(12, 21, 25, m[0])
    c.vline(21, hy0 + 1, 25, m[0])
    c.set(14, hy0 + 3, t["rivet"])
    c.set(19, hy0 + 3, t["rivet"])
    # long barrel(s) to the right: one, or two stacked at tier 2
    bx0 = 21 + rec
    for by in ((19,) if tier < 2 else (16, 21)):
        c.hline(bx0, 30 + rec, by, m[3])
        c.hline(bx0, 30 + rec, by + 1, m[2])
        c.hline(bx0, 30 + rec, by + 2, m[0])
        c.rect(bx0 + 1, by - 1, bx0 + 2, by + 3, tr[2])   # barrel band
        c.set(bx0 + 1, by - 1, tr[3])
        c.vline(30 + rec, by - 1, by + 3, tr[1])          # muzzle
        c.set(30 + rec, by - 1, tr[3])
    if tier == 1:
        c.hline(bx0 + 4, bx0 + 7, 18, tr[1])   # sight rail
        c.set(bx0 + 4, 17, tr[3])
    if tier == 2:
        pennant(c, 13, 6, 1 if fire else 0)
    c.outline("soot_0")
    for by in ((19,) if tier < 2 else (16, 21)):
        MUZZLE[f"rifle_t{tier}"] = (31, by + 1)
        if phase == 1:
            flash(c, 29, by + 1, big=True)
        elif phase == 2:
            wisp(c, 29, by - 1)
    return c


def riveter(tier: int, phase: int) -> Canvas:
    t = TIERS[tier]
    c = Canvas(W, H)
    fire = phase == 1
    base(c, tier)
    side_pipes(c, tier)
    m, tr = t["metal"], t["trim"]
    rec = -RECOIL[phase]
    stack(c, tier, 4, fire)
    by0 = 15 if tier < 2 else 13
    # boxy body (taller at tier 2)
    c.rect(8 + rec, by0, 22 + rec, 25, m[1])
    c.hline(8 + rec, 22 + rec, by0, m[3])
    c.vline(8 + rec, by0, 25, m[2])
    c.hline(8 + rec, 22 + rec, 25, m[0])
    c.vline(22 + rec, 16, 25, m[0])
    for (x, y) in [(10, 17), (20, 17), (10, 23), (20, 23), (15, 23)]:
        c.set(x + rec, y, t["rivet"])
    # drum magazine(s) on top (seen from the side: short cylinders); two at tier 2
    for dx, dy in ((0, 0),) if tier < 2 else ((-2, -2), (5, 0)):
        x0, y0 = 10 + rec + dx, 9 + dy - (2 if tier == 2 else 0)
        c.rect(x0, y0, x0 + 8, y0 + 6, tr[1])
        c.hline(x0, x0 + 8, y0, tr[3])
        c.vline(x0, y0, y0 + 6, tr[2])
        c.vline(x0 + 8, y0 + 1, y0 + 6, tr[0])
        for x in (2, 4, 6):
            c.vline(x0 + x, y0 + 1, y0 + 5, tr[0])
    # twin short barrels
    for y in (18, 22):
        c.hline(22 + rec, 28 + rec, y, m[3])
        c.hline(22 + rec, 28 + rec, y + 1, m[0])
        c.set(28 + rec, y, tr[3])
        c.set(28 + rec, y + 1, tr[1])
    c.rect(23 + rec, 17, 24 + rec, 24, tr[2])
    c.set(23 + rec, 17, tr[3])
    # rivet belt hanging from the drum
    if tier >= 1:
        for k, y in enumerate(range(15, 20)):
            c.set(7 + rec - (k % 2), y, "iron_3" if k % 2 else "iron_1")
    if tier == 2:
        gauge(c, 4, 18)
        pennant(c, 19, 2, 1 if fire else 0)
    c.outline("soot_0")
    MUZZLE[f"riveter_t{tier}"] = (29, 20)
    for y in (18, 22):
        if phase == 1:
            flash(c, 29 + rec + 1, y)
        elif phase == 2 and y == 18:
            wisp(c, 29 + rec, y - 1)
    return c


def mortar(tier: int, phase: int) -> Canvas:
    t = TIERS[tier]
    c = Canvas(W, H)
    fire = phase == 1
    base(c, tier)
    side_pipes(c, tier)
    m, tr = t["metal"], t["trim"]
    rec = RECOIL[phase]
    stack(c, tier, 4, fire)
    fat = 4 if tier == 2 else 3
    # heavy cradle
    c.rect(8, 19, 22, 25, m[1])
    c.hline(8, 22, 19, m[3])
    c.vline(8, 19, 25, m[2])
    c.vline(22, 20, 25, m[0])
    c.hline(8, 22, 25, m[0])
    # fat tube angled up-right (45 deg), 7 px thick
    cx, cy = 15 - rec, 19 + rec
    for k in range(0, 10):
        x0, y0 = cx + k, cy - k
        for j in range(-fat, fat + 1):
            px, py = x0 + j, y0 + j
            shade = m[3] if j <= -fat + 1 else m[2] if j <= 0 else m[1] if j <= fat - 1 else m[0]
            c.set(px, py, shade)
            c.set(px + 1, py, shade)
    # muzzle ring
    mx, my = cx + 10, cy - 10
    for j in range(-fat - 1, fat + 2):
        c.set(mx + j, my + j, tr[2] if j < 0 else tr[1])
        c.set(mx + j + 1, my + j, tr[3] if j < 0 else tr[2])
    c.set(mx - 1, my - 2, "soot_0")
    c.set(mx, my - 1, "soot_0")
    c.set(mx + 1, my, "soot_0")
    # band around the tube
    for j in range(-3, 4):
        c.set(cx + 4 + j, cy - 4 + j, tr[2] if j < 1 else tr[0])
    # trunnion
    c.disc(15, 21, 2.2, tr[1])
    c.set(14, 20, tr[3])
    # shells stacked on the deck
    for (sx, sy) in ([(6, 26), (9, 27)] if tier >= 1 else [(7, 26)]):
        c.disc(sx, sy, 1.6, "soot_1")
        c.set(sx - 1, sy - 1, "iron_1")
    if tier == 2:
        gauge(c, 22, 22)
        pennant(c, 6, 9, 1 if fire else 0)
    c.outline("soot_0")
    MUZZLE[f"mortar_t{tier}"] = (cx + 12, cy - 12 - rec)
    if phase == 1:
        flash(c, mx + 2, my - 3)
        c.set(mx + 3, my - 5, "ember_1")
    elif phase == 2:
        wisp(c, mx + 1, my - 3)
        c.set(mx + 3, my - 6, "steam_2")
        c.set(mx + 4, my - 7, "steam_1")
    return c


def all_towers() -> dict:
    out = {}
    for name, fn in (("rifle", rifle), ("riveter", riveter), ("mortar", mortar)):
        for tier in range(3):
            out[f"{name}_t{tier}"] = [fn(tier, 0), fn(tier, 1), fn(tier, 2)]
    return out

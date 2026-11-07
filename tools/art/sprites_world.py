"""World sprites: ground, road, moat, steam curtain, wall, gatehouse, pipes, chimneys, battlefield bg.

Light comes from the top-left: lit edges are top/left, shadows fall to the bottom-right.
"""
import math

import layout as L
from pixel import C, Canvas, cloud, from_ascii, rng


# ------------------------------------------------------------------ ground

def ground_tile(seed: int) -> Canvas:
    """16x16 seamless dry wasteland tile."""
    c = Canvas(16, 16, "dust_1")
    r = rng(seed)
    # darker patches (wrap-around), kept blobby not noisy
    for _ in range(1 if seed % 2 else 0):
        cx, cy = r.randrange(16), r.randrange(16)
        rx, ry = r.uniform(1.5, 3), r.uniform(1.0, 1.6)
        for y in range(16):
            for x in range(16):
                dx = min(abs(x - cx), 16 - abs(x - cx))
                dy = min(abs(y - cy), 16 - abs(y - cy))
                if (dx / rx) ** 2 + (dy / ry) ** 2 <= 1:
                    c.set(x, y, "dust_0")
    # pebbles: lit top-left pixel, shadow bottom-right
    for _ in range(r.randint(0, 2)):
        x, y = r.randrange(16), r.randrange(16)
        c.set(x, y, "dust_2")
        c.set((x + 1) % 16, (y + 1) % 16, "dust_0")
    # hairline crack
    if seed % 3 == 0:
        x, y = r.randrange(16), r.randrange(16)
        for _ in range(5):
            c.set(x % 16, y % 16, "dust_0")
            x += r.choice((1, 1, 0))
            y += r.choice((0, 1))
    return c


def road_tile(seed: int) -> Canvas:
    """16x16 seamless packed-dirt road tile with wheel ruts (horizontal)."""
    c = Canvas(16, 16, "dust_2")
    r = rng(seed + 100)
    for x in range(16):
        c.set(x, 5, "dust_1")
        c.set(x, 11, "dust_1")
        if (x + seed) % 5 == 0:
            c.set(x, 6, "dust_1")
        if (x + seed) % 7 == 0:
            c.set(x, 12, "dust_1")
    for _ in range(3):
        x, y = r.randrange(16), r.randrange(16)
        if y in (5, 11):
            continue
        c.set(x, y, "parchment_0")
        c.set((x + 1) % 16, (y + 1) % 16, "dust_1")
    return c


def decal_rocks(seed: int) -> Canvas:
    c = Canvas(9, 6)
    r = rng(seed)
    w = r.randint(4, 6)
    c.ellipse(w / 2 + 0.5, 3, w / 2, 2.2, "dust_0")
    c.ellipse(w / 2, 2.5, w / 2 - 0.5, 1.6, "dust_2")
    c.set(1, 2, "parchment_0")
    c.set(2, 1, "parchment_0")
    if r.random() < 0.6:
        c.ellipse(w + 1.5, 4, 1.4, 1.2, "dust_0")
        c.set(w + 1, 3, "dust_2")
    return c


def decal_grass(seed: int) -> Canvas:
    """Dry grass tuft."""
    c = Canvas(7, 6)
    r = rng(seed)
    cols = ["brass_1", "brass_2", "parchment_0"] if seed % 3 else ["verdigris_0", "verdigris_1", "brass_1"]
    for i in range(r.randint(3, 4)):
        x = 1 + i + r.randint(0, 1)
        h = r.randint(2, 5)
        lean = r.choice((-1, 0, 1))
        for k in range(h):
            c.set(x + (lean if k > h // 2 else 0), 5 - k, cols[0] if k == 0 else cols[1 if k < h - 1 else 2])
    return c


def decal_scrap(seed: int) -> Canvas:
    """Rusty debris half-buried: a gear rim, a bent pipe or a plate."""
    kind = seed % 3
    c = Canvas(12, 9)
    if kind == 0:  # half-buried gear
        for y in range(9):
            for x in range(12):
                d = math.hypot(x - 5.5, y - 6)
                ang = math.atan2(y - 6, x - 5.5)
                outer = 5 if math.cos(ang * 7) > 0 else 4
                if 2 < d <= outer and y <= 6:
                    lit = (x - 5.5) * -0.6 + (y - 6) * -0.8
                    c.set(x, y, "copper_2" if lit > 2 else "copper_1")
        c.hline(0, 11, 7, "dust_0")
    elif kind == 1:  # bent pipe
        c.hline(1, 8, 5, "copper_1")
        c.hline(1, 8, 4, "copper_2")
        c.hline(2, 6, 3, "copper_3")
        c.vline(9, 1, 5, "copper_1")
        c.vline(8, 1, 4, "copper_2")
        c.set(8, 1, "copper_3")
        c.hline(0, 10, 6, "dust_0")
    else:  # riveted plate
        c.rect(1, 2, 9, 6, "iron_1")
        c.hline(1, 9, 2, "iron_2")
        c.set(2, 3, "iron_3")
        c.set(8, 3, "copper_2")
        c.set(2, 5, "copper_1")
        c.set(8, 5, "iron_3")
        c.hline(1, 10, 7, "dust_0")
        c.set(10, 3, "copper_1")
    return c


# ------------------------------------------------------------------ moat & steam

def moat_frames() -> list:
    """30x64 boiling-water tile, 4 frames, tiles vertically. x=0 touches the wall face.

    Tall tile + scattered features so the repetition is not visible; every bubble has its own phase.
    """
    TW = L.MOAT_X1 - L.MOAT_X0 + 1
    TH = 64
    r = rng(21)
    bubbles = []
    for _ in range(14):
        bubbles.append((r.randrange(7, TW - 3), r.randrange(2, TH - 2), r.randrange(4), r.random() < 0.35))
    ripples = [(r.randrange(6, TW - 4), r.randrange(TH), r.randint(2, 4)) for _ in range(9)]
    frames = []
    for f in range(4):
        c = Canvas(TW, TH, "teal_1")
        # the wall shades the water near it (light from the left)
        for y in range(TH):
            c.hline(0, 4, y, "teal_0")
            c.set(5, y, "teal_0" if (y + f) % 2 == 0 else "teal_1")
        # depth at the foot of the stone bank on the east side, with a crisp foam lace (opaque pixels)
        for y in range(TH):
            c.hline(TW - 2, TW - 1, y, "teal_0")
            if (y + f) % 3 == 0:
                c.set(TW - 3, y, "teal_0")
            ph = (y * 7 + f * 3) % 11
            if ph in (0, 1):
                c.set(TW - 3, y, "steam_2")
            elif ph == 2:
                c.set(TW - 4, y, "teal_2")
            elif ph == 5:
                c.set(TW - 3, y, "teal_2")
        # slow ripples: short highlight dashes drifting down with the frame (wrap)
        for (x, y, ln) in ripples:
            yy = (y + f) % TH
            c.hline(x, x + ln - 1, yy, "teal_2")
        for (bx, by, ph, big) in bubbles:
            st = (f + ph) % 4
            if st == 0:
                c.set(bx, by, "teal_2")
            elif st == 1:
                c.set(bx - 1, by, "teal_2")
                c.set(bx + 1, by, "teal_2")
                c.set(bx, by - 1, "steam_2")
                c.set(bx, by + 1, "teal_2")
                c.set(bx, by, "teal_0")
            elif st == 2 and big:
                c.hline(bx - 1, bx + 1, by - 1, "teal_2")
                c.set(bx, by - 1, "steam_3")
                c.set(bx - 2, by, "teal_2")
                c.set(bx + 2, by, "teal_2")
                c.hline(bx - 1, bx + 1, by + 1, "teal_2")
                c.hline(bx - 1, bx + 1, by, "teal_0")
            elif st == 2:
                c.set(bx, by - 1, "steam_3")
                c.set(bx - 1, by, "teal_2")
                c.set(bx + 1, by, "teal_2")
            else:  # popped: spray dots
                c.set(bx - 1, by - 1, "steam_2")
                c.set(bx + 1, by - 2, "steam_3")
        frames.append(c)
    return frames


def puff(c: Canvas, cx: float, cy: float, r: float, alpha: int = 255, dark: str = "steam_1",
         mid: str = "steam_2", light: str = "steam_3") -> None:
    """Round cloud puff lit from the top-left: rounded highlight cap, crescent shadow (no outline)."""
    hx, hy, hr = cx - r * 0.3, cy - r * 0.35, r * 0.62
    sx, sy, sr = cx - r * 0.18, cy - r * 0.22, r * 0.92
    for y in range(int(cy - r) - 1, int(cy + r) + 2):
        for x in range(int(cx - r) - 1, int(cx + r) + 2):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            if dx * dx + dy * dy <= r * r:
                if (x + 0.5 - hx) ** 2 + (y + 0.5 - hy) ** 2 <= hr * hr:
                    name = light
                elif (x + 0.5 - sx) ** 2 + (y + 0.5 - sy) ** 2 <= sr * sr:
                    name = mid
                else:
                    name = dark
                c.set(x, y, name, alpha)


SHEET_W, SHEET_H = 40, 72


def steam_sheet_frames(n: int = 6) -> list:
    """40x72 rising steam column (anchor = nozzle mouth, bottom-left). Loops seamlessly.

    The column leaves the nozzle as a short jet over a crisp churn of foam, rises nearly vertically
    (that is height in the 3/4 view), then the moat's draft bends it east so the thin, torn top drifts
    over the east bank. Its silhouette is a union of discs whose radii bulge and scroll upward, so the
    edge is lumpy; lit top-left rim, shaded lower-right rim, a few curl lines where the bulges meet.
    Steam is semi-transparent; the foam at its foot is opaque - the two never read the same.
    Columns every 18 px overlap into the curtain.
    """
    P = 12.0                       # bulge period along the column (scrolls P per loop)
    L_ = SHEET_H - 12
    frames = []
    for f in range(n):
        off = f * P / n
        discs = []
        for si in range(0, int(L_) + 1):
            s_ = float(si)
            k = s_ / L_
            x = 4.0 + (k ** 1.35) * 22.0 + 0.8 * math.sin((s_ - off) / 6.0)
            y = SHEET_H - 3 - s_
            ph = ((s_ - off) / P) % 1.0
            r = (1.8 + 4.4 * k ** 0.8) * (0.86 + 0.26 * math.sin(math.tau * ph))
            torn = k > 0.72 and math.sin(math.tau * (s_ - off) / (P * 1.5) + 1.0) > 0.35
            discs.append((x, y, r, k, ph, torn))

        def inside(px, py):
            for (x, y, r, k, ph, torn) in discs:
                if not torn and (px - x) ** 2 + (py - y) ** 2 <= r * r:
                    return k
            return None
        c = Canvas(SHEET_W, SHEET_H)
        for py in range(SHEET_H):
            for px in range(SHEET_W):
                k = inside(px + 0.5, py + 0.5)
                if k is None:
                    continue
                a = int(210 - 150 * k)
                if inside(px - 0.7, py - 1.2) is None:
                    name = "steam_3"                         # lit rim
                elif inside(px + 2.0, py + 1.5) is None:
                    name = "steam_1"                         # shaded rim
                else:
                    name = "steam_2"
                c.set(px, py, name, a)
        # curl lines: the lower-right arc of each bulge, inside the column
        for (x, y, r, k, ph, torn) in discs:
            if torn or abs(ph - 0.25) > 0.5 / P or k < 0.12:
                continue
            for t in range(-2, 5):
                ang = math.radians(10 + t * 18)
                qx, qy = x + math.cos(ang) * (r - 1), y + math.sin(ang) * (r - 1)
                if c.opaque(int(qx), int(qy)) and inside(qx + 1.5, qy + 1.5) is not None:
                    c.set(int(qx), int(qy), "steam_1", int(210 - 150 * k))
        for y in range(SHEET_H - 4, SHEET_H):      # the jet out of the nozzle
            for x in range(0, 8 - (SHEET_H - 1 - y)):
                c.set(x, y, "steam_3" if y >= SHEET_H - 2 else "steam_2", 230)
        # opaque foam churn where the jet hits the water (crisp pixels, teal + white)
        for i, (dx, dy) in enumerate([(1, 0), (3, 0), (5, 0), (7, 0), (9, 0), (2, -1), (6, -1), (4, 1), (8, 1)]):
            if (i + f) % 3:
                c.set(dx + (f % 2), SHEET_H - 1 + min(0, dy), "steam_3" if (i + f) % 2 else "teal_2")
        frames.append(c)
    return frames


CURTAIN_X = L.PIPE_X + 11      # left edge of the curtain sprite (nozzle mouths are at x = CURTAIN_X + 2)
CURTAIN_W = 64


def steam_curtain_frames(n: int = 6) -> list:
    """The whole steam curtain as ONE sprite (64 x field height, anchor (0, 0) at (CURTAIN_X, 0)), 6-frame loop.

    One plume per nozzle (layout.STEAM_VENTS_Y, none at the gate). Every plume has its own length, lean,
    width and pulse phase (seeded), so there is no regular rhythm: it leaves the nozzle as a jet, rises,
    and the moat's draft bends it east; the thin, torn tops drift over the east bank and the field edge -
    that horizontal reach is the curtain's HEIGHT in the 3/4 view. Plumes are merged before shading
    (lit rim top-left, shaded rim bottom-right on the outer silhouette only; no inner rib lines).
    The steam gets more transparent toward the top. Its SHADOW lies on the water (soot, offset
    down-right, clearly visible between plumes). The foam churn at each nozzle is opaque and crisp."""
    H = L.H
    P = 12.0
    vents = [vy for vy in L.STEAM_VENTS_Y if abs(vy - L.GATE_Y) >= 30]
    water_x1 = L.MOAT_X1 - CURTAIN_X            # last water column inside the sprite
    rr = rng(404)
    params = []
    for vi, vy in enumerate(vents):
        params.append({"len": rr.uniform(26, 58), "lean": rr.uniform(14, 60), "wide": rr.uniform(0.7, 1.35),
                       "rise": rr.uniform(0.6, 1.2), "ph": rr.uniform(0, 1), "dy": rr.randint(-3, 3),
                       "tear": rr.uniform(0.62, 0.9), "pow": rr.uniform(1.2, 2.4)})
    # one or two sputtering nozzles: a short weak puff instead of a plume (breaks the herringbone)
    for vi in (3, 11):
        if vi < len(params):
            params[vi]["len"] = rr.uniform(9, 13)
            params[vi]["wide"] = 0.8
    frames = []
    for f in range(n):
        off = f * P / n
        discs = []      # (x, y, r, k, vent_index)
        for vi, vy in enumerate(vents):
            p = params[vi]
            pulse = 0.88 + 0.12 * math.sin(math.tau * (f / n + p["ph"]))
            L_ = p["len"] * pulse
            for si in range(0, int(L_) + 1):
                s_ = float(si)
                k = s_ / L_
                ph = ((s_ - off + vi * 5) / P) % 1.0
                x = 2.0 + 3.0 * k + p["lean"] * k ** p["pow"] + 0.9 * math.sin((s_ - off) / 5.0 + vi * 1.7)
                y = vy + p["dy"] - 1 - s_ * p["rise"]
                r = (1.5 + 4.3 * k ** 0.75) * p["wide"] * (0.82 + 0.28 * math.sin(math.tau * ph))
                if k > p["tear"] and math.sin(math.tau * (s_ - off + vi * 7) / 13.0) > 0.45:
                    continue        # torn top: separate tufts
                discs.append((x, y, r, k, vi))
        grid = {}
        for (x, y, r, k, vi) in discs:
            for py in range(int(y - r) - 1, int(y + r) + 2):
                for px in range(int(x - r) - 1, int(x + r) + 2):
                    if 0 <= px < CURTAIN_W and 0 <= py < H and (px + 0.5 - x) ** 2 + (py + 0.5 - y) ** 2 <= r * r:
                        old = grid.get((px, py))
                        if old is None or k < old[0]:
                            grid[(px, py)] = (k, vi)
        c = Canvas(CURTAIN_W, H)
        # shadow on the water first: the low part of the steam shifted down-right, clipped to the water
        for (px, py), (k, vi) in grid.items():
            for (ox, oy, a) in ((4, 7, 105), (5, 9, 70)):
                sx, sy = px + ox, py + oy
                if sx <= water_x1 and sy < H and (sx, sy) not in grid and k < 0.6 and not c.opaque(sx, sy):
                    c.set(sx, sy, "soot_0", a)
        for (px, py), (k, vi) in grid.items():
            a = int(215 - 130 * k)
            up, left = grid.get((px, py - 1)), grid.get((px - 1, py))
            down, right = grid.get((px, py + 1)), grid.get((px + 1, py))
            if up is None or left is None:
                name = "steam_3" if k < 0.8 else "steam_2"
            elif down is None or right is None:
                name = "steam_1"
            else:
                name = "steam_2"
            c.set(px, py, name, a)
        for vi, vy in enumerate(vents):      # opaque jets + foam churn at the nozzles
            jl = 5 + int(params[vi]["wide"] * 3)
            for y in range(vy - 3, vy + 1):
                for x in range(1, jl - (vy - y)):
                    c.set(x, y, "steam_3" if y >= vy - 1 else "steam_2", 230)
            for i, (dx, dy) in enumerate([(2, 1), (4, 1), (6, 1), (8, 1), (10, 1), (3, 2), (7, 2), (5, 0), (9, 0)]):
                if (i + f + vy) % 3:
                    c.set(dx + (f % 2), vy + dy - 1, "steam_3" if (i + f) % 2 else "teal_2")
        frames.append(c)
    return frames


def steam_shadow_frames(n: int = 6) -> list:
    """Shadow of a steam column on the water: 30x12, anchor (0, 0) = the nozzle mouth.
    Light is top-left, so the column's shadow falls to the lower right; draw it after the water, before
    the pipes and the columns. Semi-transparent soot (a shadow, not a colour)."""
    frames = []
    for f in range(n):
        c = Canvas(30, 12)
        for x in range(30):
            t = x / 29
            cy = 2.0 + t * 6.0 + 0.6 * math.sin(math.tau * (f / n) + x / 5.0)
            half = 1.2 + 2.2 * math.sin(math.pi * min(1.0, t * 1.15))
            for y in range(12):
                d = abs(y - cy)
                if d <= half:
                    c.set(x, y, "soot_0", 70 if d < half - 0.8 and 3 < x < 24 else 40)
        frames.append(c)
    return frames


def steam_wisp_frames(n: int = 8) -> list:
    """36x30 loose wisps that break off the curtain and drift east over the bank, fading out (loop).
    Place a few along the bank (x ~ bank_x0 - 6, any y), above the enemies layer."""
    frames = []
    for f in range(n):
        c = Canvas(36, 30)
        for j, (sx, sy, sr, seed) in enumerate([(4, 24, 3.0, 61), (8, 18, 2.4, 62)]):
            t = ((f + j * n // 2) % n) / n
            x = sx + t * 24
            y = sy - t * 14
            r = sr + t * 2.5
            a = int(170 * (1 - t) ** 0.8)
            if a > 20:
                cloud(c, x, y, r, seed=seed + f // 2, alpha=a, tail=t > 0.3)
        frames.append(c)
    return frames


def steam_pipe(valve: bool = False) -> Canvas:
    """14x18 tile of the brass steam main running along the moat's west edge, one nozzle per tile.

    The pipe (x 0..5) tiles vertically; the 4x5 nozzle points east over the water (mouth at x=13, y=10).
    """
    c = Canvas(14, 18)
    cols = ["brass_0", "brass_3", "brass_2", "brass_2", "brass_1", "brass_0"]
    for x, n in enumerate(cols):
        c.vline(x, 0, 17, n)
    c.hline(0, 5, 0, "brass_0")      # flange at the joint
    c.hline(0, 5, 1, "brass_3")
    c.set(5, 1, "brass_1")
    # nozzle: short neck, flared mouth, dark opening
    c.rect(6, 8, 9, 12, "brass_1")
    c.hline(6, 9, 8, "brass_3")
    c.hline(6, 9, 9, "brass_2")
    c.hline(6, 9, 12, "brass_0")
    c.rect(10, 7, 12, 13, "brass_2")
    c.vline(10, 7, 13, "brass_3")
    c.hline(10, 12, 13, "brass_0")
    c.vline(12, 8, 12, "brass_1")
    c.vline(13, 8, 12, "soot_0")
    c.vline(12, 9, 11, "soot_1")
    if valve:
        c.ascii(0, 2, ["..eee..", ".eh.ge.", "ehgggfe", "e.gfg.e", ".ee.ee."])
    c.outline("soot_0")
    return c


def smoke_frames(n: int = 4) -> list:
    """16x24 chimney smoke, sooty irregular puffs with torn tails (anchor bottom-centre)."""
    frames = []
    for f in range(n):
        c = Canvas(16, 24)
        for k in range(3):
            y = (k * 8 + f * 2) % 24
            t = y / 24
            r = 2.2 + t * 3.0
            cx = 6 + t * 4 + (1 if k % 2 else 0)
            cloud(c, cx, 21 - y, r, seed=k * 7 + 1, alpha=255 if t < 0.6 else 170,
                  dark="soot_3", mid="iron_0", light="iron_1", tail=t > 0.3)
        frames.append(c)
    return frames


# ------------------------------------------------------------------ pipes & chimneys

def pipe_h(length: int, ramp=("brass_0", "brass_1", "brass_2", "brass_3")) -> Canvas:
    """Horizontal pipe 6 px thick (top lit)."""
    c = Canvas(length, 6)
    rows = [ramp[0], ramp[3], ramp[2], ramp[2], ramp[1], ramp[0]]
    for y, name in enumerate(rows):
        c.hline(0, length - 1, y, name)
    for x in range(0, length, 12):  # flanges
        c.vline(x, 0, 5, ramp[0])
        c.vline(x + 1, 0, 5, ramp[2])
        c.set(x + 1, 0, ramp[3])
    return c


def pipe_v(length: int, ramp=("brass_0", "brass_1", "brass_2", "brass_3")) -> Canvas:
    c = Canvas(6, length)
    cols = [ramp[0], ramp[3], ramp[2], ramp[2], ramp[1], ramp[0]]
    for x, name in enumerate(cols):
        c.vline(x, 0, length - 1, name)
    for y in range(3, length, 12):
        c.hline(0, 5, y, ramp[0])
        c.hline(0, 5, y + 1, ramp[2])
        c.set(1, y + 1, ramp[3])
    return c


def valve_wheel() -> Canvas:
    return from_ascii("""
..eee..
.eh.ge.
ehgggfe
e.gfg.e
egfffee
.ee.ee.
..eee..
""")


def chimney() -> Canvas:
    """10x34 iron chimney with brass bands; anchor bottom-centre."""
    c = Canvas(10, 34)
    for y in range(4, 34):
        c.set(1, y, "iron_3")
        c.set(2, y, "iron_2")
        c.hline(3, 6, y, "iron_1")
        c.set(7, y, "iron_0")
        c.set(8, y, "soot_2")
    for y in (10, 20, 29):
        c.hline(1, 8, y, "brass_1")
        c.hline(1, 3, y, "brass_3")
        c.hline(4, 6, y, "brass_2")
        c.hline(1, 8, y + 1, "brass_0")
    # lip, sooty mouth
    c.hline(0, 9, 3, "iron_2")
    c.hline(0, 9, 4, "iron_0")
    c.set(0, 3, "iron_3")
    c.hline(1, 8, 2, "soot_0")
    c.hline(2, 7, 1, "soot_1")
    c.outline("soot_0")
    return c


# ------------------------------------------------------------------ wall pieces

def wall_section() -> Canvas:
    """Tileable (vertically) wall strip 52x32: walkway, merlons, outer face. x=0 is WALK_X0."""
    w = L.FACE_X1 - L.WALK_X0 + 1
    c = Canvas(w, 32)
    wx1 = L.WALK_X1 - L.WALK_X0
    mx0, mx1 = L.MERLON_X0 - L.WALK_X0, L.MERLON_X1 - L.WALK_X0
    fx0 = L.FACE_X0 - L.WALK_X0
    # walkway: iron deck plates 16 px tall, seams, rivets
    for y in range(32):
        for x in range(0, wx1 + 1):
            c.set(x, y, "iron_1")
    for y in (0, 16):
        c.hline(0, wx1, y, "iron_0")
        c.hline(0, wx1, y + 1, "iron_2")
    c.vline(15, 2, 15, "iron_0")
    c.vline(16, 2, 15, "iron_2")
    c.vline(9, 18, 31, "iron_0")
    c.vline(10, 18, 31, "iron_2")
    c.vline(23, 18, 31, "iron_0")
    c.vline(24, 18, 31, "iron_2")
    for (x, y) in [(2, 3), (13, 3), (18, 3), (29, 3), (2, 14), (13, 14), (18, 14), (29, 14),
                   (3, 19), (7, 19), (12, 19), (21, 19), (26, 19), (3, 30), (7, 30), (12, 30), (21, 30), (26, 30)]:
        c.set(x, y, "iron_3")
        c.set(x + 1, y + 1, "iron_0")
    # inner parapet (lit, faces the courtyard/left)
    c.vline(0, 0, 31, "iron_3")
    c.vline(1, 0, 31, "iron_2")
    # outer face (in shadow): vertical riveted plates
    for y in range(32):
        for x in range(fx0, w):
            c.set(x, y, "soot_3" if x < w - 1 else "soot_2")
        c.set(fx0, y, "soot_2")
    for y in (6, 22):
        c.hline(fx0 + 1, w - 2, y, "soot_2")
        c.hline(fx0 + 1, w - 2, y + 1, "iron_0")
    for y in (2, 10, 18, 26):
        c.set(fx0 + 3, y, "iron_0")
        c.set(fx0 + 8, y + 2, "iron_0")
    # merlons: raised blocks, top lit, south face darker; gaps show the walkway
    for x in range(mx0, mx1 + 1):
        for y in range(32):
            c.set(x, y, "iron_0")  # low parapet between merlons
    for y0 in (0, 16):
        # top surface 8 wide x 7 tall
        for y in range(y0 + 1, y0 + 8):
            for x in range(mx0, mx1 + 1):
                c.set(x, y, "iron_2")
        c.hline(mx0, mx1, y0 + 1, "iron_3")
        c.vline(mx0, y0 + 1, y0 + 7, "iron_3")
        # brass cap rim
        c.set(mx0 + 1, y0 + 2, "brass_3")
        c.hline(mx0 + 2, mx1 - 1, y0 + 2, "brass_2")
        c.vline(mx1, y0 + 2, y0 + 7, "iron_1")
        # south face
        c.hline(mx0, mx1, y0 + 8, "iron_1")
        c.hline(mx0, mx1, y0 + 9, "iron_1")
        c.hline(mx0, mx1, y0 + 10, "iron_0")
        # shadow cast onto the walkway to the lower-left is not needed (light from the left):
        # shadow falls right, onto the face
        c.hline(mx0 + 2, mx1, y0 + 11, "soot_2")
    return c


def gatehouse() -> Canvas:
    """Gate tower over the wall at the road's end: 60x64, includes the raised drawbridge."""
    c = Canvas(60, 70)
    # body: square tower; top roof platform; south face
    x0, x1 = 2, 48           # tower spans walkway+merlons
    top0, top1 = 6, 40       # roof platform (seen from above)
    # south face
    for y in range(top1 + 1, 62):
        for x in range(x0, x1 + 1):
            c.set(x, y, "iron_1")
        c.set(x0, y, "iron_2")
        c.set(x1, y, "iron_0")
    for y in (46, 54):
        c.hline(x0 + 1, x1 - 1, y, "iron_0")
        c.hline(x0 + 1, x1 - 1, y + 1, "iron_2")
    for x in range(x0 + 4, x1, 7):
        for y in (43, 51, 59):
            c.set(x, y, "iron_3")
    # window with warm light
    c.rect(20, 48, 29, 58, "soot_0")
    c.rect(21, 49, 28, 58, "ember_0")
    c.rect(22, 50, 27, 58, "ember_1")
    c.rect(24, 51, 25, 58, "ember_2")
    c.hline(20, 29, 47, "brass_1")
    c.vline(24, 49, 58, "soot_1")
    c.hline(21, 28, 53, "soot_1")
    # roof platform: wooden deck planks with a brass rim (warm, the King's tea terrace)
    for y in range(top0, top1 + 1):
        for x in range(x0, x1 + 1):
            c.set(x, y, "copper_1" if (y - top0) % 4 else "copper_0")
            if (y - top0) % 4 == 1 and (x + (y // 4) * 5) % 13 == 0:
                c.set(x, y, "copper_0")
    for y in range(top0 + 2, top1, 4):
        c.hline(x0 + 2, x1 - 2, y, "copper_2")
    c.hline(x0, x1, top0, "brass_3")
    c.vline(x0, top0, top1, "brass_3")
    c.hline(x0, x1, top1, "brass_1")
    c.vline(x1, top0, top1, "brass_1")
    c.hline(x0 + 1, x1 - 1, top0 + 1, "brass_2")
    c.vline(x0 + 1, top0 + 1, top1 - 1, "brass_2")
    # royal banners on the south face, flanking the window
    for bx in (8, 36):
        c.rect(bx, 42, bx + 5, 56, "ember_0")
        c.rect(bx + 1, 42, bx + 4, 55, "ember_1")
        c.vline(bx + 1, 42, 55, "ember_2")
        c.set(bx + 2, 47, "brass_3")
        c.set(bx + 3, 47, "brass_2")
        c.set(bx + 2, 48, "brass_2")
        c.set(bx + 3, 48, "brass_1")
        c.set(bx, 57, "ember_0")
        c.set(bx + 2, 57, "ember_0")
        c.set(bx + 4, 57, "ember_0")
        c.hline(bx - 1, bx + 6, 41, "brass_2")
    # corner turrets (small merlons)
    for (tx, ty) in [(x0, top0 - 4), (x1 - 7, top0 - 4), (x0, top1 - 7), (x1 - 7, top1 - 7)]:
        c.rect(tx, ty, tx + 7, ty + 6, "iron_3")
        c.rect(tx + 1, ty + 1, tx + 7, ty + 6, "iron_2")
        c.hline(tx, tx + 7, ty + 7, "iron_1")
        c.hline(tx, tx + 7, ty + 8, "iron_0")
        c.set(tx + 1, ty + 1, "brass_3")
        c.hline(tx + 2, tx + 6, ty + 1, "brass_2")
    # outer face of the gate tower (shadow) with the raised drawbridge
    for y in range(top0, 62):
        for x in range(x1 + 1, 59):
            c.set(x, y, "soot_3")
    c.vline(x1 + 1, top0, 61, "soot_2")
    # drawbridge (raised): wooden planks, iron bands, seen edge-on
    for y in range(18, 56):
        for x in range(x1 + 3, 58):
            c.set(x, y, "copper_0" if (y // 3) % 2 else "brass_0")
        c.set(x1 + 3, y, "copper_1")
    for y in (22, 36, 50):
        c.hline(x1 + 3, 57, y, "iron_1")
        c.hline(x1 + 3, 57, y + 1, "iron_0")
    # chains to the roof
    for i in range(10):
        c.set(x1 + 4 + (i % 2), 8 + i, "iron_2" if i % 2 else "iron_0")
    c.outline("soot_0")
    return c


def bastion(roof: str = "verdigris") -> Canvas:
    """Round corner tower with a conical patina roof, 44x58 (anchor bottom-centre)."""
    c = Canvas(44, 58)
    cx = 21.5
    # cylinder body (south face visible)
    for y in range(30, 56):
        for x in range(3, 41):
            t = (x - 3) / 37.0
            name = "iron_3" if t < 0.12 else "iron_2" if t < 0.4 else "iron_1" if t < 0.75 else "iron_0"
            c.set(x, y, name)
    # bottom ellipse edge
    for x in range(3, 41):
        dy = int(3 * math.sqrt(max(0, 1 - ((x - cx) / 19.0) ** 2)))
        for y in range(56, 56 + dy):
            c.set(x, y, "soot_3")
    for y in (38, 47):
        for x in range(3, 41):
            c.set(x, y + int(2 * math.sqrt(max(0, 1 - ((x - cx) / 19.0) ** 2))), "brass_1")
    # arrow slit
    c.rect(20, 40, 22, 46, "soot_0")
    c.set(20, 40, "soot_1")
    # cone roof
    rr = {"verdigris": ("verdigris_0", "verdigris_1", "verdigris_2"), "copper": ("copper_1", "copper_2", "copper_3")}[roof]
    for y in range(2, 34):
        half = (y - 2) / 32 * 21
        for x in range(int(cx - half), int(cx + half) + 1):
            t = (x - (cx - half)) / max(1, 2 * half)
            name = rr[2] if t < 0.3 else rr[1] if t < 0.7 else rr[0]
            if (y + (x // 4)) % 6 == 0 and 0.15 < t < 0.85:
                name = rr[0] if name != rr[0] else "soot_3"
            c.set(x, y, name)
    # eave + finial
    for x in range(0, 44):
        if abs(x - cx) <= 21.5:
            c.set(x, 34, "brass_2" if x < cx else "brass_1")
            c.set(x, 35, "brass_0")
    c.vline(21, 0, 2, "brass_3")
    c.set(22, 1, "brass_1")
    c.outline("soot_0")
    return c



# ------------------------------------------------------------------ field landmarks

def value_noise(w: int, h: int, cell: int, seed: int) -> list:
    """Smooth 2D value noise in [0,1], bilinear between random lattice points."""
    r = rng(seed)
    gw, gh = w // cell + 2, h // cell + 2
    grid = [[r.random() for _ in range(gw)] for _ in range(gh)]
    out = [[0.0] * w for _ in range(h)]
    for y in range(h):
        gy, fy = divmod(y / cell, 1)
        gy = int(gy)
        fy = fy * fy * (3 - 2 * fy)
        for x in range(w):
            gx, fx = divmod(x / cell, 1)
            gx = int(gx)
            fx = fx * fx * (3 - 2 * fx)
            a = grid[gy][gx] * (1 - fx) + grid[gy][gx + 1] * fx
            b = grid[gy + 1][gx] * (1 - fx) + grid[gy + 1][gx + 1] * fx
            out[y][x] = a * (1 - fy) + b * fy
    return out


def boulder(w: int, h: int, seed: int) -> Canvas:
    """Faceted rock lit from the top-left, with a cast shadow to the right."""
    c = Canvas(w + 4, h + 3)
    r = rng(seed)
    cx, cy = w / 2, h / 2 + 1
    pts = []
    for i in range(9):
        a = i / 9 * math.tau
        k = r.uniform(0.75, 1.0)
        pts.append((cx + math.cos(a) * w / 2 * k, cy + math.sin(a) * h / 2 * k))
    def inside(x, y):
        # point in polygon
        n, ok = len(pts), False
        j = n - 1
        for i in range(n):
            xi, yi = pts[i]
            xj, yj = pts[j]
            if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-9) + xi:
                ok = not ok
            j = i
        return ok
    # shadow (offset right/down)
    for y in range(c.h):
        for x in range(c.w):
            if inside(x - 2, y - 1) and not inside(x, y):
                c.set(x, y, "dust_0")
    for y in range(c.h):
        for x in range(c.w):
            if inside(x + 0.5, y + 0.5):
                lit = -(x - cx) / w - (y - cy) / h * 1.3
                name = "parchment_0" if lit > 0.45 else "dust_2" if lit > 0.0 else "dust_1" if lit > -0.45 else "soot_3"
                c.set(x, y, name)
    # a facet crack
    c.line(int(cx), int(cy - h / 4), int(cx + w / 5), int(cy + h / 4), "soot_3")
    c.outline("soot_1")
    return c


def crater(rx: float, ry: float) -> Canvas:
    """Shallow blast crater: dark bowl, lit far (right/bottom) inner wall, rim."""
    w, h = int(rx * 2 + 4), int(ry * 2 + 4)
    c = Canvas(w, h)
    cx, cy = w / 2, h / 2
    for y in range(h):
        for x in range(w):
            d = ((x - cx) / (rx + 1.5)) ** 2 + ((y - cy) / (ry + 1.2)) ** 2
            if d <= 1:
                c.set(x, y, "dust_2" if (x - cx) + (y - cy) * 1.5 < 0 else "dust_1")
            d2 = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
            if d2 <= 1:
                inner = (x - cx) / rx + (y - cy) / ry
                c.set(x, y, "dust_0" if inner < 0.5 else "dust_1")
            if ((x - cx) / (rx * 0.5)) ** 2 + ((y - cy) / (ry * 0.5)) ** 2 <= 1:
                c.set(x, y, "soot_3")
    return c


def wreck_boiler() -> Canvas:
    """Half-sunken rusty boiler tank lying on its side, 34x16."""
    c = Canvas(36, 18)
    for x in range(2, 32):
        for y in range(2, 14):
            t = (y - 2) / 11
            name = "copper_3" if t < 0.15 else "copper_2" if t < 0.4 else "copper_1" if t < 0.75 else "copper_0"
            c.set(x, y, name)
    # end cap (left, lit)
    c.ellipse(3, 7.5, 2.5, 6, "copper_2")
    c.ellipse(3, 7.5, 1.2, 4, "copper_3")
    # bands & rivets
    for x in (10, 20, 28):
        c.vline(x, 2, 13, "copper_0")
        for y in range(3, 13, 3):
            c.set(x + 1, y, "copper_3")
    # rust holes, verdigris streak
    c.rect(14, 6, 16, 8, "soot_1")
    c.set(14, 6, "soot_0")
    c.set(17, 9, "soot_1")
    c.vline(24, 4, 9, "verdigris_1")
    c.set(25, 5, "verdigris_2")
    # sunken into the ground: ground lip over the lower part
    for x in range(0, 36):
        c.set(x, 14, "dust_0")
        c.set(x, 15, "dust_1")
    c.hline(33, 35, 12, "dust_0")
    c.hline(32, 35, 13, "dust_0")
    c.outline("soot_1")
    return c


def wreck_wheel() -> Canvas:
    """Big locomotive wheel half-buried, 22x14."""
    c = Canvas(24, 15)
    cx, cy = 11.5, 12
    for y in range(c.h):
        for x in range(c.w):
            d = math.hypot(x - cx, y - cy)
            if d <= 10.5 and y <= 12:
                ang = math.atan2(y - cy, x - cx)
                if d > 8.5:
                    c.set(x, y, "iron_2" if (x - cx) < 0 else "iron_0")
                    if d > 9.5 and x - cx < -2:
                        c.set(x, y, "iron_3")
                elif d < 2.2:
                    c.set(x, y, "copper_2")
                elif abs(math.sin(ang * 3)) < 0.18:
                    c.set(x, y, "iron_1")
    c.hline(0, 23, 13, "dust_0")
    c.hline(0, 23, 14, "dust_1")
    c.outline("soot_1")
    return c


def dead_tree() -> Canvas:
    """Bare dead tree, 20x26 (anchor bottom-centre)."""
    c = from_ascii("""
....0.......0.......
.....0..0..0........
..0...0.0.0...0.....
...0..2.0.2..0......
....0.2.22..0..0....
.....022.2.0..0.....
..0...222.20.0......
...00..2222..0......
.....0.322..........
......0322..........
.......32...........
.......32...........
.......322..........
.......332..........
.......332..........
......3322..........
......33322.........
.....33.3322........
.....D..DD.DD.......
....DDDDDDDDDDD.....
""")
    return c


def signpost() -> Canvas:
    return from_ascii("""
..nnnnnnnn..
.nopppppon0.
.n0o0oo0o00.
..n0000000..
....no0.....
....no0.....
....no0.....
....no0.....
...DDDDD....
""")

# ------------------------------------------------------------------ edge vegetation (fields: sprites_field.py)

BUSH_TONES = {
    "olive": ("soot_3", "brass_0", "brass_1", "parchment_0"),
    "rust": ("soot_3", "copper_0", "copper_1", "copper_2"),
    "sage": ("soot_3", "verdigris_0", "verdigris_1", "verdigris_2"),
}


def bush(seed: int, tone: str = None) -> Canvas:
    """Dry shrub clump lit top-left for the field's framing edges. Size, lobe count and tone vary with
    the seed (olive / rusty / sage), so a row of them never reads as a stamp."""
    r = rng(seed)
    tone = tone or r.choice(("olive", "olive", "rust", "sage"))
    dark, d1, d2, tip = BUSH_TONES[tone]
    w = r.randint(6, 17)
    hh = r.randint(7, 12)
    c = Canvas(w + 3, hh + 1)
    lobes = r.randint(2, 5)
    for i in range(lobes):
        cx = 2 + (w - 3) * (i + 0.5) / lobes + r.uniform(-1.2, 1.2)
        rad = r.uniform(2.0, min(4.2, hh / 2.2))
        cy = hh - rad - r.uniform(0, 1.5)
        for y in range(hh + 1):
            for x in range(w + 3):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                if dx * dx + dy * dy <= rad * rad:
                    lit = -(dx * 0.6 + dy * 0.8) / rad
                    c.set(x, y, d2 if lit > 0.35 else d1 if lit > -0.5 else dark)
    # break the rounded silhouette: notches bitten out of the lower edge, twigs poking out of the top
    for x in range(w + 3):
        col = [y for y in range(hh + 1) if c.opaque(x, y)]
        if not col:
            continue
        top, bot = col[0], col[-1]
        if r.random() < 0.3 and bot - top > 2:
            c.set(x, bot, None)
        if r.random() < 0.35:
            ln = r.randint(1, 3)
            lean = r.choice((-1, 0, 0, 1))
            for k in range(1, ln + 1):
                xx, yy = x + (lean if k > 1 else 0), top - k
                if 0 <= yy:
                    c.set(xx, yy, d1 if k < ln else tip)
    for k in range(r.randint(2, 5)):   # lit leaf tips inside the crown
        x = r.randrange(1, w + 1)
        for y in range(hh):
            if c.opaque(x, y):
                c.set(x, y + 1, tip)
                break
    c.outline("soot_1")
    return c


def fence_remnant(seed: int) -> Canvas:
    """Three or four leaning fence posts with a sagging wire - a farm long gone."""
    r = rng(seed)
    n = r.randint(3, 4)
    c = Canvas(n * 7 + 2, 12)
    tops = []
    for i in range(n):
        x = 1 + i * 7 + r.randint(0, 1)
        h = r.randint(6, 9)
        lean = r.choice((-1, 0, 1))
        for k in range(h):
            xx = x + (lean if k > h // 2 else 0)
            c.set(xx, 11 - k, "copper_2" if k < h - 1 else "copper_3")
            c.set(xx + 1, 11 - k, "copper_0")
        tops.append((x + lean, 11 - h + 2))
    for (a, b) in zip(tops, tops[1:]):
        mx = (a[0] + b[0]) // 2
        c.line(a[0] + 1, a[1], mx, max(a[1], b[1]) + 2, "iron_1")
        c.line(mx, max(a[1], b[1]) + 2, b[0], b[1], "iron_1")
    c.outline("soot_1")
    return c


def stone_scatter(seed: int) -> Canvas:
    """A loose group of 4-7 small stones of different sizes (for empty flats)."""
    r = rng(seed)
    c = Canvas(22, 10)
    for _ in range(r.randint(4, 7)):
        x, y = r.randint(2, 18), r.randint(3, 8)
        rad = r.choice((0.8, 1.2, 1.6, 2.2))
        c.ellipse(x, y, rad + 0.4, rad * 0.75, "dust_2")
        c.set(x - 1, y - 1, "parchment_0")
        c.set(x + 1, y + 1, "dust_0")
    c.outline("soot_3")
    return c

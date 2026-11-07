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
        # depth at the foot of the stone bank on the east side
        for y in range(TH):
            c.hline(TW - 2, TW - 1, y, "teal_0")
            if (y + f) % 3 == 0:
                c.set(TW - 3, y, "teal_0")
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
                c.hline(bx - 1, bx + 1, by - 1, "steam_3")
                c.set(bx - 2, by, "steam_2")
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


def steam_sheet_frames(n: int = 6, height: int = 64) -> list:
    """24 x height steam sheet (anchor = nozzle mouth, bottom-left). Loops seamlessly.

    A semi-opaque sheet that leaves the nozzle as a jet, rises and leans east on the moat's heat draft:
    lit left edge, shaded right edge, ragged edges and streaks scroll upward, torn wisps at the top.
    Sheets every 18 px overlap into a feathered curtain where every sheet stays readable.
    """
    W = 24
    period = 72.0
    frames = []
    for f in range(n):
        c = Canvas(W, height)
        ph = f * period / n
        for y in range(height):
            k = (height - 1 - y) / (height - 1)          # 0 at the nozzle, 1 at the top
            v = y + ph                                   # texture coordinate scrolls upward
            wob = math.sin(math.tau * v / 24.0) + 0.6 * math.sin(math.tau * v / 18.0 + 1.3)
            wob2 = math.sin(math.tau * v / 36.0 + 2.1) + 0.5 * math.sin(math.tau * v / 12.0 + 0.4)
            half = 2.2 + k * 2.8
            cx = 3.0 + (k ** 0.8) * 14.0
            x0 = int(round(cx - half + wob * 0.8))
            x1 = int(round(cx + half + wob2 * 0.9))
            if k < 0.07:   # the jet leaving the nozzle
                x0, x1 = 0, 6
            if k > 0.62 and (math.sin(math.tau * v / 9.0) + math.sin(math.tau * v / 24.0 + 0.7)) > 0.4:
                continue   # torn wisps near the top
            alpha = int(215 - 150 * k)
            for x in range(max(0, x0), min(W, x1 + 1)):
                if x <= x0:
                    name = "steam_3"
                elif x >= x1 - 1:
                    name = "steam_1"
                else:
                    name = "steam_3" if (x - x0) == 1 and k < 0.6 else "steam_2"
                c.set(x, y, name, alpha)
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

# ------------------------------------------------------------------ battlefield background

def _road_mask(x: int, y: int, r) -> float:
    """Signed distance-ish to the road edge (negative inside)."""
    cy = L.road_center(x)
    return abs(y - cy) - L.ROAD_HALF


def bush(seed: int) -> Canvas:
    """Dry shrub clump (dark olive, lit top-left) for the field's framing edges."""
    r = rng(seed)
    w = r.randint(10, 15)
    c = Canvas(w + 2, 11)
    for i in range(r.randint(3, 4)):
        cx = 2 + (w - 4) * i / 3 + r.uniform(-1, 1)
        cy = r.uniform(4.5, 6.5)
        rad = r.uniform(2.4, 3.6)
        for y in range(11):
            for x in range(w + 2):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                if dx * dx + dy * dy <= rad * rad:
                    lit = -(dx * 0.6 + dy * 0.8) / rad
                    c.set(x, y, "brass_1" if lit > 0.35 else "brass_0" if lit > -0.5 else "soot_3")
    for k in range(4):  # a few dry twigs and lit leaf tips
        x = r.randrange(1, w)
        c.set(x, 2, "parchment_0")
    c.outline("soot_1")
    return c


def _blob(c: Canvas, ellipses: list, name: str, only: tuple = None) -> None:
    """Fill a smooth union of ellipses [(cx, cy, rx, ry)] (no noise, clean pixel edges)."""
    xs0 = int(min(e[0] - e[2] for e in ellipses)) - 1
    xs1 = int(max(e[0] + e[2] for e in ellipses)) + 1
    ys0 = int(min(e[1] - e[3] for e in ellipses)) - 1
    ys1 = int(max(e[1] + e[3] for e in ellipses)) + 1
    for y in range(max(0, ys0), min(c.h, ys1 + 1)):
        for x in range(max(L.FIELD_X0, xs0), min(c.w, xs1 + 1)):
            for (cx, cy, rx, ry) in ellipses:
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                    if only is None or c.get(x, y)[:3] in only:
                        c.set(x, y, name)
                    break


def battlefield_bg(ground_tiles: list, road_tiles: list) -> Canvas:
    W, H = L.W, L.H
    c = Canvas(W, H, "dust_1")
    r = rng(7)
    D1 = C("dust_1")[:3]
    # base ground tiles (subtle texture only)
    for ty in range(0, H, 16):
        for tx in range(L.FIELD_X0 - 16, W, 16):
            t = ground_tiles[(tx * 7 + ty * 13 + (tx // 16) * (ty // 16)) % len(ground_tiles)]
            c.blit(t, tx, ty)
    # composition: 5 large pale dry flats with smooth edges
    for blob in (
        [(205, 120, 34, 16), (236, 128, 26, 12)],
        [(318, 236, 40, 15), (352, 228, 22, 11)],
        [(410, 150, 30, 13)],
        [(176, 238, 20, 10), (190, 246, 16, 8)],
        [(300, 70, 28, 10), (330, 76, 18, 8)],
    ):
        _blob(c, blob, "dust_2", only=(D1,))
    # framing ridges: dark higher ground along the top and bottom edges leads the eye to the road
    for x in range(L.FIELD_X0, W):
        t = (x - L.FIELD_X0) / (W - L.FIELD_X0)
        top = int(20 + 7 * math.sin(t * 7.1 + 0.5) + 4 * math.sin(t * 17.0))
        bot = int(H - 22 - 6 * math.sin(t * 6.3 + 1.7) - 3 * math.sin(t * 15.0 + 0.2))
        for y in range(0, top):
            c.set(x, y, "dust_0" if (x * 3 + y * 5) % 23 else "soot_3")
        c.set(x, top, "soot_3")              # the ridge's south face: a short dark drop
        c.set(x, top + 1, "soot_3")
        c.set(x, top + 2, "dust_0")
        c.set(x, top - 1, "dust_1")          # lit rim of the ridge top
        for y in range(bot, H):
            c.set(x, y, "dust_0" if (x * 5 + y * 3) % 29 else "soot_3")
        c.set(x, bot, "dust_1")              # lit lip of the low bank in the foreground
        c.set(x, bot + 1, "dust_0")
    # road (tile texture inside a wobbly mask, darker shoulder)
    edge_noise = [r.choice((0, 0, 1, 1, 2)) for _ in range(W)]
    for x in range(L.FIELD_X0 - 2, W):
        cy = L.road_center(x)
        for y in range(H):
            d = abs(y - cy) - L.ROAD_HALF + edge_noise[x] * 0.7
            if d < 0:
                tile = road_tiles[(x // 16) % len(road_tiles)]
                yy = int(y - cy + 64) % 16
                c.px[x, y] = tile.px[x % 16, yy]
            elif d < 2:
                c.set(x, y, "dust_0")
    stamps = []   # (y_sort, x, y, canvas)
    # bushes and boulders on both ridges
    for i, x in enumerate(range(L.FIELD_X0 + 6, W - 8, 19)):
        x += r.randint(-4, 4)
        t = (x - L.FIELD_X0) / (W - L.FIELD_X0)
        top = int(20 + 7 * math.sin(t * 7.1 + 0.5) + 4 * math.sin(t * 17.0))
        bot = int(H - 22 - 6 * math.sin(t * 6.3 + 1.7) - 3 * math.sin(t * 15.0 + 0.2))
        b = bush(i) if i % 3 else boulder(r.randint(9, 13), r.randint(7, 9), i)
        stamps.append((top, x, top - b.h + r.randint(2, 5), b))
        b2 = bush(i + 50) if i % 4 else boulder(r.randint(10, 14), r.randint(7, 10), i + 9)
        stamps.append((bot + 9, x + r.randint(-5, 5), bot - 3 + r.randint(0, 6), b2))
    # roadside tussocks and stones along both edges
    for i, x in enumerate(range(L.FIELD_X0 + 14, W - 4, 13)):
        x += r.randint(-3, 3)
        for side in (-1, 1):
            if r.random() < 0.35:
                continue
            y = int(L.road_center(x) + side * (L.ROAD_HALF + r.randint(1, 4)))
            d = decal_grass(i * 2 + (side > 0)) if r.random() < 0.65 else decal_rocks(i + 3 * side)
            stamps.append((y, x, y - d.h + 2, d))
    # clusters: A boiler wreck + scrap + grass, B wheel + rocks, C dead tree + boulder + crater, D crater + rocks
    clusters = [
        [(232, 98, wreck_boiler()), (222, 110, decal_scrap(1)), (266, 108, decal_scrap(2)),
         (216, 104, decal_grass(3)), (270, 100, decal_grass(4)), (250, 112, decal_rocks(5))],
        [(372, 280, wreck_wheel()), (395, 284, boulder(16, 11, 5)), (360, 292, boulder(9, 7, 7)),
         (390, 276, decal_grass(6)), (352, 284, decal_grass(7))],
        [(186, 262, dead_tree()), (204, 276, boulder(14, 10, 11)), (166, 278, crater(7, 4)),
         (178, 286, decal_grass(8)), (214, 268, decal_grass(9))],
        [(398, 92, crater(9, 5)), (420, 102, boulder(12, 8, 13)), (386, 104, decal_rocks(10)),
         (412, 88, decal_scrap(4))],
    ]
    for cl in clusters:
        for (x, y, d) in cl:
            stamps.append((y + d.h, x, y, d))
    stamps.sort(key=lambda s_: s_[0])
    for (_ys, x, y, d) in stamps:
        if abs(y + d.h - L.road_center(x)) < L.ROAD_HALF - 3 and d.w > 9:
            continue   # never put big props on the road
        c.paste_over(d, x, y)
    # outer bank: a stone retaining edge. Its west face (toward the moat) is lit; the coping casts
    # a short shadow east onto the field; the water at its foot is darker (in the moat tile).
    for y in range(H):
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
        c.set(L.BANK_X0 + 8, y, "soot_3")                   # cast shadow on the field
        c.set(L.BANK_X0 + 9, y, "dust_0")
        if y % 11 == 3:
            c.set(L.BANK_X0, y, "steam_2")                  # foam flecks at the waterline
    # moat bed (covered at runtime by the animated water tiles)
    water = moat_frames()[0]
    for y in range(0, H, water.h):
        c.blit(water, L.MOAT_X0, y)
    # broken bridge stub on the bank, at the road's end
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
    for x in (L.BANK_X0 + 3, x_end - 3):  # posts
        c.rect(x, gy - 13, x + 2, gy - 9, "copper_1")
        c.set(x, gy - 13, "copper_3")
        c.rect(x, gy + 10, x + 2, gy + 14, "copper_1")
        c.set(x, gy + 10, "copper_3")
    # courtyard: big flagstones, low contrast (one ramp step) so it does not compete with the towers
    for y in range(H):
        for x in range(0, L.WALK_X0):
            c.set(x, y, "soot_2")
    for y in range(0, H, 8):
        off = 5 if (y // 8) % 2 else 0
        c.hline(0, L.WALK_X0 - 1, y, "soot_1")
        for x in range(off, L.WALK_X0, 10):
            c.vline(x, y + 1, y + 7, "soot_1")
    # wall strip, tiled
    ws = wall_section()
    for y in range(0, H, 32):
        c.blit(ws, L.WALK_X0, y)
    # brass steam main along the moat's west edge (also drawn at runtime over the water)
    for i, vy in enumerate(L.STEAM_VENTS_Y):
        if abs(vy - L.GATE_Y) < 30:
            continue
        c.paste_over(steam_pipe(valve=(i % 4 == 1)), L.PIPE_X, vy - 10)
    return c


def courtyard_props(c: Canvas) -> list:
    """Draws static courtyard props into c; returns chimney top positions for smoke [(x, y)]."""
    smoke = []
    # boiler house: big copper boiler in a brick shed
    bx, by = 4, 238
    # shed roof (top view), copper plates
    for y in range(by, by + 30):
        for x in range(bx, bx + 46):
            c.set(x, y, "copper_1" if (x + (y // 4) * 2) % 8 else "copper_0")
    c.hline(bx, bx + 45, by, "copper_3")
    c.vline(bx, by, by + 29, "copper_2")
    for y in range(by + 4, by + 30, 4):
        c.hline(bx + 1, bx + 45, y, "copper_0")
    # shed front (south face) with furnace mouth glowing
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
    # coal pile
    for i, (x, y, rr) in enumerate([(10, 292, 4), (16, 290, 5), (22, 293, 4), (14, 295, 3)]):
        c.disc(x, y, rr, "soot_1")
    for (x, y) in [(9, 289), (15, 287), (21, 290), (17, 292), (12, 293)]:
        c.set(x, y, "iron_0")
        c.set(x + 1, y, "soot_3")
    # chimneys on the shed
    ch = chimney()
    for (x, y) in [(bx + 4, by - 26), (bx + 32, by - 20)]:
        c.paste_over(ch, x, y)
        smoke.append((x + 5, y + 2))
    # workshop (north): iron hall with a big gear on the wall
    wx, wy = 4, 40
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
    # pipes from the boiler to the wall (feed the steam curtain)
    p = pipe_h(L.WALK_X0 - (bx + 46) + 2)
    c.paste_over(p, bx + 46, by + 12)
    p2 = pipe_v(by - 120)
    c.paste_over(p2, 26, 120 + 4)
    c.paste_over(pipe_h(L.WALK_X0 - 26), 26, 118)
    c.paste_over(valve_wheel(), 23, 150)
    return smoke

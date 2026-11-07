"""Small pixel-drawing toolkit on top of PIL, palette-name based.

ASCII sprite legend (single characters, case-sensitive), used by `from_ascii`:
    .  transparent
    0 1 2 3   soot_0..3          a b c d   iron_0..3
    e f g h   brass_0..3         m n o p   copper_0..3
    s t u v   steam_0..3         w x y     teal_0..2
    Q R T     ember_0..2         V W X     verdigris_0..2
    L M N     parchment_0..2     D E F     dust_0..2
"""
import math
import random

from PIL import Image

import palette as pal

LEGEND = {}
for _chars, _ramp in (("0123", "soot"), ("abcd", "iron"), ("efgh", "brass"), ("mnop", "copper"),
                      ("stuv", "steam"), ("wxy", "teal"), ("QRT", "ember"), ("VWX", "verdigris"),
                      ("LMN", "parchment"), ("DEF", "dust")):
    for _i, _c in enumerate(_chars):
        LEGEND[_c] = f"{_ramp}_{_i}"


def C(name: str, alpha: int = 255) -> tuple:
    return pal.rgba(name, alpha)


class Canvas:
    def __init__(self, w: int, h: int, fill: str = None):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w, h), C(fill) if fill else (0, 0, 0, 0))
        self.px = self.img.load()

    # -- basic
    def inside(self, x: int, y: int) -> bool:
        return 0 <= x < self.w and 0 <= y < self.h

    def set(self, x: int, y: int, name: str, alpha: int = 255) -> None:
        x, y = int(x), int(y)
        if self.inside(x, y):
            self.px[x, y] = C(name, alpha) if name else (0, 0, 0, 0)

    def get(self, x: int, y: int) -> tuple:
        return self.px[x, y] if self.inside(x, y) else (0, 0, 0, 0)

    def opaque(self, x: int, y: int) -> bool:
        return self.get(x, y)[3] > 0

    def rect(self, x0: int, y0: int, x1: int, y1: int, name: str, alpha: int = 255) -> None:
        """Filled, inclusive."""
        for y in range(min(y0, y1), max(y0, y1) + 1):
            for x in range(min(x0, x1), max(x0, x1) + 1):
                self.set(x, y, name, alpha)

    def frame(self, x0: int, y0: int, x1: int, y1: int, name: str) -> None:
        self.hline(x0, x1, y0, name)
        self.hline(x0, x1, y1, name)
        self.vline(x0, y0, y1, name)
        self.vline(x1, y0, y1, name)

    def hline(self, x0: int, x1: int, y: int, name: str) -> None:
        for x in range(min(x0, x1), max(x0, x1) + 1):
            self.set(x, y, name)

    def vline(self, x: int, y0: int, y1: int, name: str) -> None:
        for y in range(min(y0, y1), max(y0, y1) + 1):
            self.set(x, y, name)

    def line(self, x0: int, y0: int, x1: int, y1: int, name: str) -> None:
        x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.set(x0, y0, name)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def disc(self, cx: float, cy: float, r: float, name: str, alpha: int = 255) -> None:
        for y in range(int(cy - r) - 1, int(cy + r) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    self.set(x, y, name, alpha)

    def ellipse(self, cx: float, cy: float, rx: float, ry: float, name: str, alpha: int = 255) -> None:
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                    self.set(x, y, name, alpha)

    def shaded_disc(self, cx: float, cy: float, r: float, ramp: list, light=(-0.6, -0.8),
                    outline: str = None) -> None:
        """Sphere/disc shaded from the light direction; ramp dark->light names."""
        lx, ly = light
        n = len(ramp)
        for y in range(int(cy - r) - 1, int(cy + r) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                dx, dy = x - cx, y - cy
                d = math.hypot(dx, dy)
                if d <= r:
                    if outline and d > r - 1.0:
                        self.set(x, y, outline)
                        continue
                    t = 0.5 + 0.5 * ((dx * lx + dy * ly) / max(r, 0.01))
                    t = t * 0.9 + 0.1 * (1 - d / r)
                    self.set(x, y, ramp[max(0, min(n - 1, int(t * n)))])

    def blit(self, other, x: int, y: int) -> None:
        src = other.img if isinstance(other, Canvas) else other
        self.img.alpha_composite(src, (int(x), int(y)))

    def paste_over(self, other, x: int, y: int) -> None:
        """Copy opaque pixels only (no blending)."""
        src = other.img if isinstance(other, Canvas) else other
        sp = src.load()
        for yy in range(src.height):
            for xx in range(src.width):
                if sp[xx, yy][3]:
                    if self.inside(x + xx, y + yy):
                        self.px[x + xx, y + yy] = sp[xx, yy]

    def ascii(self, x: int, y: int, rows, legend: dict = None) -> None:
        lg = dict(LEGEND)
        if legend:
            lg.update(legend)
        if isinstance(rows, str):
            rows = [r for r in rows.strip("\n").split("\n")]
        for yy, row in enumerate(rows):
            for xx, ch in enumerate(row):
                if ch in (".", " "):
                    continue
                self.set(x + xx, y + yy, lg[ch])

    def outline(self, name: str = "soot_0", diagonal: bool = False) -> None:
        """Adds a 1-px outline around all opaque pixels (outside)."""
        src = self.img.copy().load()
        nb = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        if diagonal:
            nb += [(-1, -1), (1, -1), (-1, 1), (1, 1)]
        for y in range(self.h):
            for x in range(self.w):
                if src[x, y][3] == 0:
                    for dx, dy in nb:
                        xx, yy = x + dx, y + dy
                        if 0 <= xx < self.w and 0 <= yy < self.h and src[xx, yy][3] == 255:
                            self.px[x, y] = C(name)
                            break

    def recolor(self, mapping: dict) -> None:
        """mapping: palette name -> palette name."""
        m = {C(a)[:3]: C(b)[:3] for a, b in mapping.items()}
        for y in range(self.h):
            for x in range(self.w):
                r, g, b, a = self.px[x, y]
                if a and (r, g, b) in m:
                    self.px[x, y] = m[(r, g, b)] + (a,)

    def flip_h(self) -> "Canvas":
        c = Canvas(self.w, self.h)
        c.img = self.img.transpose(Image.FLIP_LEFT_RIGHT)
        c.px = c.img.load()
        return c

    def copy(self) -> "Canvas":
        c = Canvas(self.w, self.h)
        c.img = self.img.copy()
        c.px = c.img.load()
        return c

    def shifted(self, dx: int, dy: int) -> "Canvas":
        c = Canvas(self.w, self.h)
        c.img.paste(self.img, (dx, dy))
        c.px = c.img.load()
        return c


def from_ascii(rows: str, legend: dict = None) -> Canvas:
    lines = [r for r in rows.strip("\n").split("\n")]
    w = max(len(r) for r in lines)
    c = Canvas(w, len(lines))
    c.ascii(0, 0, [r.ljust(w, ".") for r in lines], legend)
    return c


def strip(frames: list) -> Image.Image:
    """Horizontal sprite sheet from equally sized frames."""
    w, h = frames[0].w, frames[0].h
    img = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        assert (f.w, f.h) == (w, h)
        img.paste(f.img, (i * w, 0))
    return img


def upscale(img: Image.Image, k: int) -> Image.Image:
    return img.resize((img.width * k, img.height * k), Image.NEAREST)


def rng(seed: int) -> random.Random:
    return random.Random(seed)


# ------------------------------------------------------------------ colour utilities

_RGB2NAME = {pal.rgb(n): n for n in pal.names()}


def name_at(c: Canvas, x: int, y: int):
    p = c.get(x, y)
    return _RGB2NAME.get(p[:3]) if p[3] else None


def step(name: str, k: int) -> str:
    """Move k steps along the colour's ramp (clamped)."""
    ramp, idx = name.rsplit("_", 1)
    n = len(pal.RAMPS[ramp])
    return f"{ramp}_{max(0, min(n - 1, int(idx) + k))}"


def rim_light(c: Canvas, outline: str = "soot_0") -> None:
    """1-px light rim: pixels whose top or left neighbour is outline/empty go one ramp step lighter."""
    src = c.copy()
    for y in range(c.h):
        for x in range(c.w):
            n = name_at(src, x, y)
            if n is None or n == outline or n.startswith("soot") or src.get(x, y)[3] < 255:
                continue
            up, left = name_at(src, x, y - 1), name_at(src, x - 1, y)
            if up in (None, outline) or left in (None, outline):
                c.set(x, y, step(n, 1))


def luminance(name: str) -> float:
    def f(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = pal.rgb(name)
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast(a: str, b: str) -> float:
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def main_color(c: Canvas, ignore=("soot_0",)) -> str:
    """Most frequent opaque palette colour (ignoring the outline)."""
    counts = {}
    for y in range(c.h):
        for x in range(c.w):
            n = name_at(c, x, y)
            if n and n not in ignore and c.get(x, y)[3] == 255:
                counts[n] = counts.get(n, 0) + 1
    return max(counts, key=counts.get)


def cloud(c: Canvas, cx: float, cy: float, r: float, seed: int, alpha: int = 255,
          dark: str = "steam_1", mid: str = "steam_2", light: str = "steam_3", tail: bool = True) -> None:
    """Irregular cloud: a body plus 3-5 lobes (curls show at lobe borders) and a torn trailing tail.

    Every lobe is shaded on its own (highlight cap top-left, crescent shadow bottom-right), lobes higher
    on the screen are drawn last, so their lower rims read as curls over the body.
    """
    rr = random.Random(seed)
    lobes = [(cx, cy, r)]
    for i in range(rr.randint(3, 5)):
        a = math.pi * (1.0 + rr.uniform(-0.15, 1.15))      # mostly the upper half
        d = r * rr.uniform(0.45, 0.75)
        lobes.append((cx + math.cos(a) * d, cy + math.sin(a) * d * 0.8, r * rr.uniform(0.42, 0.66)))
    if tail and r > 2.5:
        tx, ty = cx + r * 0.5, cy + r * 0.7
        for k in range(rr.randint(2, 3)):
            lobes.append((tx + k * r * 0.35 + rr.uniform(-0.6, 0.6), ty + k * r * 0.25, r * (0.32 - k * 0.08)))
    lobes.sort(key=lambda l: -l[1])  # lower lobes first, upper lobes over them
    for (lx, ly, lr) in lobes:
        if lr < 0.6:
            continue
        hx, hy, hr = lx - lr * 0.3, ly - lr * 0.35, lr * 0.6
        sx, sy, sr = lx - lr * 0.2, ly - lr * 0.22, lr * 0.9
        for y in range(int(ly - lr) - 1, int(ly + lr) + 2):
            for x in range(int(lx - lr) - 1, int(lx + lr) + 2):
                if (x + 0.5 - lx) ** 2 + (y + 0.5 - ly) ** 2 <= lr * lr:
                    if (x + 0.5 - hx) ** 2 + (y + 0.5 - hy) ** 2 <= hr * hr:
                        name = light
                    elif (x + 0.5 - sx) ** 2 + (y + 0.5 - sy) ** 2 <= sr * sr:
                        name = mid
                    else:
                        name = dark
                    c.set(x, y, name, alpha)


# ------------------------------------------------------------------ scatter & organic shapes

def poisson(x0: int, y0: int, x1: int, y1: int, r: float, seed: int, k: int = 24) -> list:
    """Blue-noise points (Bridson): no two closer than r. Deterministic; no lattice, no visible grid."""
    rr = random.Random(seed)
    cell = r / math.sqrt(2)
    gw, gh = int((x1 - x0) / cell) + 1, int((y1 - y0) / cell) + 1
    grid = [[None] * gw for _ in range(gh)]
    pts, active = [], []

    def put(p):
        pts.append(p)
        active.append(p)
        grid[int((p[1] - y0) / cell)][int((p[0] - x0) / cell)] = p

    put((rr.uniform(x0, x1), rr.uniform(y0, y1)))
    while active:
        i = rr.randrange(len(active))
        px, py = active[i]
        for _ in range(k):
            a = rr.uniform(0, math.tau)
            d = rr.uniform(r, 2 * r)
            qx, qy = px + math.cos(a) * d, py + math.sin(a) * d
            if not (x0 <= qx < x1 and y0 <= qy < y1):
                continue
            gx, gy = int((qx - x0) / cell), int((qy - y0) / cell)
            ok = True
            for yy in range(max(0, gy - 2), min(gh, gy + 3)):
                for xx in range(max(0, gx - 2), min(gw, gx + 3)):
                    o = grid[yy][xx]
                    if o and (o[0] - qx) ** 2 + (o[1] - qy) ** 2 < r * r:
                        ok = False
                        break
                if not ok:
                    break
            if ok:
                put((qx, qy))
                break
        else:
            active.pop(i)
    return [(int(x), int(y)) for x, y in pts]


def wobble(seed: int, n: int = 3):
    """Smooth periodic 1-D noise f(angle or t) in about [-1, 1]: a few sines with random phases."""
    rr = random.Random(seed)
    waves = [(rr.randint(2, 7), rr.uniform(0, math.tau), rr.uniform(0.4, 1.0)) for _ in range(n)]
    norm = sum(w[2] for w in waves)
    return lambda a: sum(math.sin(a * f + p) * amp for f, p, amp in waves) / norm


def organic(cx: float, cy: float, rx: float, ry: float, seed: int, rough: float = 0.28):
    """Inside-test for an irregular blob: an ellipse whose radius wobbles with the angle."""
    f = wobble(seed, 4)

    def inside(x: float, y: float) -> bool:
        dx, dy = (x - cx) / rx, (y - cy) / ry
        a = math.atan2(dy, dx)
        return dx * dx + dy * dy <= (1.0 + rough * f(a)) ** 2
    return inside


def fill_shape(c: "Canvas", inside, box: tuple, name: str, only=None, alpha: int = 255) -> list:
    """Fill pixels where inside(x+.5, y+.5); returns the filled pixel list. `only`: set of rgb allowed under."""
    x0, y0, x1, y1 = box
    out = []
    for y in range(max(0, int(y0)), min(c.h, int(y1) + 1)):
        for x in range(max(0, int(x0)), min(c.w, int(x1) + 1)):
            if inside(x + 0.5, y + 0.5) and (only is None or c.get(x, y)[:3] in only):
                c.set(x, y, name, alpha)
                out.append((x, y))
    return out

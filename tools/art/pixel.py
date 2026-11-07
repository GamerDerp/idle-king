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

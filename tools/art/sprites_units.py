"""Characters: region-1 enemies, the King. Hand-drawn ASCII pixel maps (legend in pixel.py).

All walkers face LEFT (toward the fortress). Anchor = bottom-centre of the feet.
"""
from pixel import Canvas, from_ascii, rim_light

# ------------------------------------------------------------------ Бродяга (scavenger), 16x20

# Hooded tramp: a pointed hood with the face showing under it, a patched cloak, a big lumpy sack on
# his back (with a pipe sticking out), a walking stick in front. The hood + sack make the silhouette.
SCAV_BODY = """
.....00.........
....0XX0........
...0XXXW0..0000.
..0XXWWWW00LMMN0
..0XW000W0LMMMN0
..0X0pp00LLMNMM0
..0Wp0po0LLMMMM0
.0d0ppp0LLLMMNM0
.0c0Wo0WLLLLMMM0
.0cXXXWWWLLLLML0
.0cXXXXWWWLLLLL0
.0cpXXXWWW0LLL0.
.0c0XXXXWWW000..
.0c0XXXXXWWW0...
.0c0VXXXXWWV0...
..0..0VVVVV0....
"""
SCAV_LEGS = [
    """
.....0bb0b0.....
....0b0..0b0....
...011...0110...
...000....000...
""",
    """
.....0bbb0......
......0bb0......
.....0110.......
.....0000.......
""",
    """
.....0b0bb0.....
....0b0..0b0....
...0110...011...
...0000...000...
""",
    """
.....0bbb0......
......0b0.......
.....0110.......
.....0000.......
""",
]


def scavenger_frames() -> list:
    frames = []
    for i, legs in enumerate(SCAV_LEGS):
        c = Canvas(16, 20)
        bob = 0 if i % 2 == 0 else -1
        c.ascii(0, 16, [r.ljust(16, ".") for r in legs.strip("\n").split("\n")])
        body = from_ascii(SCAV_BODY)
        c.paste_over(body, 0, bob)
        if i % 2:   # the pipe in the sack bobs
            c.set(14, 1 + bob, "iron_2")
        c.outline("soot_0")
        rim_light(c)
        frames.append(c)
    return frames


# ------------------------------------------------------------------ Ржавый пёс (rust hound), 20x13

HOUND_BODY = """
....................
..000...............
.0ph00..............
0pTp0c0.......0.....
0oppoc00000000d0....
.0oopcddddcccdc0....
..00poppppppooc0....
....0opppppooon0....
....0ooooonnnn0.....
.....000000000......
"""
HOUND_LEGS = [
    """
....0b0.....0b0.....
...0b0.......0b0....
...00.........00....
""",
    """
.....0b0...0b0......
.....0b0...0b0......
.....00....00.......
""",
    """
......0b0.0b0.......
......0b0.0b0.......
......00...00.......
""",
    """
.....0b0...0b0......
....0b0.....0b0.....
....00.......00.....
""",
]


def hound_frames() -> list:
    frames = []
    for i, legs in enumerate(HOUND_LEGS):
        c = Canvas(20, 13)
        c.ascii(0, 10, [r.ljust(20, ".").replace("b", "c") for r in legs.strip("\n").split("\n")])
        body = from_ascii(HOUND_BODY)
        c.paste_over(body, 0, 1 if i in (1, 3) else 0)
        # exhaust puff from the tail pipe on alternate frames
        if i % 2 == 0:
            c.set(16, 2, "steam_1")
            c.set(17, 1, "steam_2")
        rim_light(c)
        frames.append(c)
    return frames


# ------------------------------------------------------------------ Старьёвщик с тележкой (junk cart), 30x20

JUNK_MAN = """
.........0000.
........0nnnn0
.......0nnoon0
.......000000.
.......0hygv0.
.......0ppo0..
......0QQQQ0..
......0QRQQQ0.
.....0nnQQQn0.
....00nnnnmn0.
...0p0nnnnmn0.
...0p0nnnmmn0.
....0.0nnnnm0.
......0nnnmn0.
"""
CART = """
..............00000.......
.....000.....0abcb0.......
....0hgf00..0cddc00.......
...0ghgff0f00bccb00.......
00.0fgfff0hg00bba0000.....
0d00ffffe0gfe0000nono0....
0cd000ee0eee0mn0nooon0....
.0c0nnnnnnnnnnnnnnnnnn0...
..00ooooooooooooooooon00..
...0nnnnnnnnnnnnnnnnnm0d0.
....00000000000000000000d0
"""


def wheel(c: Canvas, cx: int, cy: int, phase: int) -> None:
    c.disc(cx, cy, 3.6, "soot_0")
    c.disc(cx, cy, 2.6, "iron_1")
    c.set(cx - 1, cy - 2, "iron_3")
    c.set(cx - 2, cy - 1, "iron_2")
    spokes = [((0, -2), (0, 2)), ((-2, 0), (2, 0)), ((-1, -1), (1, 1)), ((1, -1), (-1, 1))]
    (a, b) = spokes[phase % 2 * 2 + (phase // 2) % 2]
    c.set(cx + a[0], cy + a[1], "iron_0")
    c.set(cx + b[0], cy + b[1], "iron_0")
    c.set(cx, cy, "brass_2")


def junk_cart_frames() -> list:
    legs = [
        ("..0333..", "..03.03.", ".033..03", "0110.0110"),
        ("..0333..", "...033..", "...033..", "..01100."),
        ("..0333..", "..030.3.", ".03..033", "0110.0110"),
        ("..0333..", "...033..", "..0330..", "..01100."),
    ]
    frames = []
    for i in range(4):
        c = Canvas(30, 20)
        cart = from_ascii(CART.translate(str.maketrans("nomefgh", "ghfmnop")))
        c.paste_over(cart, 0, 4)
        wheel(c, 6, 15, i)
        wheel(c, 17, 15, i + 1)
        man = from_ascii(JUNK_MAN.translate(str.maketrans("nomQ", "ppoR")))
        bob = -1 if i % 2 else 0
        c.paste_over(man, 16, 1 + bob)
        for k, row in enumerate(legs[i]):
            c.ascii(22, 15 + k, row.replace("3", "b"))
        rim_light(c)
        frames.append(c)
    return frames


# ------------------------------------------------------------------ Вожак пустошей (wasteland boss), 32x32

BOSS = """
................................
................................
..........0.......0.............
.........0d0.....0d0............
.........0c00000000c0...........
..........0cbbbbbbb0............
.........0dccbbbbbbb0...........
........0dcccbbbbbbba0..........
........0hhgg0cbbbba0...........
........0vyx0g0bbbaa0...........
........0hgg0gg0baa0..000.......
.........0000ccc0a00.0nnn0......
.........0pTpTpp0000.0noon0.....
........00ppppoo0nnnn0nonn0.....
.......0nn00ooo0nonnoo0nnn0.....
......0nnoon000nnoooonn0n0......
.....0nonoonnnnnooonnnnn0.......
....0doonnonnnnnnoonnnmm0.......
...0ddcoonnnmnnnnnnnnmmm0.......
...0dc0oonnnmmmnnnnnnmm0........
...0c00poonnnmmmnnnnmmm0........
....00ppo0nnnmmnnnnmmm0.........
.....0po00nnnnmnnnnmm0..........
......00.0nnnnnmnnnmm0..........
.........0EEEEEDDDDDD0..........
.........0EEDDD0EEDDD0..........
"""
BOSS_LEGS = [
    ("........0EED0...0EDD0..........", ".......0EED0.....0EDD0.........", "......0111110....011110........", "......0000000....000000........"),
    ("........0EEDD0.0EDDD0..........", ".........0EED00EDD0............", "........0111110110............", "........00000000000..........."),
    ("........0EED0...0EDD0..........", ".......0EED0......0EDD0........", "......011110.....0111110.......", "......000000.....0000000.......",),
    ("........0EEDD0.0EDDD0..........", "..........0EEDEED0.............", ".........01110111O............", ".........0000000000............"),
]


def boss_frames() -> list:
    frames = []
    for i in range(4):
        c = Canvas(32, 32)
        body = from_ascii(BOSS.translate(str.maketrans("nomabc", "opnbcd")))
        legs = Canvas(32, 4)
        for k, row in enumerate(BOSS_LEGS[i]):
            legs.ascii(0, k, row.replace("O", "0"))
        c.paste_over(legs, 0, 26)
        c.paste_over(body, 0, 1 if i % 2 else 0)
        # the big wrench, held upright in the front fist
        b = 1 if i % 2 else 0
        c.ascii(0, 3 + b, [
            "0dd0.0d0",
            "0cdd0dc0",
            "0cccccc0",
            ".0cccb0.",
            "..0cb0..",
            "..0cb0..",
            "..0cb0..",
            "..0cb0..",
            "..0cb0..",
            "..0cb0..",
            "..0cb0..",
            "..0cb0..",
            "..0cb0..",
            "..0cb0..",
        ])
        rim_light(c)
        frames.append(c)
    return frames


# ------------------------------------------------------------------ falling into the moat

def fall_frames(walk0: Canvas) -> list:
    """3 frames of sinking into the boiling moat. Anchor = (w//2+3, h+1): the waterline under the feet."""
    w, h = walk0.w + 6, walk0.h + 4
    out = []
    for i, depth in enumerate((3, walk0.h * 45 // 100, walk0.h * 80 // 100)):
        c = Canvas(w, h)
        water = h - 3                       # waterline row
        src = walk0.img
        for y in range(walk0.h):
            ty = 4 + y + depth - 2
            if ty >= water:
                continue
            for x in range(walk0.w):
                p = src.getpixel((x, y))
                if p[3]:
                    c.px[3 + x, ty] = p
        cx = w / 2
        rx = 3 + i * 2 + walk0.w * 0.25
        for x in range(w):
            dx = (x - cx) / rx
            if abs(dx) <= 1.0:
                c.set(x, water, "steam_3" if abs(dx) > 0.55 else "teal_2")
                if abs(dx) > 0.75:
                    c.set(x, water - 1, "steam_2")
        for k, (dx, dy) in enumerate([(-4, -3), (5, -4), (-6, -6), (6, -7)]):
            if k <= i + 1:
                c.set(cx + dx * (1 + i * 0.4), water + dy - i, "steam_3" if k % 2 else "teal_2")
        if i == 2:
            for (bx, by) in [(cx - 3, water - 2), (cx + 2, water - 3), (cx, water - 5)]:
                c.set(bx, by, "steam_2")
        out.append(c)
    return out


# ------------------------------------------------------------------ the King, 30x28 (faces right, toward the field)
# Not a Santa: teal robe with brass trim, a brass gorget collar, brass goggles over the eyes, a grey
# handlebar moustache (no white beard), a small brass crown with ember gems, and his samovar beside him.

KING_HEAD = """
.......h..h..h....
.......hg.hgThg...
......fgRgggggRf..
......eeeeeeeeee..
.....cnhhhnnnhhhn.
....ccnhyxhnhyxxh.
....cdphhhpophhho.
....cdpdddppdddpp.
....cdpp0pppp0pp..
.....cppppppooop..
.....cdddddoodddd.
....dc.ccddddcc.dd
.......ppnnpp.....
"""
KING_BODY = """
.....ehhgggggfe...
....ehhggfffffffe.
...yehgfeeeeeefexy
..xyyeeexxxxxxexxy
..yyxxxxhxxxxwxxx.
.xyxxxxxgxxxxwwxx.
.xyxxxxxhxxxxwwx..
.xyxxxxxgxxxwwwx..
.xyxxxxxhxxxwwwx..
.xxxxxxxgxxwwwww..
.ffggggghgggfffe..
..................
"""
KING_ARM = """
.yxx.
.xxwx
..xwp
...pp
"""
KING_FEET = """
...01........10...
..011........110..
"""
SAMOVAR = """
.....00.....
....0po0....
...0opoon0..
...0nooonn0.
....0eeee0..
...0hhggf0..
..0hhgggff0.
.0ehNgggffe0
0e0NNgggfe0e0
.0.hNgggfe0.0
..0hhgggfe000
..0hggTRfe0n0
...0hgffe0.0.
....0eee0...
....0hgf0...
...0hggfe0..
..0eeeeeee0.
...0.....0..
"""
CUP = ["vvvu", "uvu.", ".u.."]


def _king_canvas(head_dy: int = 0, body_dy: int = 0, cup=(25, 15), sip: bool = False, steam: int = -1,
                 samovar_steam: int = 0) -> Canvas:
    c = Canvas(30, 28)
    head = from_ascii(KING_HEAD)
    body = from_ascii(KING_BODY)
    sam = from_ascii(SAMOVAR)
    c.paste_over(sam, 0, 9)
    for (dx, dy) in [((samovar_steam % 2), 0), (1 - samovar_steam % 2, -2), (samovar_steam % 2 + 1, -4)][:2 + samovar_steam % 2]:
        c.set(5 + dx, 8 + dy, "steam_2" if dy else "steam_3")
    c.ascii(10, 25, KING_FEET.strip("\n").split("\n"))
    c.paste_over(body, 10, 13 + body_dy)
    c.paste_over(head, 10, 1 + head_dy + body_dy)
    if sip:  # the goggled eyes squint while sipping
        c.set(15, 8 + head_dy + body_dy, "brass_1")
        c.set(20, 8 + head_dy + body_dy, "brass_1")
    cx, cy = cup
    arm = from_ascii(KING_ARM)
    c.paste_over(arm, cx - 4, cy - 1 + (1 if cy < 13 else 0))
    c.ascii(cx, cy, CUP)
    if steam >= 0:
        c.set(cx + 1 + steam % 2, cy - 2, "steam_2")
        c.set(cx + 2 - steam % 2, cy - 3, "steam_3")
    c.outline("soot_0")
    rim_light(c)
    return c


def king_frames() -> dict:
    idle = [
        _king_canvas(steam=0, samovar_steam=0),
        _king_canvas(head_dy=-1, body_dy=0, steam=1, samovar_steam=1),     # breathe in: head rises
        _king_canvas(steam=0, samovar_steam=2),
        _king_canvas(head_dy=1, steam=1, samovar_steam=3),                 # small nod
    ]
    tea = [
        _king_canvas(cup=(25, 15), steam=0, samovar_steam=0),
        _king_canvas(cup=(25, 12), steam=1, samovar_steam=1),
        _king_canvas(cup=(23, 9), sip=True, samovar_steam=2),
        _king_canvas(cup=(23, 9), sip=True, head_dy=-1, samovar_steam=3),
        _king_canvas(cup=(25, 12), steam=0, samovar_steam=0),
        _king_canvas(cup=(25, 15), steam=1, samovar_steam=1),
    ]
    return {"idle": idle, "tea": tea}

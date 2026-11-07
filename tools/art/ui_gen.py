"""UI skin: 9-slice textures (drawn at 1x, saved at 2x) + themes/main_theme.tres.

All UI is displayed at 2x pixel scale, so every texture is upscaled x2 on export and every
margin in the theme is in screen pixels (2 per art pixel).
"""
import os

from pixel import Canvas, upscale

K = 2  # UI pixel scale


def _corners_cut(c: Canvas) -> None:
    for (x, y) in [(0, 0), (c.w - 1, 0), (0, c.h - 1), (c.w - 1, c.h - 1)]:
        c.set(x, y, None)


def bevel_box(c: Canvas, x0: int, y0: int, x1: int, y1: int, light: str, dark: str, corner: str = None) -> None:
    c.hline(x0, x1, y0, light)
    c.vline(x0, y0, y1, light)
    c.hline(x0, x1, y1, dark)
    c.vline(x1, y0, y1, dark)
    if corner:
        c.set(x0, y0, corner)


def rivet(c: Canvas, x: int, y: int, hi: str = "brass_3", lo: str = "brass_1") -> None:
    c.set(x, y, hi)
    c.set(x + 1, y, lo)
    c.set(x, y + 1, lo)
    c.set(x + 1, y + 1, "soot_0")


# ------------------------------------------------------------------ textures

def panel(fill: str = "soot_2", trim=("brass_3", "brass_2", "brass_0"), rivets: bool = True, size: int = 20) -> Canvas:
    """Riveted dark iron plate with a brass frame. 9-slice margin 7."""
    c = Canvas(size, size, fill)
    s = size - 1
    c.frame(0, 0, s, s, "soot_0")
    bevel_box(c, 1, 1, s - 1, s - 1, trim[1], trim[2], trim[0])
    c.frame(2, 2, s - 2, s - 2, "soot_0")
    bevel_box(c, 3, 3, s - 3, s - 3, "iron_0", "soot_1")
    if rivets:
        for (x, y) in [(4, 4), (s - 5, 4), (4, s - 5), (s - 5, s - 5)]:
            rivet(c, x, y)
    _corners_cut(c)
    return c


def card(affordable: bool = False) -> Canvas:
    """Shop card: dark plate, thin trim; affordable = warm brass double edge with corner glints."""
    c = Canvas(16, 16, "soot_2")
    c.frame(0, 0, 15, 15, "soot_0")
    if affordable:
        bevel_box(c, 1, 1, 14, 14, "brass_3", "brass_2", "parchment_2")
        bevel_box(c, 2, 2, 13, 13, "brass_2", "brass_1")
        c.frame(3, 3, 12, 12, "soot_0")
        for (x, y) in [(1, 1), (14, 1), (1, 14), (14, 14)]:
            c.set(x, y, "ember_2")
    else:
        bevel_box(c, 1, 1, 14, 14, "iron_1", "soot_1", "iron_2")
        c.frame(2, 2, 13, 13, "soot_0")
        bevel_box(c, 3, 3, 12, 12, "soot_3", "soot_1")
    _corners_cut(c)
    return c


def button(state: str) -> Canvas:
    """Brass plate button, 14x14, 2 px thick; pressed sinks by 1 px. 9-slice margin 5."""
    c = Canvas(14, 14)
    pal = {
        "normal": ("brass_3", "brass_2", "brass_1", "brass_0"),
        "hover": ("parchment_2", "brass_3", "brass_2", "brass_0"),
        "pressed": ("brass_2", "brass_1", "brass_1", "brass_0"),
        "disabled": ("iron_2", "iron_1", "iron_0", "soot_3"),
    }[state]
    top, face, side, thick = pal
    sink = 1 if state == "pressed" else 0
    y0 = sink                       # outline top row
    fb = 10 + sink                  # last face row
    c.rect(0, y0, 13, 13, "soot_0")
    c.rect(1, y0 + 1, 12, fb, face)
    c.hline(1, 12, fb + 1, side)    # front edge (thickness)
    if not sink:
        c.hline(1, 12, fb + 2, thick)
    if state == "pressed":
        c.hline(1, 12, y0 + 1, "brass_0")   # inner shadow when sunk
        c.vline(1, y0 + 1, fb, "brass_0")
    else:
        c.hline(1, 12, y0 + 1, top)
        c.vline(1, y0 + 1, fb, top)
        c.vline(12, y0 + 2, fb, side)
    for (x, y) in [(0, y0), (13, y0), (0, 13), (13, 13)]:
        c.set(x, y, None)
    return c


def tab(state: str) -> Canvas:
    """Tab head, 12x12; selected merges with the panel below (no bottom edge). 9-slice margin 4."""
    c = Canvas(12, 12)
    if state == "selected":
        c.rect(0, 0, 11, 11, "soot_0")
        c.rect(1, 1, 10, 11, "soot_2")
        c.hline(1, 10, 1, "brass_3")
        c.vline(1, 1, 11, "brass_2")
        c.vline(10, 2, 11, "brass_0")
        c.hline(2, 9, 2, "brass_1")
    else:
        fill, lt, dk = ("soot_2", "iron_1", "soot_0") if state == "hover" else ("soot_1", "iron_0", "soot_0")
        c.rect(0, 2, 11, 11, "soot_0")
        c.rect(1, 3, 10, 10, fill)
        c.hline(1, 10, 3, lt)
        c.vline(1, 3, 10, lt)
        c.hline(0, 11, 11, "soot_0")
    c.set(0, 0 if state == "selected" else 2, None)
    c.set(11, 0 if state == "selected" else 2, None)
    return c


def gauge_bg() -> Canvas:
    """Pressure-gauge tube: brass frame, dark glass, tick marks (tile the middle). 18x10, margin 5/4."""
    c = Canvas(18, 10)
    c.rect(0, 0, 17, 9, "soot_0")
    c.rect(1, 1, 16, 8, "brass_1")
    c.hline(1, 16, 1, "brass_3")
    c.vline(1, 1, 8, "brass_2")
    c.hline(1, 16, 8, "brass_0")
    c.vline(16, 2, 8, "brass_0")
    c.rect(3, 3, 14, 6, "soot_1")
    c.hline(3, 14, 3, "soot_0")
    # end caps (bolts)
    c.set(2, 4, "brass_3")
    c.set(2, 5, "brass_0")
    c.set(15, 4, "brass_2")
    c.set(15, 5, "brass_0")
    # tick marks inside the glass (bottom), repeated by tiling the centre
    for x in (6, 9, 12):
        c.set(x, 6, "iron_0")
    c.set(9, 5, "iron_0")
    c.set(0, 0, None)
    c.set(17, 0, None)
    c.set(0, 9, None)
    c.set(17, 9, None)
    return c


def gauge_fill(kind: str) -> Canvas:
    """18x10 fill matching gauge_bg: transparent where the brass frame is (Godot draws the fill
    over the whole bar rect), liquid inside the glass, bright needle column at the right end."""
    c = Canvas(18, 10)
    ramp = {"ember": ("ember_0", "ember_1", "ember_2", "parchment_2"),
            "steam": ("steam_0", "steam_1", "steam_2", "steam_3"),
            "teal": ("teal_0", "teal_1", "teal_2", "steam_3")}[kind]
    c.hline(3, 14, 3, ramp[2])
    c.hline(3, 14, 4, ramp[1])
    c.hline(3, 14, 5, ramp[1])
    c.hline(3, 14, 6, ramp[0])
    c.set(4, 3, ramp[3])
    c.vline(14, 3, 6, ramp[3])
    c.vline(13, 3, 6, ramp[2])
    return c


def tooltip() -> Canvas:
    """Parchment note with a dark edge. 12x12, margin 4."""
    c = Canvas(12, 12, "parchment_2")
    c.frame(0, 0, 11, 11, "soot_0")
    bevel_box(c, 1, 1, 10, 10, "parchment_2", "parchment_0")
    c.frame(2, 2, 9, 9, "parchment_1")
    c.set(2, 2, "parchment_2")
    c.hline(3, 8, 9, "parchment_1")
    _corners_cut(c)
    return c


def scroll_groove() -> Canvas:
    c = Canvas(6, 10, "soot_1")
    c.frame(0, 0, 5, 9, "soot_0")
    c.vline(1, 1, 8, "soot_0")
    c.vline(4, 1, 8, "soot_2")
    return c


def scroll_grabber(state: str) -> Canvas:
    face = {"normal": ("brass_3", "brass_2", "brass_0"), "hover": ("parchment_2", "brass_3", "brass_1"),
            "pressed": ("brass_2", "brass_1", "brass_0")}[state]
    c = Canvas(6, 10, face[1])
    c.frame(0, 0, 5, 9, "soot_0")
    bevel_box(c, 1, 1, 4, 8, face[0], face[2])
    c.hline(2, 3, 4, face[2])
    c.hline(2, 3, 5, face[0])
    _corners_cut(c)
    return c


def resource_plate() -> Canvas:
    """Counter plate in the top bar. 16x12, margin 4."""
    c = Canvas(16, 12, "soot_1")
    c.frame(0, 0, 15, 11, "soot_0")
    bevel_box(c, 1, 1, 14, 10, "iron_0", "soot_2")
    c.hline(2, 13, 10, "brass_1")
    c.hline(2, 13, 9, "soot_0")
    _corners_cut(c)
    return c


def top_bar() -> Canvas:
    """Full-width strip: iron plate with a brass lower edge. 16x20, margin 6 (tile middle)."""
    c = Canvas(16, 20, "soot_2")
    c.hline(0, 15, 0, "iron_0")
    c.hline(0, 15, 1, "soot_3")
    for x in (3, 11):
        rivet(c, x, 3, "iron_2", "iron_0")
    c.hline(0, 15, 16, "soot_0")
    c.hline(0, 15, 17, "brass_2")
    c.hline(0, 15, 18, "brass_0")
    c.hline(0, 15, 19, "soot_0")
    for x in (7,):
        rivet(c, x, 17, "brass_3", "brass_1")
    return c


def separator() -> Canvas:
    c = Canvas(12, 4)
    c.hline(0, 11, 1, "soot_0")
    c.hline(0, 11, 2, "iron_0")
    c.set(5, 1, "brass_3")
    c.set(6, 1, "brass_1")
    c.set(5, 2, "brass_1")
    c.set(6, 2, "soot_0")
    return c


def inset() -> Canvas:
    """Recessed well (lists, icon slots). 10x10, margin 3."""
    c = Canvas(10, 10, "soot_1")
    c.hline(0, 9, 0, "soot_0")
    c.vline(0, 0, 9, "soot_0")
    c.hline(1, 9, 9, "soot_3")
    c.vline(9, 1, 9, "soot_3")
    c.hline(1, 8, 1, "soot_0")
    return c


def badge() -> Canvas:
    """Small ember badge (e.g. 'available upgrades' counter). 8x8, margin 3."""
    c = Canvas(8, 8, "ember_1")
    c.frame(0, 0, 7, 7, "soot_0")
    bevel_box(c, 1, 1, 6, 6, "ember_2", "ember_0")
    _corners_cut(c)
    return c


TEXTURES = {
    # name: (fn, margins l t r b in ART px, axis stretch h/v: 0 stretch 1 tile 2 tile_fit)
    "panel": (panel, (7, 7, 7, 7), 0),
    "panel_plain": (lambda: panel(rivets=False), (7, 7, 7, 7), 0),
    "card": (card, (4, 4, 4, 4), 0),
    "card_affordable": (lambda: card(True), (4, 4, 4, 4), 0),
    "button_normal": (lambda: button("normal"), (5, 4, 5, 5), 0),
    "button_hover": (lambda: button("hover"), (5, 4, 5, 5), 0),
    "button_pressed": (lambda: button("pressed"), (5, 4, 5, 5), 0),
    "button_disabled": (lambda: button("disabled"), (5, 4, 5, 5), 0),
    "tab_selected": (lambda: tab("selected"), (4, 4, 4, 3), 0),
    "tab_unselected": (lambda: tab("unselected"), (4, 5, 4, 3), 0),
    "tab_hover": (lambda: tab("hover"), (4, 5, 4, 3), 0),
    "gauge_bg": (gauge_bg, (5, 4, 5, 4), 1),
    "gauge_fill_ember": (lambda: gauge_fill("ember"), (5, 4, 5, 4), 0),
    "gauge_fill_steam": (lambda: gauge_fill("steam"), (5, 4, 5, 4), 0),
    "gauge_fill_teal": (lambda: gauge_fill("teal"), (5, 4, 5, 4), 0),
    "tooltip": (tooltip, (4, 4, 4, 4), 0),
    "scroll_groove": (scroll_groove, (2, 2, 2, 2), 0),
    "scroll_grabber": (lambda: scroll_grabber("normal"), (2, 3, 2, 3), 0),
    "scroll_grabber_hover": (lambda: scroll_grabber("hover"), (2, 3, 2, 3), 0),
    "scroll_grabber_pressed": (lambda: scroll_grabber("pressed"), (2, 3, 2, 3), 0),
    "resource_plate": (resource_plate, (4, 4, 4, 4), 0),
    "top_bar": (top_bar, (4, 6, 4, 6), 1),
    "separator": (separator, (4, 1, 4, 1), 1),
    "inset": (inset, (3, 3, 3, 3), 0),
    "badge": (badge, (3, 3, 3, 3), 0),
}


# ------------------------------------------------------------------ theme .tres

def color_of(name: str) -> str:
    import palette as pal
    r, g, b = pal.rgb(name)
    return f"Color({r / 255:.4g}, {g / 255:.4g}, {b / 255:.4g}, 1)"


def write_theme(root: str, save, check) -> list:
    """Saves textures to themes/ui/ and writes themes/main_theme.tres. Returns written paths."""
    ui_dir = os.path.join(root, "themes", "ui")
    os.makedirs(ui_dir, exist_ok=True)
    written = []
    ext, subs, props = [], [], []
    ids = {}
    for i, (name, (fn, _m, _s)) in enumerate(TEXTURES.items()):
        img = fn().img
        check(img, f"themes/ui/{name}.png")
        path = os.path.join(ui_dir, name + ".png")
        upscale(img, K).save(path)
        written.append(path)
        ids[name] = f"t_{name}"
        ext.append(f'[ext_resource type="Texture2D" path="res://themes/ui/{name}.png" id="t_{name}"]')
    fonts = {"regular": "f_regular", "bold": "f_bold", "title": "f_title"}
    for fname, fid in fonts.items():
        ext.append(f'[ext_resource type="FontFile" path="res://fonts/kotel_{fname}.fnt" id="{fid}"]')

    def sb_tex(sid: str, tex: str, content=(0, 0, 0, 0), modulate: str = None) -> str:
        _fn, m, stretch = TEXTURES[tex]
        lines = [f'[sub_resource type="StyleBoxTexture" id="{sid}"]']
        for side, v in zip(("left", "top", "right", "bottom"), content):
            lines.append(f"content_margin_{side} = {float(v)}")
        lines.append(f'texture = ExtResource("{ids[tex]}")')
        for side, v in zip(("left", "top", "right", "bottom"), m):
            lines.append(f"texture_margin_{side} = {float(v * K)}")
        if stretch:
            lines.append(f"axis_stretch_horizontal = {stretch}")
        if modulate:
            lines.append(f"modulate_color = {modulate}")
        subs.append("\n".join(lines))
        return f'SubResource("{sid}")'

    def sb_empty(sid: str) -> str:
        subs.append(f'[sub_resource type="StyleBoxEmpty" id="{sid}"]')
        return f'SubResource("{sid}")'

    C = color_of
    P = props.append
    P('default_font = ExtResource("f_regular")')
    P("default_font_size = 24")

    # --- panels
    panel_sb = sb_tex("panel", "panel", (18, 16, 18, 16))
    P(f"Panel/styles/panel = {panel_sb}")
    P(f"PanelContainer/styles/panel = {panel_sb}")
    for var, tex, cm in (("CardPanel", "card", (14, 12, 14, 12)), ("CardAffordable", "card_affordable", (14, 12, 14, 12)),
                         ("PlainPanel", "panel_plain", (16, 14, 16, 14)), ("TopBar", "top_bar", (12, 6, 12, 10)),
                         ("ResourcePlate", "resource_plate", (8, 4, 12, 6)), ("InsetPanel", "inset", (8, 8, 8, 8)),
                         ("Badge", "badge", (6, 2, 6, 2)), ("TooltipLikePanel", "tooltip", (12, 10, 12, 10))):
        P(f'{var}/base_type = &"PanelContainer"')
        P(f"{var}/styles/panel = {sb_tex('pc_' + var, tex, cm)}")

    # --- buttons (content margins in screen px; pressed moves the label down 2 px)
    P(f"Button/styles/normal = {sb_tex('btn_n', 'button_normal', (14, 6, 14, 10))}")
    P(f"Button/styles/hover = {sb_tex('btn_h', 'button_hover', (14, 6, 14, 10))}")
    P(f"Button/styles/pressed = {sb_tex('btn_p', 'button_pressed', (14, 8, 14, 8))}")
    P(f"Button/styles/hover_pressed = SubResource(\"btn_p\")")
    P(f"Button/styles/disabled = {sb_tex('btn_d', 'button_disabled', (14, 6, 14, 10))}")
    P(f"Button/styles/focus = {sb_empty('btn_focus')}")
    P(f'Button/fonts/font = ExtResource("f_bold")')
    for k, col in (("font_color", "soot_0"), ("font_hover_color", "soot_0"), ("font_pressed_color", "soot_1"),
                   ("font_hover_pressed_color", "soot_1"), ("font_focus_color", "soot_0"),
                   ("font_disabled_color", "soot_3")):
        P(f"Button/colors/{k} = {C(col)}")
    P("Button/constants/h_separation = 8")

    # --- labels
    P(f"Label/colors/font_color = {C('parchment_2')}")
    P(f"Label/colors/font_shadow_color = {C('soot_0')}")
    P("Label/constants/shadow_offset_x = 2")
    P("Label/constants/shadow_offset_y = 2")
    P("Label/constants/line_spacing = 0")
    for var, font, size, col in (("HeaderLabel", "f_title", 32, "brass_3"), ("BoldLabel", "f_bold", 24, "parchment_2"),
                                 ("PriceLabel", "f_bold", 24, "brass_3"), ("DimLabel", None, 24, "iron_3"),
                                 ("GoodLabel", "f_bold", 24, "verdigris_2"), ("BadLabel", "f_bold", 24, "ember_2"),
                                 ("InkLabel", None, 24, "soot_1"), ("CounterLabel", "f_bold", 24, "parchment_2")):
        P(f'{var}/base_type = &"Label"')
        if font:
            P(f'{var}/fonts/font = ExtResource("{font}")')
        P(f"{var}/font_sizes/font_size = {size}")
        P(f"{var}/colors/font_color = {C(col)}")
    P(f"InkLabel/colors/font_shadow_color = Color(0, 0, 0, 0)")
    P(f"RichTextLabel/colors/default_color = {C('parchment_2')}")
    P(f"RichTextLabel/colors/font_shadow_color = {C('soot_0')}")
    P("RichTextLabel/constants/shadow_offset_x = 2")
    P("RichTextLabel/constants/shadow_offset_y = 2")
    P('RichTextLabel/fonts/bold_font = ExtResource("f_bold")')
    P(f"RichTextLabel/styles/normal = {sb_empty('rtl_normal')}")

    # --- tabs
    tsel = sb_tex("tab_sel", "tab_selected", (14, 8, 14, 6))
    tun = sb_tex("tab_un", "tab_unselected", (14, 10, 14, 6))
    thv = sb_tex("tab_hv", "tab_hover", (14, 10, 14, 6))
    for t in ("TabContainer", "TabBar"):
        P(f"{t}/styles/tab_selected = {tsel}")
        P(f"{t}/styles/tab_unselected = {tun}")
        P(f"{t}/styles/tab_hovered = {thv}")
        P(f"{t}/styles/tab_disabled = {tun}")
        P(f"{t}/styles/tab_focus = SubResource(\"btn_focus\")")
        P(f'{t}/fonts/font = ExtResource("f_bold")')
        P(f"{t}/colors/font_selected_color = {C('brass_3')}")
        P(f"{t}/colors/font_unselected_color = {C('iron_3')}")
        P(f"{t}/colors/font_hovered_color = {C('parchment_2')}")
        P(f"{t}/colors/font_disabled_color = {C('iron_1')}")
        P(f"{t}/colors/font_outline_color = {C('soot_0')}")
    P(f"TabContainer/styles/panel = {sb_tex('tab_panel', 'panel_plain', (16, 14, 16, 14))}")
    P(f"TabContainer/styles/tabbar_background = {sb_empty('tabbar_bg')}")
    P("TabContainer/constants/side_margin = 0")

    # --- progress bar = pressure gauge
    P(f"ProgressBar/styles/background = {sb_tex('gauge_bg', 'gauge_bg', (6, 6, 6, 6))}")
    P(f"ProgressBar/styles/fill = {sb_tex('gauge_fill', 'gauge_fill_ember', (0, 0, 0, 0))}")
    P(f'ProgressBar/fonts/font = ExtResource("f_bold")')
    P(f"ProgressBar/colors/font_color = {C('parchment_2')}")
    P(f"ProgressBar/colors/font_outline_color = {C('soot_0')}")
    P("ProgressBar/constants/outline_size = 0")
    P('SteamGauge/base_type = &"ProgressBar"')
    P(f"SteamGauge/styles/fill = {sb_tex('gauge_fill_s', 'gauge_fill_steam')}")
    P('TealGauge/base_type = &"ProgressBar"')
    P(f"TealGauge/styles/fill = {sb_tex('gauge_fill_t', 'gauge_fill_teal')}")

    # --- tooltip
    P(f"TooltipPanel/styles/panel = {sb_tex('tooltip', 'tooltip', (14, 10, 14, 12))}")
    P(f"TooltipLabel/colors/font_color = {C('soot_1')}")
    P("TooltipLabel/colors/font_shadow_color = Color(0, 0, 0, 0)")
    P("TooltipLabel/font_sizes/font_size = 24")

    # --- scrollbars
    groove = sb_tex("sc_groove", "scroll_groove", (4, 4, 4, 4))
    grab = sb_tex("sc_grab", "scroll_grabber", (4, 6, 4, 6))
    grab_h = sb_tex("sc_grab_h", "scroll_grabber_hover", (4, 6, 4, 6))
    grab_p = sb_tex("sc_grab_p", "scroll_grabber_pressed", (4, 6, 4, 6))
    for t in ("VScrollBar", "HScrollBar"):
        P(f"{t}/styles/scroll = {groove}")
        P(f"{t}/styles/scroll_focus = {groove}")
        P(f"{t}/styles/grabber = {grab}")
        P(f"{t}/styles/grabber_highlight = {grab_h}")
        P(f"{t}/styles/grabber_pressed = {grab_p}")

    # --- separators
    sep = sb_tex("sep", "separator", (0, 4, 0, 4))
    P(f"HSeparator/styles/separator = {sep}")
    P("HSeparator/constants/separation = 8")

    # --- tooltip-ish popup & misc
    P(f"PopupPanel/styles/panel = {panel_sb}")

    out = ['[gd_resource type="Theme" format=3]', ""]
    out += ext
    out.append("")
    for s in subs:
        out.append(s)
        out.append("")
    out.append("[resource]")
    out += props
    path = os.path.join(root, "themes", "main_theme.tres")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    written.append(path)
    return written

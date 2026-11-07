"""Unified steampunk pixel palette for Idle King (single source of truth).

Every sprite in assets/sprites is drawn only with these colors.
Ramps go dark -> light (index 0 = darkest).
Run `python3 tools/art/gen_art.py` to re-export config/palette.json and the swatch.
"""

# (name, hex) in display order, grouped by ramp.
RAMPS = {
    "soot":      ["#120f0f", "#1d1817", "#2a2321", "#3b322e"],  # soot blacks / background
    "iron":      ["#3d4247", "#5a6066", "#7f868c", "#a9afb3"],  # iron & steel greys
    "brass":     ["#5c3d14", "#8f6420", "#c49a3a", "#e8c766"],  # brass / gold
    "copper":    ["#4a1f14", "#7d3421", "#b0582f", "#d98a52"],  # copper / rust
    "steam":     ["#5d6b78", "#8a99a6", "#c3ced6", "#eef2f3"],  # steam whites / blue-greys
    "teal":      ["#123f45", "#1f6f74", "#3fa8a3"],             # boiling water
    "ember":     ["#7a1712", "#c8401c", "#f28a2e"],             # embers / fire / damage
    "verdigris": ["#24493b", "#3f7d5f", "#6fb08a"],             # patina accents
    "parchment": ["#8c7451", "#c9b48a", "#ece0bf"],             # UI paper
}

PALETTE = {f"{ramp}_{i}": hexcol for ramp, cols in RAMPS.items() for i, hexcol in enumerate(cols)}
TRANSPARENT = (0, 0, 0, 0)


def rgb(name: str) -> tuple:
    """Palette color as (r, g, b)."""
    h = PALETTE[name].lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def rgba(name: str, alpha: int = 255) -> tuple:
    return rgb(name) + (alpha,)


def names() -> list:
    return list(PALETTE.keys())


if __name__ == "__main__":
    print(f"{len(PALETTE)} colors")
    for n, h in PALETTE.items():
        print(f"  {n:12s} {h}")

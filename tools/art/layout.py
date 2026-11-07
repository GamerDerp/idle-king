"""Battlefield geometry in ART pixels (the world is shown at 2x on screen).

The battlefield background is 450x340 art px = 900x680 screen px, placed at screen (0, 40)
below the 40 px resource bar. Exported to the manifest ("battlefield") for the game.
"""
W, H = 450, 340
SCALE = 2

COURT_X1 = 55        # courtyard 0..55
WALK_X0, WALK_X1 = 56, 87      # wall-top walkway (towers stand here)
MERLON_X0, MERLON_X1 = 88, 95  # crenellations along the outer edge
FACE_X0, FACE_X1 = 96, 107     # outer (east) wall face, in shadow
MOAT_X0, MOAT_X1 = 108, 137    # boiling moat, 30 px (animated water tiles)
BANK_X0, BANK_X1 = 138, 145    # outer earth bank lip (static, drawn in the background)
FIELD_X0 = 146

ROAD_Y = 196         # road centre line at the moat
ROAD_HALF = 17       # half width of the road
GATE_Y = 196         # gatehouse centre (road ends here, bridge is raised)

# tower slots on the walkway: (x, y) = feet anchor in art px (bottom-centre of the tower base)
TOWER_SLOTS = [(72, 78), (72, 117), (72, 156), (72, 266), (72, 306)]
KING_POS = (66, 186)           # the King stands on the gatehouse roof (feet)
GATE_TOP = GATE_Y - 36         # gatehouse sprite top (its drawbridge centre is at GATE_Y)
SMOKE_POINTS = []              # chimney mouths, filled by gen_art (courtyard_props)
STEAM_VENTS_Y = list(range(14, 360, 18))   # steam curtain column positions along the moat


def road_center(x: float) -> float:
    """Road centre y for a given art x on the field (gentle S-curve)."""
    import math
    t = (x - FIELD_X0) / (W - FIELD_X0)
    return ROAD_Y - 34 * math.sin(t * math.pi * 0.9) * t


def as_dict() -> dict:
    return {
        "size": [W, H], "scale": SCALE, "screen_offset": [0, 40],
        "court_x1": COURT_X1, "walk_x": [WALK_X0, WALK_X1], "merlon_x": [MERLON_X0, MERLON_X1],
        "face_x": [FACE_X0, FACE_X1], "moat_x": [MOAT_X0, MOAT_X1], "bank_x": [BANK_X0, BANK_X1],
        "field_x0": FIELD_X0, "road_y": ROAD_Y, "road_half": ROAD_HALF, "gate_y": GATE_Y,
        "tower_slots": [list(p) for p in TOWER_SLOTS], "king_pos": list(KING_POS),
        "steam_vents_y": STEAM_VENTS_Y, "gate_top": GATE_TOP,
        "smoke_points": [list(p) for p in SMOKE_POINTS],
        "road_samples": [[x, round(road_center(x), 1)] for x in range(FIELD_X0, W + 1, 16)],
    }

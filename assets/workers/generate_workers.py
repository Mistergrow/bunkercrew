#!/usr/bin/env python3
"""Author the original LETZTE SCHICHT worker sprites, using only Pillow.

The transparent PNG atlases are checked in: Pillow is not a game dependency.
Each pose is rasterized at native resolution, with no anti-aliasing or resizing.
The rear body and foreground arm are separate so carried items sit in the hands.
Feet anchor: (48, 90) in a 112 x 112 cell. Palette and poses are editable below.
"""
from pathlib import Path
from math import sin, cos, pi, sqrt, atan2
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
CELL, OX, OY = 112, 48, 90
STATES = {
    "idle": 6, "walk": 8, "carry_idle": 6, "carry_walk": 8,
    "jump_up": 3, "fall": 3, "land": 4, "climb": 8,
    "mine": 8, "work": 6, "pickup": 6, "drop": 6, "turret": 4,
    "crouch": 6, "crouch_walk": 8, "crouch_mine": 8,
    "weapon": 4, "weapon_up": 4, "weapon_down": 4,
}
C = {
    "ink": "#151b1e", "deep": "#25302c", "shadow": "#354231",
    "olive": "#566044", "cloth": "#727a50", "light": "#929b67",
    "edge": "#b2b989", "trouser": "#44543c", "trouser_light": "#65744e",
    "skin_shadow": "#83583d", "skin": "#b88957", "skin_light": "#dfba7c",
    "leather": "#674a31", "leather_light": "#987047", "strap": "#43382c",
    "boot": "#352e27", "boot_light": "#5b5141", "sole": "#141b1c",
    "steel": "#89998e", "steel_light": "#c1cbbb", "red": "#9a4535",
}


def add(a, b):
    return a[0] + b[0], a[1] + b[1]


def p(a):
    return round(a[0] + OX), round(a[1] + OY)


def line(d, a, b, color, width=1):
    d.line([p(a), p(b)], fill=color, width=width)


def polygon(d, points, fill, outline=None):
    d.polygon([p(v) for v in points], fill=fill)
    if outline:
        d.line([p(v) for v in points + [points[0]]], fill=outline, width=1)


def box(d, x, y, w, h, fill):
    d.rectangle((round(x + OX), round(y + OY), round(x + OX + w - 1), round(y + OY + h - 1)), fill=fill)


def joint(a, b, length_a, length_b, side=1):
    """Two bone IK, quantized at rasterization; authored endpoints define poses."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    dist = min(max(sqrt(dx * dx + dy * dy), 0.1), length_a + length_b - 0.01)
    along = (length_a * length_a - length_b * length_b + dist * dist) / (2 * dist)
    height = sqrt(max(0, length_a * length_a - along * along))
    norm = max(sqrt(dx * dx + dy * dy), 0.1)
    return a[0] + dx / norm * along - side * dy / norm * height, a[1] + dy / norm * along + side * dx / norm * height


def pose(state, f, _n):
    q = dict(hip=(0, -25), lean=0, head=0, feet=[(-6, -3), (5, -3)], hands=[(-9, -26), (9, -25)],
             tool=None, item=(16, -31), facing_back=False, blink=False)
    if state in ("idle", "carry_idle"):
        bob = [0, 0, -1, -1, 0, 0][f]
        q["hip"] = (0, -25 + bob)
        q["hands"] = [(-9, -26 + bob), (9, -25 + bob)]
        q["head"] = -1 if f == 3 else 0
        q["blink"] = f == 4
        if state == "carry_idle":
            q["lean"] = -1
            q["hands"] = [(9, -33 + bob), (20, -29 + bob)]
            q["item"] = (17, -32 + bob)
    elif state in ("walk", "carry_walk"):
        # Contact, down, passing, high; the other leg follows half a cycle later.
        feet = [(10, -3), (5, -3), (-2, -3), (-10, -4), (-9, -8), (-3, -12), (6, -10), (12, -5)]
        bob = [0, 2, 0, -1, 0, 2, 0, -1][f]
        q["hip"] = (0, -25 + bob)
        q["lean"] = 2
        q["feet"] = [feet[(f + 4) % 8], feet[f]]
        swing = [7, 4, -2, -6, -7, -4, 2, 6][f]
        q["hands"] = [(-8 + swing, -26 + abs(swing) * .2 + bob), (6 - swing, -26 + abs(swing) * .3 + bob)]
        q["head"] = -1 if f in (2, 6) else 0
        if state == "carry_walk":
            q["lean"] = -1
            q["hands"] = [(8, -33 + bob), (20, -29 + bob)]
            q["item"] = (16, -32 + bob)
    elif state == "jump_up":
        q["hip"] = (0, -24)
        q["lean"] = [3, 2, 1][f]
        q["feet"] = [(-10, -8 - f * 2), (9, -12 + f)]
        q["hands"] = [(-13, -44 - f), (15, -42 - f)]
    elif state == "fall":
        q["hip"] = (0, -27)
        q["feet"] = [(-7, -4), (8, -4 - f)]
        q["hands"] = [(-15, -40 + f), (16, -38 + f)]
    elif state == "land":
        bend = [7, 5, 2, 0][f]
        q["hip"] = (0, -25 + bend)
        q["lean"] = bend * .5
        q["feet"] = [(-9, -3), (8, -3)]
        q["hands"] = [(-12, -24 + bend), (14, -23 + bend)]
    elif state == "climb":
        q["facing_back"] = True
        # One complete cycle travels 56 world pixels (four 14px rungs).
        # A planted hand/boot moves down 7 local pixels per frame while the
        # body moves up 7 world pixels: its world grip stays on the same rung.
        # The opposite pair reaches the next hold, then takes the body weight.
        q["hip"] = (0, -25)
        q["hands"] = [(-12, [-56, -49, -42, -35, -28, -35, -45, -54][f]),
                      (12, [-28, -35, -45, -54, -56, -49, -42, -35][f])]
        q["feet"] = [(-8, [-31, -24, -17, -10, -3, -11, -23, -30][f]),
                     (8, [-3, -11, -23, -30, -31, -24, -17, -10][f])]
    elif state == "mine":
        # Two frames of anticipation, quick impact, visible recoil, then recovery.
        lean = [-4, -5, -3, 8, 9, 6, 1, -2][f]
        q["hip"] = (0, -25 + [1, 0, -1, 3, 3, 2, 1, 0][f])
        q["lean"] = lean
        q["feet"] = [(-9, -3), (9, -3)]
        q["head"] = [-1, -2, -2, 2, 2, 1, 0, -1][f]
        hands = [(1, -49), (-3, -58), (-1, -58), (26, -34), (28, -30), (23, -33), (15, -37), (6, -43)]
        q["hands"] = [add(hands[f], (-5, 5)), hands[f]]
        q["tool"] = (hands[f], [-1.1, -1.7, -1.45, .22, .43, .25, -.15, -.7][f])
    elif state == "work":
        q["lean"] = [3, 4, 5, 5, 4, 3][f]
        q["hands"] = [(12, -37), (24 + [0, 1, 2, 1, 0, -1][f], -34)]
        q["item"] = (21, -37)
        q["feet"] = [(-7, -3), (7, -3)]
    elif state in ("pickup", "drop"):
        bend = [2, 6, 10, 8, 4, 0][f] if state == "pickup" else [0, 3, 7, 8, 5, 1][f]
        q["hip"] = (-2, -25 + bend * .55)
        q["lean"] = bend * .9
        q["head"] = bend * .4
        q["hands"] = [(11 + bend * .4, -28 + bend * 1.3), (17 + bend * .3, -26 + bend * 1.45)]
        q["item"] = (17 + bend * .3, -29 + bend * 1.45)
        q["feet"] = [(-8, -3), (8, -3)]
    elif state == "turret":
        recoil = [0, -3, -1, 0][f]
        q["hip"] = (-1, -24)
        q["lean"] = 5 + recoil
        q["head"] = recoil
        q["hands"] = [(20 + recoil, -39), (24 + recoil, -37)]
        q["feet"] = [(-10, -3), (8, -3)]
    elif state in ("crouch", "crouch_walk", "crouch_mine"):
        q["hip"] = (-3, -13)
        q["lean"] = 7
        q["head"] = 5
        q["hands"] = [(8, -20), (20, -17)]
        q["item"] = (16, -20)
        q["feet"] = [(-8, -3), (8, -3)]
        if state == "crouch_walk":
            step = [(-8, -3), (-4, -3), (1, -3), (7, -3), (9, -5), (5, -6), (0, -6), (-6, -5)]
            q["feet"] = [step[(f+4)%8], step[f]]
        elif state == "crouch_mine":
            hands = [(8, -25), (5, -27), (7, -28), (23, -23), (24, -21), (20, -22), (16, -23), (11, -24)]
            q["hands"] = [add(hands[f], (-5, 4)), hands[f]]
            q["tool"] = (hands[f], [-.8, -1, -.85, .1, .3, .1, -.2, -.6][f])
    elif state.startswith("weapon"):
        recoil = [0, 3, 1, 0][f]
        angle = -.7 if state == "weapon_up" else (.7 if state == "weapon_down" else 0)
        q["lean"] = 1 - recoil * .6
        q["head"] = -1 if angle < 0 else (1 if angle > 0 else 0)
        q["feet"] = [(-8, -3), (7, -3)]
        grips = []
        for grip in [(-1-recoil,1),(15-recoil,-1)]:
            grips.append((10+cos(angle)*grip[0]-sin(angle)*grip[1],
                          -38+sin(angle)*grip[0]+cos(angle)*grip[1]))
        q["hands"] = grips
    return q


def leg(d, hip, foot, front):
    knee = joint(hip, foot, 12, 12, -1)
    hi = C["trouser_light"] if front else C["shadow"]
    mid = C["trouser"] if front else C["deep"]
    for a, b, width in [(hip, knee, 9), (knee, foot, 8)]:
        line(d, a, b, C["ink"], width)
        line(d, add(a, (0, -1)), add(b, (0, -1)), mid, width - 2)
        line(d, add(a, (-1, -1)), add(b, (-1, -2)), hi, 2)
    box(d, knee[0] - 2, knee[1] - 1, 5, 4, C["shadow"])
    box(d, knee[0] - 1, knee[1] - 1, 4, 1, hi)
    x, y = foot
    polygon(d, [(x - 4, y - 4), (x + 2, y - 4), (x + 3, y - 1), (x + 7, y), (x + 7, y + 3), (x - 5, y + 3), (x - 5, y)], C["boot"], C["ink"])
    box(d, x - 3, y - 2, 5, 3, C["boot_light"] if front else C["strap"])
    box(d, x - 4, y + 2, 12, 2, C["sole"])
    box(d, x + 3, y, 3, 1, C["leather_light"] if front else C["boot_light"])
    box(d, x - 1, y - 3, 2, 1, C["leather_light"])


def arm(d, shoulder, hand, front, back=False):
    elbow = joint(shoulder, hand, 11, 12, 1 if not back else -1)
    # Upper arm is cloth, forearm is a rolled cuff and fingerless leather glove.
    line(d, shoulder, elbow, C["ink"], 9)
    line(d, shoulder, elbow, C["olive"] if front else C["shadow"], 7)
    line(d, add(shoulder, (-2, 0)), add(elbow, (-2, 0)), C["light"] if front else C["olive"], 2)
    line(d, elbow, hand, C["ink"], 7)
    line(d, elbow, hand, C["cloth"] if front else C["olive"], 5)
    line(d, add(elbow, (0, -1)), add(hand, (0, -1)), C["light"] if front else C["cloth"], 2)
    box(d, elbow[0] - 2, elbow[1] - 1, 4, 3, C["shadow"])
    box(d, hand[0] - 3, hand[1] - 2, 7, 6, C["ink"])
    box(d, hand[0] - 2, hand[1] - 1, 5, 4, C["leather_light"] if front else C["leather"])
    box(d, hand[0] + 1, hand[1] - 1, 2, 2, C["skin_light"] if front else C["skin"])
    box(d, hand[0] - 2, hand[1] + 2, 4, 1, C["leather"])


def worker(state, frame, count, player):
    if state == "climb":
        return climber(frame, count, player)
    body = Image.new("RGBA", (CELL, CELL))
    foreground = Image.new("RGBA", (CELL, CELL))
    d, fg = ImageDraw.Draw(body), ImageDraw.Draw(foreground)
    q = pose(state, frame, count)
    hx, hy = q["hip"]
    lean = q["lean"]
    shoulder = (hx + lean, hy - 17)
    rear_shoulder = add(shoulder, (-6, 0))
    front_shoulder = add(shoulder, (3, 0))
    front_hip, rear_hip = (hx + 4, hy), (hx - 4, hy)
    back = q["facing_back"]
    leg(d, rear_hip, q["feet"][0], False)
    arm(d, rear_shoulder, q["hands"][0], False, back)
    # Canvas backpack, side flask, rolled bedding and two straps.
    bx, by = shoulder[0] - 13, shoulder[1] + 2
    polygon(d, [(bx - 3, by), (bx + 6, by - 2), (bx + 9, by + 4), (bx + 7, by + 17), (bx - 3, by + 16), (bx - 5, by + 10)], C["leather"], C["ink"])
    box(d, bx - 2, by + 1, 7, 11, C["leather_light"])
    box(d, bx, by + 1, 2, 15, C["strap"])
    box(d, bx + 1, by + 8, 2, 2, C["steel"])
    box(d, bx - 4, by + 9, 4, 6, C["olive"])
    box(d, bx - 3, by + 8, 2, 1, C["steel"])
    line(d, (bx - 3, by - 1), (bx + 7, by - 1), C["ink"], 5)
    line(d, (bx - 3, by - 2), (bx + 7, by - 2), C["olive"], 3)
    leg(d, front_hip, q["feet"][1], True)
    # Tapered jacket has a broad shoulder, narrow waist and an uneven hem.
    x, y = shoulder
    polygon(d, [(x - 8, y - 3), (x + 5, y - 3), (x + 9, y + 3), (hx + 9, hy - 1), (hx + 6, hy + 3), (hx - 9, hy + 2), (x - 11, y + 6)], C["olive"], C["ink"])
    polygon(d, [(x - 7, y - 2), (x + 1, y - 2), (hx + 1, hy - 2), (hx - 7, hy - 2), (x - 9, y + 6)], C["cloth"])
    line(d, (x - 7, y), (hx - 7, hy - 4), C["light"], 2)
    polygon(d, [(x + 3, y), (x + 7, y + 4), (hx + 7, hy - 2), (hx + 3, hy - 3)], C["shadow"])
    line(d, (x + 1, y + 2), (hx + 1, hy - 1), C["deep"], 1)
    box(d, x - 6, y + 4, 6, 5, C["shadow"])
    box(d, x - 6, y + 4, 6, 1, C["light"])
    box(d, x - 4, y + 6, 1, 1, C["steel_light"])
    line(d, (x - 7, y - 1), (hx - 4, hy - 2), C["strap"], 2)
    box(d, hx - 9, hy - 2, 18, 3, C["strap"])
    box(d, hx + 1, hy - 2, 4, 3, C["steel"])
    box(d, hx + 2, hy - 1, 2, 1, C["deep"])
    box(d, hx - 8, hy, 5, 6, C["leather"])
    box(d, hx - 7, hy + 1, 4, 1, C["leather_light"])
    box(d, hx - 6, hy + 3, 1, 1, C["steel_light"])
    # Red neck cloth gives the warm skin a strong separation from the jacket.
    nx, ny = x + 1, y - 3
    box(d, nx - 4, ny - 4, 9, 6, C["skin_shadow"])
    polygon(d, [(nx - 5, ny), (nx + 5, ny - 1), (nx + 4, ny + 3), (nx - 3, ny + 2)], C["red"], C["ink"])
    box(d, nx - 3, ny, 7, 1, "#c46749")
    # Face in three-quarter profile: visible ear, brow, nose, cheek and jaw.
    fx, fy = x + 1 + q["head"] * .2, y - 15 + q["head"]
    polygon(d, [(fx - 6, fy), (fx + 5, fy - 1), (fx + 7, fy + 4), (fx + 10, fy + 6), (fx + 9, fy + 8), (fx + 6, fy + 8), (fx + 6, fy + 12), (fx + 2, fy + 14), (fx - 5, fy + 11), (fx - 7, fy + 5)], C["skin_shadow"], C["ink"])
    if not back:
        polygon(d, [(fx - 2, fy + 3), (fx + 5, fy + 2), (fx + 6, fy + 5), (fx + 9, fy + 6), (fx + 5, fy + 8), (fx + 5, fy + 11), (fx, fy + 11), (fx - 2, fy + 8)], C["skin"])
        box(d, fx + 2, fy + 6, 3, 3, C["skin_light"])
        box(d, fx + 6, fy + 6, 3, 1, C["skin_light"])
        box(d, fx - 5, fy + 5, 3, 4, C["skin"])
        box(d, fx - 4, fy + 6, 1, 2, C["skin_light"])
        box(d, fx + 3, fy + 3, 4, 2, C["deep"])
        box(d, fx + 5, fy + 4, 1, 1, C["skin_light"] if not q["blink"] else C["skin_shadow"])
        box(d, fx + 3, fy + 10, 4, 1, C["deep"])
        box(d, fx, fy + 12, 4, 1, C["skin_shadow"])
        box(d, fx - 5, fy + 2, 2, 3, C["strap"])
    else:
        box(d, fx - 5, fy + 4, 12, 5, C["strap"])
        box(d, fx - 4, fy + 9, 10, 2, C["skin_shadow"])
    # Hardhat follows stepped arcs. A 1px hot edge is consistent with bunker lamps.
    hat = ["#83582d", "#ca932e", "#eabd50", "#ffe191"] if player == 1 else ["#28646a", "#3b929c", "#66c9cd", "#b1ece1"]
    polygon(d, [(fx - 9, fy + 2), (fx - 8, fy - 4), (fx - 5, fy - 7), (fx + 3, fy - 8), (fx + 7, fy - 5), (fx + 9, fy + 1), (fx + 11, fy + 2), (fx + 11, fy + 4), (fx - 10, fy + 4)], hat[0], C["ink"])
    polygon(d, [(fx - 7, fy), (fx - 7, fy - 3), (fx - 4, fy - 5), (fx + 3, fy - 6), (fx + 6, fy - 4), (fx + 7, fy + 1)], hat[1])
    polygon(d, [(fx - 6, fy - 2), (fx - 3, fy - 5), (fx + 2, fy - 5), (fx + 3, fy - 2), (fx + 2, fy)], hat[2])
    line(d, (fx - 3, fy - 5), (fx + 2, fy - 6), hat[3])
    box(d, fx - 8, fy + 1, 19, 2, hat[2])
    box(d, fx - 8, fy + 3, 17, 1, hat[0])
    box(d, fx + 6, fy - 1, 4, 4, C["ink"])
    box(d, fx + 7, fy, 2, 2, "#fff0b8")
    # Rank stripe is the helmet color, never a class restriction.
    box(d, x - 9, y + 2, 4, 2, hat[1])
    if q["tool"]:
        hand, angle = q["tool"]
        end = add(hand, (cos(angle) * 23, sin(angle) * 23))
        tail = add(hand, (-cos(angle) * 9, -sin(angle) * 9))
        line(fg, tail, end, C["ink"], 5)
        line(fg, tail, end, C["leather_light"], 3)
        line(fg, add(tail, (0, -1)), add(end, (0, -1)), "#cfa366", 1)
        axis = (-sin(angle), cos(angle))
        a, b = add(end, (axis[0] * 11, axis[1] * 11)), add(end, (-axis[0] * 10, -axis[1] * 10))
        line(fg, a, b, C["ink"], 6)
        line(fg, a, b, C["steel"], 3)
        line(fg, add(a, (0, -1)), add(b, (0, -1)), C["steel_light"], 1)
        if frame in (3, 4):
            # A sharp 2-frame tool glint complements impact particles from mining.
            ex, ey = end
            line(fg, (ex - 4, ey - 4), (ex + 3, ey + 3), "#ead8a1")
    arm(fg, front_shoulder, q["hands"][1], True, back)
    return body, foreground, [round(v) for v in q["item"]]


def climber(frame, count, player):
    """A dedicated back view, with hands on rails and soles on ladder rungs."""
    body = Image.new("RGBA", (CELL, CELL))
    foreground = Image.new("RGBA", (CELL, CELL))
    d, fg = ImageDraw.Draw(body), ImageDraw.Draw(foreground)
    q = pose("climb", frame, count)
    for index, side in enumerate((-1, 1)):
        hip, foot = (side * 5, -25), q["feet"][index]
        a, b = joint(hip, foot, 12, 12, -1), joint(hip, foot, 12, 12, 1)
        knee = min((a,b),key=lambda point:point[0]) if side < 0 else max((a,b),key=lambda point:point[0])
        for start, end in ((hip, knee), (knee, foot)):
            line(d,start,end,C["ink"],9)
            line(d,start,end,C["trouser"],7)
            line(d,add(start,(-1,0)),add(end,(-1,0)),C["trouser_light"],2)
        box(d,knee[0]-3,knee[1]-1,6,3,C["shadow"])
        box(d,knee[0]-2,knee[1]-1,4,1,C["cloth"])
        x,y=foot
        polygon(d,[(x-4,y-5),(x+3,y-5),(x+4,y+3),(x-5,y+3)],C["boot"],C["ink"])
        box(d,x-3,y-3,5,4,C["boot_light"])
        box(d,x-3,y-2,4,1,C["leather_light"])
        box(d,x-5,y+2,10,2,C["sole"])
        box(d,x-3,y+2,6,1,"#817158")
    polygon(d,[(-10,-44),(-6,-47),(6,-47),(10,-44),(12,-35),(9,-24),(-9,-24),(-12,-35)],C["olive"],C["ink"])
    polygon(d,[(-8,-44),(-2,-45),(-2,-27),(-8,-26),(-10,-35)],C["cloth"])
    line(d,(-9,-40),(-8,-27),C["light"],2)
    box(d,-9,-26,18,3,C["strap"])
    box(d,-2,-26,4,3,C["steel"])
    box(d,-10,-25,5,7,C["leather"])
    box(d,-9,-24,4,1,C["leather_light"])
    # Symmetric shoulder straps and a central canvas pack establish rear view.
    line(d,(-7,-43),(-6,-27),C["strap"],3)
    line(d,(7,-43),(6,-27),C["strap"],3)
    polygon(d,[(-7,-43),(6,-43),(9,-38),(8,-28),(5,-25),(-6,-25),(-9,-29),(-9,-38)],C["leather"],C["ink"])
    polygon(d,[(-6,-41),(4,-41),(6,-38),(5,-29),(-6,-29),(-7,-34)],C["leather_light"])
    box(d,-6,-38,12,2,C["strap"])
    box(d,-4,-34,8,6,C["leather"])
    box(d,-4,-34,8,1,"#b08a58")
    box(d,-1,-33,2,2,C["steel"])
    box(d,-7,-40,2,13,C["strap"])
    box(d,5,-40,2,13,C["strap"])
    line(d,(-7,-43),(7,-43),C["ink"],5)
    line(d,(-6,-43),(6,-43),C["cloth"],3)
    box(d,-5,-45,2,5,C["strap"])
    box(d,3,-45,2,5,C["strap"])
    # Nape, hair and helmet rim: no profile nose/eye or front chest pockets.
    box(d,-5,-51,10,7,C["skin_shadow"])
    box(d,-3,-49,6,3,C["skin"])
    box(d,-6,-47,12,2,C["red"])
    box(d,-7,-58,14,9,C["ink"])
    box(d,-6,-55,12,5,C["strap"])
    box(d,-7,-54,2,4,C["skin_shadow"])
    box(d,6,-54,2,4,C["skin"])
    hat = ["#83582d", "#ca932e", "#eabd50", "#ffe191"] if player == 1 else ["#28646a", "#3b929c", "#66c9cd", "#b1ece1"]
    polygon(d,[(-10,-56),(-9,-61),(-6,-65),(5,-65),(9,-61),(10,-56),(11,-55),(10,-52),(-11,-52),(-12,-54)],hat[0],C["ink"])
    polygon(d,[(-8,-57),(-7,-61),(-4,-64),(4,-64),(7,-61),(8,-57)],hat[1])
    polygon(d,[(-6,-58),(-5,-61),(-3,-63),(1,-63),(2,-58)],hat[2])
    line(d,(-4,-64),(2,-64),hat[3])
    box(d,-10,-56,20,2,hat[2])
    box(d,-8,-54,16,1,hat[0])
    box(d,-3,-55,6,2,C["strap"])
    box(d,-1,-55,2,1,C["steel"])
    # Each elbow bends outwards, leaving the central pack visible.
    for index, side in enumerate((-1,1)):
        shoulder,hand=(side*8,-42),q["hands"][index]
        a,b=joint(shoulder,hand,11,12,-1),joint(shoulder,hand,11,12,1)
        elbow=min((a,b),key=lambda point:point[0]) if side<0 else max((a,b),key=lambda point:point[0])
        for start,end in ((shoulder,elbow),(elbow,hand)):
            line(fg,start,end,C["ink"],8)
            line(fg,start,end,C["olive"],6)
            line(fg,add(start,(-1,-1)),add(end,(-1,-1)),C["light"],2)
        box(fg,elbow[0]-2,elbow[1]-1,4,3,C["shadow"])
        x,y=hand
        box(fg,x-3,y-2,7,6,C["ink"])
        box(fg,x-2,y-1,5,4,C["leather_light"])
        box(fg,x-2,y+2,4,1,C["leather"])
        box(fg,x-2,y-1,4,1,C["skin_light"])
    return body,foreground,[16,-31]


def props():
    atlas = Image.new("RGBA", (24 * 7, 24))
    colors = [("#c89c59", "#e4c47b"), ("#747d85", "#c38a58"), ("#738f94", "#c3d2c4"), ("#81887b", "#c4c8a9"), ("#58613a", "#c8a151"), ("#825e48", "#be936a")]
    for i, (base, light) in enumerate(colors):
        im = Image.new("RGBA", (24, 24)); d = ImageDraw.Draw(im)
        if i in (0, 1):
            d.polygon([(3, 10), (6, 5), (11, 4), (14, 6), (18, 5), (21, 10), (20, 18), (16, 21), (6, 20), (3, 17)], fill=C["ink"])
            d.polygon([(4, 11), (7, 6), (12, 5), (15, 8), (18, 6), (20, 11), (18, 18), (8, 19), (5, 16)], fill=base)
            d.polygon([(7, 8), (11, 6), (14, 9), (11, 13), (5, 13)], fill=light)
            d.line([(5, 16), (11, 15), (16, 17), (19, 12)], fill=C["leather"])
            if i == 1:
                for x, y in [(9, 8), (15, 10), (8, 15), (17, 16)]: d.rectangle((x, y, x+2, y+1), fill=light)
        elif i == 2:
            for y in (6, 11, 16):
                d.polygon([(1,y+1), (19,y), (23,y+2), (22,y+5), (2,y+6), (0,y+4)], fill=C["ink"])
                d.line([(2,y+2), (20,y+1)], fill=light, width=2)
                d.line([(2,y+4), (20,y+3)], fill=base, width=2)
                d.point((21,y+3), fill=C["steel_light"])
        elif i == 3:
            d.line([(5,9), (5,3), (7,1), (17,1), (19,3), (19,9)], fill=C["ink"], width=3)
            d.line([(5,9), (5,3), (7,1), (17,1), (19,3), (19,9)], fill=C["steel"], width=1)
            d.polygon([(2,7), (22,7), (19,22), (6,22)], fill=C["ink"])
            d.polygon([(4,9), (20,9), (18,20), (7,20)], fill=base)
            d.rectangle((3,7,21,9),fill=light)
            d.rectangle((7,11,9,19),fill="#aeb099")
            d.line([(12,14), (17,14)], fill="#5b635b", width=2)
        elif i == 4:
            d.rectangle((2,5,22,22),fill=C["ink"])
            d.rectangle((3,7,21,20),fill=base)
            d.rectangle((4,5,20,8),fill="#7c8252")
            d.rectangle((9,3,15,5),outline=C["steel"])
            for x in (7,11,15): d.rectangle((x,11,x+1,17),fill=light)
            d.rectangle((3,19,21,20),fill="#354230")
        else:
            d.polygon([(2,8),(18,2),(22,7),(17,11),(21,18),(10,22),(3,18)],fill=C["ink"])
            d.line([(5,9),(16,5),(19,7)],fill=base,width=4)
            d.line([(6,17),(15,12),(19,18)],fill=light,width=3)
            d.rectangle((9,8,12,16),fill="#65777a")
        atlas.alpha_composite(im,(i*24,0))
    # Separate poured-bucket silhouette avoids smooth runtime sprite rotation.
    im = Image.new("RGBA", (24, 24)); d = ImageDraw.Draw(im)
    d.line([(8,8),(11,1),(15,2),(22,6),(21,13)],fill=C["ink"],width=3)
    d.line([(8,8),(11,1),(15,2),(22,6),(21,13)],fill=C["steel"],width=1)
    d.polygon([(6,6),(22,14),(15,23),(1,16)],fill=C["ink"])
    d.polygon([(6,9),(19,15),(14,21),(4,16)],fill="#81887b")
    d.polygon([(6,7),(21,14),(20,16),(5,9)],fill="#c4c8a9")
    d.line([(6,12),(13,17)],fill="#aeb099",width=2)
    d.line([(16,17),(13,20)],fill="#5b635b",width=2)
    atlas.alpha_composite(im,(6*24,0))
    atlas.save(ROOT / "material_props.png")


def main():
    metadata = {"cell": CELL, "anchor": [OX, OY], "states": {}}
    for player in (1, 2):
        bodies = Image.new("RGBA", (CELL * 8, CELL * len(STATES)))
        arms = Image.new("RGBA", bodies.size)
        for row, (state, count) in enumerate(STATES.items()):
            anchors = []
            for f in range(count):
                body, arm_image, anchor = worker(state, f, count, player)
                bodies.alpha_composite(body, (f * CELL, row * CELL))
                arms.alpha_composite(arm_image, (f * CELL, row * CELL))
                anchors.append(anchor)
            metadata["states"][state] = {"row": row, "frames": count, "item_anchors": anchors}
            if state == "climb":
                poses = [pose(state, f, count) for f in range(count)]
                metadata["states"][state].update({"rung_pitch": 14, "cycle_distance": 56,
                    "hands": [q["hands"] for q in poses], "feet": [q["feet"] for q in poses]})
        bodies.save(ROOT / f"worker_{player}_body.png")
        arms.save(ROOT / f"worker_{player}_arms.png")
    (ROOT / "worker_frames.json").write_text(json.dumps(metadata, indent=2) + "\n")
    props()
    # Contact sheet is a review artifact; it is not loaded by the game.
    sheet = Image.new("RGB", (CELL * 8, CELL * len(STATES)), "#232c31")
    d = ImageDraw.Draw(sheet)
    for row, (state, count) in enumerate(STATES.items()):
        for f in range(count):
            body, arm_image, anchor = worker(state, f, count, 1)
            sheet.paste(body, (f*CELL,row*CELL),body)
            sheet.paste(arm_image,(f*CELL,row*CELL),arm_image)
        d.text((2,row*CELL+2),state,fill="#aebcbb")
    sheet.save(ROOT / "worker_contact_sheet.png")


if __name__ == "__main__":
    main()

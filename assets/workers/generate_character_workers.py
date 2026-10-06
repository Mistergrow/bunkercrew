#!/usr/bin/env python3
"""Author all eight Bunkercrew identities from original native pixel geometry.

No imported image is read or transformed. The existing 110 authored pose
records remain the input contract: feet, tool contacts, cargo and weapons keep
all their original anchors. Every clean head/coat also has a rear-view piece.
Recruit generator entry points delegate here rather than inheriting base heads.
"""
from pathlib import Path
from copy import deepcopy
import hashlib
import json
from math import cos, sin
from PIL import Image, ImageDraw
import generate_workers as rig

ROOT = Path(__file__).resolve().parent
IDS = ("mara", "branko", "ivo", "nora", "levin", "selma", "oskar", "rika")
PARTS = ("body", "arms", "torso", "head", "back_torso", "back_head")
BASE_PALETTE = rig.C.copy()
VISUALS = json.loads((ROOT / "character_visuals.json").read_text())
PROFILES = deepcopy(VISUALS["identities"])
MOTION = VISUALS["motion_profiles"]
MOTION_FRAMES = json.loads((ROOT / "character_motion_frames.json").read_text())
LICENSE = "Original Bunkercrew source-authored pixel geometry. Distribution only together with Bunkercrew; standalone redistribution and use in other projects are not permitted."
VISUAL_SIGNATURES = {
    "mara": {"head": "amber hardhat and long dark braid", "outfit": "short rust work jacket with reflective shoulder bands", "equipment": "small belt satchel"},
    "branko": {"head": "ivory hardhat and full dark beard", "outfit": "broad navy guard coat with split hem and padded shoulders", "equipment": "squared heavy guard pack"},
    "ivo": {"head": "low olive cloth cap and large welding goggles", "outfit": "narrow leather tool vest over teal sleeves", "equipment": "three visible tools and rolled tool pouch"},
    "nora": {"head": "wide bronze helmet brim and short dark bob", "outfit": "slate engineer vest with high collar and measuring gauge", "equipment": "long blueprint tube and rectangular folio"},
    "levin": {"head": "pointed olive hood with exposed side face", "outfit": "short asymmetric field poncho and neck scarf", "equipment": "radio pack with long aerial"},
    "selma": {"head": "soft ivory medical cap and short auburn bob", "outfit": "long sage field jacket with pale medical insignia", "equipment": "large cream cross-marked medical bag"},
    "oskar": {"head": "raised headlamp on a dust helmet and short moustache", "outfit": "heavy work overalls with long leather miner apron", "equipment": "tall squared dust pack and tool strap"},
    "rika": {"head": "dark beanie with cropped hair and copper headset", "outfit": "short ochre insulated electrician jacket", "equipment": "round copper cable reel and handheld-meter pouch"},
}
# Copper workwear separates Rika from Nora's slate and Branko's navy clothes.
PROFILES["rika"]["palette"].update({"deep":"#3e3029", "shadow":"#66503d", "olive":"#96724f", "cloth":"#b88d5b", "light":"#d8b07b", "edge":"#edcf9c", "red":"#c6a66e"})
for identity in IDS:
    PROFILES[identity]["visual_signature"] = VISUAL_SIGNATURES[identity]


def character_pose(state, frame, identity):
    """Return the existing authored trajectory without changing any joint."""
    return deepcopy(MOTION_FRAMES[identity][state][frame])


def _established_head(d, x, y, identity, blink=False, back=False):
    c, h = rig.C, PROFILES[identity]["hat"]
    # Hair extends beyond the helmet: Mara's braid stays visible in every pose.
    if identity == "mara":
        rig.polygon(d, [(x-7,y+1),(x-12,y+5),(x-13,y+14),(x-10,y+23),(x-6,y+25),(x-7,y+18),(x-8,y+10),(x-5,y+7)], "#322a29",c["ink"])
        rig.line(d,(x-10,y+8),(x-9,y+19),"#66503a",2)
        rig.box(d,x-11,y+11,4,2,h[1])
    if back:
        rig.box(d,x-6,y+1,12,11,c["skin_shadow"])
        rig.box(d,x-6,y+1,12,7,"#332c29")
        rig.box(d,x-4,y+8,8,3,c["skin"])
    else:
        jaw = 7 if identity == "branko" else (4 if identity == "mara" else 5)
        rig.polygon(d,[(x-6,y),(x+5,y-1),(x+7,y+4),(x+10,y+6),(x+9,y+8),(x+6,y+8),(x+jaw,y+12),(x+1,y+14),(x-5,y+11),(x-7,y+5)],c["skin_shadow"],c["ink"])
        rig.polygon(d,[(x-2,y+2),(x+5,y+2),(x+6,y+5),(x+9,y+6),(x+5,y+8),(x+4,y+11),(x,y+11),(x-2,y+8)],c["skin"])
        rig.box(d,x+2,y+6,3,3,c["skin_light"])
        rig.box(d,x+6,y+6,3,1,c["skin_light"])
        rig.box(d,x-5,y+5,3,4,c["skin"])
        rig.box(d,x-4,y+6,1,2,c["skin_light"])
        rig.box(d,x+3,y+3,4,2,c["deep"])
        rig.box(d,x+5,y+4,1,1,c["skin_light"] if not blink else c["skin_shadow"])
        rig.box(d,x+3,y+10,4,1,c["deep"])
        if identity == "branko":
            rig.polygon(d,[(x-5,y+7),(x-1,y+9),(x+3,y+8),(x+8,y+8),(x+8,y+12),(x+4,y+17),(x-2,y+16),(x-6,y+11)],"#302b2a",c["ink"])
            rig.line(d,(x-3,y+10),(x+1,y+14),"#6a5545",2)
            rig.box(d,x+3,y+10,4,1,c["skin_shadow"])
            rig.box(d,x+2,y+14,3,1,"#88745d")
        elif identity == "mara":
            rig.line(d,(x-5,y+1),(x-4,y+7),"#3d2d27",2)
            rig.box(d,x+4,y+11,3,1,"#995446")
    if identity == "ivo":
        # Low fabric cap and bulky welding goggles create a different head contour.
        rig.polygon(d,[(x-8,y+1),(x-7,y-4),(x-3,y-6),(x+4,y-6),(x+7,y-3),(x+8,y),(x+12,y+1),(x+12,y+3),(x-9,y+3)],h[0],c["ink"])
        rig.polygon(d,[(x-6,y),(x-5,y-3),(x+3,y-4),(x+5,y-2),(x+6,y)],h[1])
        rig.line(d,(x-3,y-4),(x+3,y-4),h[2],1)
        rig.box(d,x-7,y+3,15,3,"#332d24")
        if not back:
            rig.box(d,x+1,y+2,9,6,c["ink"])
            rig.box(d,x+2,y+3,7,4,"#82c9bf")
            rig.box(d,x+3,y+3,2,2,"#e1e5bb")
            rig.box(d,x+6,y+4,2,2,"#447871")
        else:
            rig.box(d,x-3,y+3,6,2,"#b09966")
        return
    rig.polygon(d,[(x-9,y+2),(x-8,y-4),(x-5,y-7),(x+3,y-8),(x+7,y-5),(x+9,y+1),(x+11,y+2),(x+11,y+4),(x-10,y+4)],h[0],c["ink"])
    rig.polygon(d,[(x-7,y),(x-7,y-3),(x-4,y-5),(x+3,y-6),(x+6,y-4),(x+7,y+1)],h[1])
    rig.polygon(d,[(x-6,y-2),(x-3,y-5),(x+2,y-5),(x+3,y-2),(x+2,y)],h[2])
    rig.line(d,(x-3,y-5),(x+2,y-6),h[3])
    rig.box(d,x-8,y+1,19,2,h[2])
    rig.box(d,x-8,y+3,17,1,h[0])
    if not back:
        rig.box(d,x+6,y-1,4,4,c["ink"])
        rig.box(d,x+7,y,2,2,"#fff0b8")
    else:
        rig.box(d,x-3,y+2,6,2,c["strap"])



def _established_torso(d, shoulder, hip, identity, back=False):
    c = rig.C
    x,y = shoulder; hx,hy = hip
    width = PROFILES[identity]["width"]
    left,right = round(-10*width),round(9*width)
    waist = 10 if identity == "branko" else (7 if identity == "ivo" else 8)
    if not back:
        # Distinct pack shapes: light belt satchel, broad guard pack, tool roll.
        if identity == "mara":
            rig.polygon(d,[(x-12,y+6),(x-7,y+5),(hx-7,hy+4),(hx-14,hy+4),(x-15,y+10)],c["leather"],c["ink"])
            rig.box(d,x-13,y+9,5,7,c["leather_light"])
        else:
            pack_width = 11 if identity == "branko" else 7
            rig.polygon(d,[(x-left-25,y+1),(x-7,y),(x-5,y+7),(hx-7,hy+2),(hx-7-pack_width,hy+1),(x-left-27,y+9)],c["leather"],c["ink"])
            rig.box(d,x-15,y+3,6,12,c["leather_light"])
            rig.box(d,x-13,y+3,2,15,c["strap"])
    rig.polygon(d,[(x+left,y-3),(x+right-4,y-3),(x+right,y+3),(hx+waist,hy+2),(hx-waist,hy+2),(x+left-2,y+7)],c["olive"],c["ink"])
    rig.polygon(d,[(x+left+2,y-2),(x,y-2),(hx,hy-2),(hx-waist+2,hy-2),(x+left,y+6)],c["cloth"])
    rig.line(d,(x+left+2,y),(hx-waist+2,hy-3),c["light"],2)
    rig.line(d,(x+2,y+2),(hx+2,hy-1),c["deep"],1)
    if identity == "mara":
        rig.line(d,(x+left+1,y+3),(x+right-2,y+3),"#e6bd7c",2)
        rig.line(d,(x+left+2,y+5),(hx-waist+2,hy-4),"#e6bd7c",2)
        rig.box(d,x-5,y+7,5,5,c["shadow"])
        rig.box(d,x-5,y+7,5,1,c["edge"])
    elif identity == "branko":
        # A long coat hem, large collar and segmented shoulder padding change silhouette.
        rig.polygon(d,[(hx-11,hy-3),(hx+10,hy-3),(hx+12,hy+8),(hx+2,hy+9),(hx,hy+4),(hx-11,hy+7)],c["olive"],c["ink"])
        rig.line(d,(hx-9,hy),(hx-9,hy+5),c["light"],2)
        rig.box(d,x+left-1,y-3,10,6,c["deep"])
        rig.box(d,x+left,y-3,8,2,c["light"])
        rig.box(d,x-7,y+5,7,7,c["deep"])
        rig.box(d,x-6,y+5,6,2,c["light"])
        rig.line(d,(x-7,y-3),(x+6,y-3),"#b49d7b",3)
    else:
        rig.polygon(d,[(x-6,y-3),(x+2,y-3),(x+5,y+3),(hx+5,hy),(hx-7,hy),(x-8,y+5)],c["leather"],c["ink"])
        rig.line(d,(x-5,y),(hx-5,hy-2),c["leather_light"],2)
        rig.box(d,x-4,y+8,8,7,c["strap"])
        for ox in [-3,0,3]:
            rig.box(d,x+ox,y+5,2,7,c["steel"])
            rig.box(d,x+ox,y+5,1,2,c["steel_light"])
    rig.box(d,hx-waist,hy-2,waist*2,3,c["strap"])
    rig.box(d,hx+1,hy-2,4,3,c["steel"])
    if back:
        rig.polygon(d,[(x-7,y),(x+6,y),(x+8,y+6),(hx+6,hy),(hx-7,hy),(x-9,y+8)],c["leather"],c["ink"])
        rig.box(d,x-6,y+3,11,10,c["leather_light"])
        rig.box(d,x-6,y+6,11,2,c["strap"])
        rig.line(d,(x-6,y),(hx-6,hy),c["strap"],2)
        rig.line(d,(x+5,y),(hx+5,hy),c["strap"],2)
        if identity == "ivo":
            rig.box(d,x-8,y-1,15,5,c["olive"])
            rig.box(d,x-6,y-1,2,5,c["strap"])
            rig.box(d,x+3,y-1,2,5,c["strap"])
    rig.box(d,x-3,y-7,8,5,c["skin_shadow"])
    rig.polygon(d,[(x-4,y-3),(x+6,y-4),(x+5,y),(x-2,y-1)],c["red"],c["ink"])



def _face(d, x, y, identity, blink=False, back=False):
    c = rig.C
    if back:
        rig.box(d,x-5,y+3,11,9,c["skin_shadow"])
        rig.box(d,x-3,y+9,7,3,c["skin"])
        return
    jaw = 7 if identity == "oskar" else 4
    rig.polygon(d,[(x-6,y),(x+5,y-1),(x+7,y+4),(x+10,y+6),(x+9,y+8),(x+6,y+8),(x+jaw,y+12),(x+1,y+14),(x-5,y+11),(x-7,y+5)],c["skin_shadow"],c["ink"])
    rig.polygon(d,[(x-2,y+2),(x+5,y+2),(x+6,y+5),(x+9,y+6),(x+5,y+8),(x+4,y+11),(x,y+11),(x-2,y+8)],c["skin"])
    rig.box(d,x+2,y+6,3,3,c["skin_light"])
    rig.box(d,x+6,y+6,3,1,c["skin_light"])
    rig.box(d,x-5,y+5,3,4,c["skin"])
    rig.box(d,x-4,y+6,1,2,c["skin_light"])
    rig.box(d,x+3,y+3,4,2,c["deep"])
    rig.box(d,x+5,y+4,1,1,c["skin_shadow"] if blink else c["skin_light"])
    rig.box(d,x+3,y+10,4,1,c["deep"])


def head(d, x, y, identity, blink=False, back=False):
    # Side profiles only. Rear pieces show the same haircut/headwear on ladders.
    if identity in ("mara", "branko", "ivo"):
        return _established_head(d,x,y,identity,blink,back)
    c,h = rig.C,PROFILES[identity]["hat"]
    if identity in ("nora", "selma"):
        hair = "#372d2b" if identity == "nora" else "#6a3e2c"
        hair_light = "#685047" if identity == "nora" else "#a16a45"
        rig.polygon(d,[(x-7,y-3),(x-11,y+1),(x-12,y+12),(x-9,y+18),(x-5,y+17),(x-3,y+10),(x+5,y+6),(x+4,y-2)],hair,c["ink"])
        rig.line(d,(x-9,y+4),(x-9,y+13),hair_light,2)
        if back:
            rig.polygon(d,[(x-8,y+2),(x+7,y+2),(x+8,y+13),(x+5,y+17),(x-8,y+17),(x-10,y+11)],hair,c["ink"])
            rig.line(d,(x-5,y+6),(x-4,y+14),hair_light,2)
    elif identity == "levin":
        # A peaked, fabric hood reads at native size even in monochrome.
        rig.polygon(d,[(x-4,y-14),(x-11,y-10),(x-15,y-1),(x-14,y+11),(x-9,y+17),(x+2,y+15),(x+7,y+7),(x+7,y-4)],h[0],c["ink"])
        rig.polygon(d,[(x-5,y-10),(x-10,y-4),(x-10,y+6),(x-5,y+12),(x+2,y+9),(x+4,y-2)],h[1])
        rig.line(d,(x-9,y-4),(x-10,y+6),h[2],2)
    elif identity == "rika":
        rig.polygon(d,[(x-6,y-4),(x+4,y-4),(x+7,y+2),(x+2,y+8),(x-4,y+11),(x-8,y+6)],"#312c2c",c["ink"])
        rig.line(d,(x-6,y+3),(x-5,y+9),"#675143",2)
    _face(d,x,y,identity,blink,back)
    if identity == "nora":
        # Low industrial engineer helmet, broad level brim, exposed short bob.
        rig.polygon(d,[(x-10,y),(x-9,y-7),(x-5,y-11),(x+3,y-11),(x+8,y-7),(x+10,y),(x+15,y+1),(x+15,y+4),(x-14,y+4),(x-14,y+1)],h[0],c["ink"])
        rig.polygon(d,[(x-7,y-2),(x-7,y-6),(x-4,y-8),(x+3,y-8),(x+6,y-5),(x+7,y)],h[1])
        rig.line(d,(x-5,y-7),(x+3,y-7),h[2],2)
        rig.box(d,x-12,y+1,26,2,h[2])
        rig.box(d,x-6,y-3,6,4,c["deep"])
        rig.box(d,x-5,y-2,4,2,"#c4cfb2")
    elif identity == "levin":
        if back:
            rig.polygon(d,[(x-4,y-14),(x-11,y-8),(x-14,y+5),(x-9,y+15),(x+4,y+15),(x+8,y+3),(x+7,y-5)],h[0],c["ink"])
            rig.polygon(d,[(x-4,y-10),(x-8,y-3),(x-8,y+9),(x+1,y+13),(x+4,y+7),(x+3,y-2)],h[1])
        else:
            rig.polygon(d,[(x-4,y-12),(x+3,y-9),(x+7,y-3),(x+7,y+2),(x+3,y+1),(x-1,y-4)],h[1],c["ink"])
            rig.polygon(d,[(x-9,y+8),(x-4,y+8),(x+2,y+12),(x+6,y+11),(x+5,y+16),(x-5,y+18),(x-11,y+14)],c["shadow"],c["ink"])
            rig.line(d,(x-7,y+12),(x+2,y+14),c["light"],2)
    elif identity == "selma":
        rig.polygon(d,[(x-9,y+1),(x-8,y-5),(x-4,y-9),(x+2,y-9),(x+7,y-5),(x+9,y+1),(x+9,y+4),(x-9,y+4)],h[0],c["ink"])
        rig.polygon(d,[(x-7,y),(x-6,y-4),(x-2,y-6),(x+3,y-6),(x+6,y-2),(x+6,y+1)],h[1])
        rig.box(d,x-8,y+1,17,3,h[2])
        rig.box(d,x-2,y-6,5,6,"#537363")
        rig.box(d,x,y-5,1,4,h[3])
        rig.box(d,x-1,y-3,3,1,h[3])
        rig.line(d,(x-5,y-5),(x-2,y-7),h[3])
    elif identity == "oskar":
        # The raised lamp and short moustache replace the guard's full beard.
        rig.polygon(d,[(x-9,y+2),(x-9,y-4),(x-6,y-8),(x+2,y-9),(x+7,y-5),(x+9,y+1),(x+12,y+2),(x+12,y+5),(x-10,y+5)],h[0],c["ink"])
        rig.polygon(d,[(x-7,y),(x-7,y-3),(x-5,y-6),(x+2,y-7),(x+6,y-4),(x+7,y)],h[1])
        rig.line(d,(x-5,y-5),(x,y-6),h[2],2)
        rig.box(d,x-8,y+2,19,2,h[2])
        rig.box(d,x+2,y-13,9,10,c["ink"])
        rig.box(d,x+3,y-12,7,7,h[1])
        rig.box(d,x+5,y-11,4,5,"#e9d7a3")
        rig.box(d,x+6,y-10,2,3,"#fff0bd")
        if not back:
            rig.box(d,x+1,y+9,6,2,"#3c3029")
            rig.box(d,x-3,y+11,5,1,"#75523c")
        else:
            rig.box(d,x-5,y+6,10,4,"#484238")
    elif identity == "rika":
        # Ribbed beanie, cropped hair and a prominent rear ear cup/mic boom.
        rig.polygon(d,[(x-8,y+1),(x-8,y-7),(x-5,y-11),(x+2,y-11),(x+6,y-8),(x+7,y),(x+8,y+2),(x-8,y+2)],"#283237",c["ink"])
        rig.polygon(d,[(x-6,y-2),(x-6,y-6),(x-3,y-8),(x+2,y-8),(x+4,y-5),(x+5,y)],"#46565b")
        for ox in (-4,-1,2): rig.line(d,(x+ox,y-7),(x+ox,y-2),"#647777")
        rig.box(d,x-8,y,16,3,"#243035")
        rig.line(d,(x-7,y-6),(x-9,y+1),"#bda270",2)
        rig.box(d,x-11,y+1,7,11,c["ink"])
        rig.box(d,x-10,y+2,5,8,"#a77948")
        rig.box(d,x-9,y+3,3,5,"#d2ad74")
        rig.box(d,x-9,y+5,3,2,"#584738")
        if not back:
            rig.line(d,(x-5,y+9),(x+8,y+11),"#725d40",2)
            rig.box(d,x+7,y+10,4,3,c["ink"])
            rig.box(d,x+8,y+10,2,1,"#b3beb2")
        else:
            rig.line(d,(x-7,y+5),(x+6,y+5),"#af8b59",2)
            rig.box(d,x+5,y+2,5,8,"#8f673e")


def _reel(d, x, y, radius=9):
    c=rig.C
    d.ellipse([rig.p((x-radius,y-radius)),rig.p((x+radius,y+radius))],fill=c["ink"])
    d.ellipse([rig.p((x-radius+1,y-radius+1)),rig.p((x+radius-1,y+radius-1))],fill="#c08a4d")
    d.ellipse([rig.p((x-5,y-5)),rig.p((x+5,y+5))],fill="#674a33",outline="#e3b873")
    d.ellipse([rig.p((x-3,y-3)),rig.p((x+3,y+3))],fill="#252c2b")
    rig.line(d,(x-6,y-4),(x+5,y+5),"#a4aba0",2)
    rig.box(d,x-1,y-1,3,3,"#d1c4a0")


def torso(d, shoulder, hip, identity, back=False):
    if identity in ("mara", "branko", "ivo"):
        return _established_torso(d,shoulder,hip,identity,back)
    c=rig.C
    x,y=shoulder; hx,hy=hip
    width=PROFILES[identity]["width"]
    left,right=round(-10*width),round(9*width)
    waist=9 if identity=="oskar" else 8
    if not back:
        if identity=="nora":
            rig.polygon(d,[(x-18,y-6),(x-13,y-6),(hx-12,hy+8),(hx-17,hy+8)],c["leather"],c["ink"])
            rig.line(d,(x-16,y-4),(hx-15,hy+5),"#9faeaa",2)
            rig.box(d,x-19,y-6,7,3,"#d6c39c")
            rig.box(d,x-21,y+8,10,15,c["deep"])
            rig.box(d,x-20,y+9,8,12,"#9d9980")
            rig.box(d,x-19,y+10,5,8,"#d2c8a5")
            rig.box(d,x-20,y+14,8,2,c["leather"])
        elif identity=="levin":
            rig.box(d,x-20,y+3,9,19,c["ink"])
            rig.box(d,x-19,y+4,7,17,c["shadow"])
            rig.box(d,x-18,y+6,5,7,c["light"])
            rig.box(d,x-17,y+9,3,2,c["deep"])
            rig.line(d,(x-15,y-20),(x-15,y+6),c["ink"],3)
            rig.line(d,(x-15,y-20),(x-15,y-3),"#9aa795",1)
            rig.box(d,x-16,y-21,3,3,"#b7c2ab")
        elif identity=="selma":
            rig.box(d,x-22,y+6,14,18,c["ink"])
            rig.box(d,x-21,y+7,12,16,"#b8c3a3")
            rig.box(d,x-20,y+8,10,4,"#d7dfc0")
            rig.box(d,x-20,y+15,10,2,"#7d947e")
            rig.box(d,x-17,y+12,3,10,"#e6e7ca")
            rig.box(d,x-21,y+16,11,3,"#e6e7ca")
            rig.box(d,x-19,y+5,7,2,c["strap"])
        elif identity=="oskar":
            rig.polygon(d,[(x-21,y-3),(x-10,y-3),(hx-10,hy+6),(hx-21,hy+6)],c["deep"],c["ink"])
            rig.box(d,x-19,y-1,7,19,c["leather_light"])
            rig.box(d,x-19,y+4,7,3,c["strap"])
            rig.box(d,x-19,y+16,7,3,c["strap"])
        else:
            _reel(d,x-13,y+12)
            rig.line(d,(x-18,y+16),(hx-13,hy+5),"#ab7e45",2)
    hem=8 if identity=="selma" else 2
    rig.polygon(d,[(x+left,y-3),(x+right-4,y-3),(x+right,y+3),(hx+waist,hy+hem),(hx-waist,hy+hem),(x+left-2,y+7)],c["olive"],c["ink"])
    rig.polygon(d,[(x+left+2,y-2),(x,y-2),(hx,hy-2),(hx-waist+2,hy+hem-2),(x+left,y+6)],c["cloth"])
    rig.line(d,(x+left+2,y),(hx-waist+2,hy+hem-3),c["light"],2)
    rig.line(d,(x+2,y+2),(hx+2,hy-1),c["deep"])
    if identity=="nora":
        rig.polygon(d,[(x-9,y-4),(x+5,y-4),(x+7,y+6),(hx+6,hy),(hx-8,hy)],c["shadow"],c["ink"])
        rig.line(d,(x-7,y),(hx-6,hy-2),c["edge"],2)
        rig.box(d,x-4,y+5,8,6,c["deep"])
        rig.box(d,x-3,y+6,6,4,"#c5c3a3")
        rig.box(d,x-1,y+6,1,3,"#6c7370")
        rig.box(d,x-6,y-4,10,3,c["light"])
    elif identity=="levin":
        rig.polygon(d,[(x-12,y-4),(x+6,y-4),(x+12,y+5),(hx+8,hy+4),(hx-16,hy+1),(x-15,y+7)],c["shadow"],c["ink"])
        rig.polygon(d,[(x-10,y-2),(x+1,y-1),(hx-5,hy),(hx-14,hy-1)],c["olive"])
        rig.line(d,(x-9,y+1),(hx-12,hy-2),c["light"],2)
        rig.line(d,(x+3,y),(hx+3,hy),c["leather_light"],2)
        rig.box(d,x-7,y-5,11,4,"#8d9980")
    elif identity=="selma":
        rig.line(d,(x-7,y+2),(hx+5,hy),"#b8c3a3",3)
        rig.box(d,x+1,y+6,6,7,c["deep"])
        rig.box(d,x+3,y+7,2,5,"#e3e5c7")
        rig.box(d,x+1,y+9,6,2,"#e3e5c7")
        rig.box(d,hx-7,hy+2,6,4,c["shadow"])
        rig.box(d,hx+2,hy+2,5,4,c["shadow"])
        rig.line(d,(hx,hy),(hx,hy+6),c["deep"])
    elif identity=="oskar":
        rig.polygon(d,[(x-8,y+1),(x+5,y+1),(hx+11,hy+10),(hx-9,hy+11),(hx-11,hy+8)],c["leather"],c["ink"])
        rig.line(d,(x-6,y-4),(x-5,y+8),c["leather_light"],3)
        rig.line(d,(x+3,y-3),(x+3,y+7),c["leather_light"],3)
        rig.line(d,(x-6,y+3),(hx-7,hy+8),"#a18054",2)
        rig.box(d,hx-5,hy-4,10,8,c["strap"])
        rig.box(d,hx-4,hy-3,8,2,c["leather_light"])
        rig.box(d,x-5,y+2,2,2,c["steel_light"])
        rig.box(d,x+3,y+2,2,2,c["steel_light"])
    else:
        rig.polygon(d,[(x-8,y-3),(x+4,y-3),(x+7,y+5),(hx+6,hy-1),(hx-6,hy-1)],c["cloth"],c["ink"])
        rig.line(d,(x-6,y-2),(hx-5,hy-3),c["edge"],2)
        rig.box(d,x+1,y+4,7,7,"#413f36")
        rig.box(d,x+2,y+5,5,3,"#9bb89c")
        rig.box(d,x+2,y+10,2,1,"#d8b976")
        rig.box(d,x-6,y+7,4,8,c["deep"])
        rig.box(d,x-5,y+8,2,2,"#b18e5c")
    rig.box(d,hx-waist,hy-2,waist*2,3,c["strap"])
    rig.box(d,hx+1,hy-2,4,3,c["steel"])
    if back:
        if identity=="rika":
            _reel(d,x-1,y+10,12)
            rig.line(d,(x-8,y),(hx-6,hy+1),c["strap"],2)
            rig.line(d,(x+6,y),(hx+6,hy+1),c["strap"],2)
        else:
            pw=9 if identity=="oskar" else 7
            rig.polygon(d,[(x-pw,y),(x+pw,y),(x+pw+1,y+6),(hx+pw,hy+2),(hx-pw,hy+2),(x-pw-2,y+8)],c["leather"],c["ink"])
            rig.box(d,x-pw+1,y+3,pw*2-1,12,c["leather_light"])
            rig.box(d,x-pw+1,y+7,pw*2-1,2,c["strap"])
            rig.line(d,(x-pw+1,y),(hx-pw+1,hy),c["strap"],2)
            if identity=="selma":
                rig.box(d,x-6,y+3,12,13,"#a9b99a")
                rig.box(d,x-1,y+4,3,11,"#e2e4c5")
                rig.box(d,x-5,y+8,11,3,"#e2e4c5")
            elif identity=="nora":
                rig.box(d,x-12,y-7,5,30,"#8a958e")
                rig.box(d,x-13,y-7,7,3,"#d6c39c")
                rig.box(d,x-5,y+4,9,9,"#c1b69a")
                rig.box(d,x-5,y+8,9,2,c["strap"])
            elif identity=="levin":
                rig.line(d,(x-7,y-20),(x-7,y+5),c["ink"],3)
                rig.line(d,(x-7,y-20),(x-7,y+4),"#a7b1a0")
                rig.box(d,x-5,y+3,10,5,c["olive"])
                rig.box(d,x-3,y+4,3,2,c["edge"])
            elif identity=="oskar":
                rig.box(d,x-9,y-3,18,4,c["shadow"])
                rig.box(d,x-7,y+14,14,4,c["strap"])
    rig.box(d,x-3,y-7,8,5,c["skin_shadow"])
    rig.polygon(d,[(x-4,y-3),(x+6,y-4),(x+5,y),(x-2,y-1)],c["red"],c["ink"])


def worker(state, frame, identity):
    q = character_pose(state,frame,identity)
    rig.C = dict(BASE_PALETTE, **PROFILES[identity]["palette"])
    c = rig.C
    body = Image.new("RGBA",(rig.CELL,rig.CELL))
    foreground = Image.new("RGBA",body.size)
    d,fg = ImageDraw.Draw(body),ImageDraw.Draw(foreground)
    hx,hy = q["hip"]; shoulder = (hx+q["lean"],hy-17)
    if state == "climb":
        for index,side in enumerate((-1,1)):
            hip,foot = (side*5,-25),q["feet"][index]
            a,b = rig.joint(hip,foot,12,12,-1),rig.joint(hip,foot,12,12,1)
            knee = min((a,b),key=lambda p:p[0]) if side<0 else max((a,b),key=lambda p:p[0])
            for start,end in ((hip,knee),(knee,foot)):
                rig.line(d,start,end,c["ink"],9)
                rig.line(d,start,end,c["trouser"],7)
                rig.line(d,rig.add(start,(-1,0)),rig.add(end,(-1,0)),c["trouser_light"],2)
            rig.box(d,foot[0]-5,foot[1]-4,10,7,c["ink"])
            rig.box(d,foot[0]-3,foot[1]-3,6,5,c["boot_light"])
            rig.box(d,foot[0]-5,foot[1]+2,10,2,c["sole"])
        torso(d,shoulder,(hx,hy),identity,True)
        head(d,0,-57,identity,back=True)
        for index,side in enumerate((-1,1)):
            rig.arm(fg,(side*8,-42),q["hands"][index],True,True)
    else:
        rig.leg(d,(hx-4,hy),q["feet"][0],False)
        rig.arm(d,rig.add(shoulder,(-6,0)),q["hands"][0],False)
        rig.leg(d,(hx+4,hy),q["feet"][1],True)
        torso(d,shoulder,(hx,hy),identity)
        head(d,shoulder[0]+1+q["head"]*.2,shoulder[1]-15+q["head"],identity,q["blink"])
        if q["tool"]:
            hand,angle = q["tool"]
            end = rig.add(hand,(cos(angle)*23,sin(angle)*23))
            tail = rig.add(hand,(-cos(angle)*9,-sin(angle)*9))
            rig.line(fg,tail,end,c["ink"],5)
            rig.line(fg,tail,end,c["leather_light"],3)
            rig.line(fg,rig.add(tail,(0,-1)),rig.add(end,(0,-1)),"#cfa366",1)
            axis = (-sin(angle),cos(angle))
            a,b = rig.add(end,(axis[0]*11,axis[1]*11)),rig.add(end,(-axis[0]*10,-axis[1]*10))
            rig.line(fg,a,b,c["ink"],6)
            rig.line(fg,a,b,c["steel"],3)
            rig.line(fg,rig.add(a,(0,-1)),rig.add(b,(0,-1)),c["steel_light"],1)
            if frame in (3,4): rig.line(fg,rig.add(end,(-4,-4)),rig.add(end,(3,3)),"#ead8a1")
        rig.arm(fg,rig.add(shoulder,(3,0)),q["hands"][1],True)
    return body,foreground


def main(identities=None, output=None):
    """Rebuild native sprites, preserving pose/anchor files byte-for-byte.

    ``output`` supports isolated generator regressions. Legacy recruit entry
    points pass their subset while the shared catalog still contains all eight.
    """
    identities = tuple(identities or IDS)
    if any(identity not in IDS for identity in identities):
        raise ValueError("Unknown crew identity")
    destination = Path(output) if output is not None else ROOT
    destination.mkdir(parents=True, exist_ok=True)
    for identity in IDS:
        if set(MOTION_FRAMES[identity]) != set(rig.STATES):
            raise ValueError(f"{identity}: incomplete original pose contract")
        for state, count in rig.STATES.items():
            if len(MOTION_FRAMES[identity][state]) != count:
                raise ValueError(f"{identity} {state}: missing original frame")
    history_path = ROOT / "identities/source-history-20261005.json"
    history = json.loads(history_path.read_text())["sources"]
    source_hash = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    pose_hash = hashlib.sha256((ROOT / "character_motion_frames.json").read_bytes()).hexdigest()
    for identity in identities:
        bodies = Image.new("RGBA",(rig.CELL*8,rig.CELL*len(rig.STATES)))
        arms = Image.new("RGBA",bodies.size)
        for row,(state,count) in enumerate(rig.STATES.items()):
            for frame in range(count):
                body,foreground = worker(state,frame,identity)
                bodies.alpha_composite(body,(frame*rig.CELL,row*rig.CELL))
                arms.alpha_composite(foreground,(frame*rig.CELL,row*rig.CELL))
        bodies.save(destination/f"{identity}_body.png")
        arms.save(destination/f"{identity}_arms.png")
        rig.C = dict(BASE_PALETTE, **PROFILES[identity]["palette"])
        for back in (False,True):
            for piece in ("torso","head"):
                image = Image.new("RGBA",(rig.CELL,rig.CELL))
                draw = ImageDraw.Draw(image)
                if piece == "torso":
                    torso(draw,(0,-42),(0,-25),identity,back)
                else:
                    head(draw,1,-57,identity,back=back)
                name=f"{identity}_{'back_' if back else ''}{piece}.png"
                image.save(destination/name)
        names=[f"{identity}_{piece}.png" for piece in PARTS]
        notice={
            "source":"generate_character_workers.py", "source_sha256":source_hash,
            "rig":"generate_workers.py",
            "method":"Original source-authored pixel geometry; no imported image edits",
            "identity":identity, "states":19, "frames":110, "cell":112,
            "feet_anchor":[48,90], "head_origin":[49,33], "torso_origin":[48,48],
            "motion":MOTION[identity], "palette":PROFILES[identity],
            "motion_frames":"character_motion_frames.json", "motion_frames_sha256":pose_hash,
            "assets":names, "sha256":{name:hashlib.sha256((destination/name).read_bytes()).hexdigest() for name in names},
            "license":LICENSE,
            "source_history":"identities/source-history-20261005.json",
            "previous_source_sha256":history[identity]["notice_sha256"],
        }
        (destination/f"{identity}.source.json").write_text(json.dumps(notice,indent=2)+"\n")
    catalog=deepcopy(VISUALS)
    catalog.update({"source":"generate_character_workers.py", "identities":PROFILES,
                    "visual_contract":{"view":"side and rear only", "head_origin":[49,33], "torso_origin":[48,48], "parts":list(PARTS)},
                    "source_history":"identities/source-history-20261005.json"})
    (destination/"character_visuals.json").write_text(json.dumps(catalog,indent=2)+"\n")
    print(f"Authored {len(identities)} crew identities / {len(identities)*6} sprites; all 110 original poses preserved")


if __name__ == "__main__":
    main()

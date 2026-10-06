#!/usr/bin/env python3
"""Original pixel UI skins/icons; title rasterizes the bundled licensed font."""
from pathlib import Path
import random
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
INK, STEEL, LIGHT, AMBER = '#0b1012','#6e756f','#dfdfc9','#d7a451'


def plate(name, active=False, pressed=False):
    im=Image.new('RGBA',(128,80)); d=ImageDraw.Draw(im)
    border=[(6,1),(120,1),(126,7),(126,72),(120,78),(6,78),(1,73),(1,7)]
    d.polygon(border,fill='#080d10')
    d.polygon([(7,3),(119,3),(124,8),(124,71),(119,76),(7,76),(3,71),(3,8)],fill='#48524f')
    d.line([(7,3),(119,3),(124,8)],fill='#9b9e87',width=1)
    d.line([(3,8),(3,71),(7,76)],fill='#727968',width=1)
    d.line([(7,76),(119,76),(124,71),(124,8)],fill='#232d2d',width=2)
    d.rectangle((7,8,120,71),fill='#252d2b' if active else '#171e20')
    d.line([(8,9),(118,9)],fill='#846d43' if active else '#3a4440',width=1)
    d.line([(8,70),(118,70)],fill='#0c1316',width=2)
    rng=random.Random(71)
    for _ in range(95):
        x,y=rng.randint(10,117),rng.randint(12,67)
        d.point((x,y),fill=rng.choice(['#1d2425','#202829','#171e20','#29302c']))
    for x,y in [(10,5),(84,4),(123,19),(3,56),(33,75),(102,76)]:
        d.line([(x,y),(x+3,y)],fill='#acac8d',width=1)
        d.point((x+1,y+1),fill='#111819')
    for x,y in [(7,8),(120,8),(7,71),(120,71)]:
        d.rectangle((x-2,y-2,x+2,y+2),fill='#101719')
        d.rectangle((x-1,y-1,x+1,y+1),fill='#92947d')
        d.point((x-1,y-1),fill='#d0ccad')
        d.line([(x-1,y+1),(x+1,y-1)],fill='#48534a')
    if active:
        d.line([(15,5),(111,5)],fill=AMBER,width=2)
        d.line([(15,74),(111,74)],fill='#775b30',width=1)
    if pressed:
        d.rectangle((9,10,118,69),fill=(0,0,0,65))
    im.save(ROOT/name)


def icon(kind):
    im=Image.new('RGBA',(32,32)); d=ImageDraw.Draw(im)
    def line(points,fill,width=3):
        d.line(points,fill=INK,width=width+2); d.line(points,fill=fill,width=width)
    if kind in ('wall','fortress','workshop'):
        d.rectangle((5,6,26,27),fill=INK)
        d.rectangle((7,7,24,25),fill='#81867a')
        d.line([(7,8),(23,8)],fill=LIGHT,width=2)
        for y in (13,20):d.line([(7,y),(24,y)],fill='#363e37',width=2)
        for x,y in [(15,8),(11,14),(20,21)]:d.line([(x,y),(x,y+5)],fill='#363e37',width=1)
        if kind=='fortress':
            for x in (8,20):d.rectangle((x,5,x+3,27),fill='#455861');d.line([(x,6),(x,26)],fill='#bbc8bd')
        if kind=='workshop':line([(8,26),(23,8)],AMBER,3);line([(19,7),(28,14)],STEEL,6)
    elif kind in ('rifle','shotgun','arcgun'):
        line([(4,21),(10,17)],'#796344',5)
        d.rectangle((9,12,24,19),fill=INK);d.rectangle((10,13,24,17),fill='#889285')
        line([(22,14),(29,14)],LIGHT,2)
        line([(13,18),(11,25)],'#7d7150',3)
        d.rectangle((17,18,20,23),fill='#9c8153')
        if kind=='shotgun':line([(21,18),(29,18)],'#a9b09e',2)
        if kind=='arcgun':
            d.rectangle((14,10,23,19),fill='#435966')
            for x in (15,18,21):d.line([(x,11),(x,17)],fill='#9acbc9',width=1)
    elif kind=='boots':
        d.polygon([(8,5),(19,5),(19,19),(28,23),(28,28),(5,28),(5,23)],fill=INK)
        d.polygon([(9,7),(17,7),(17,21),(25,24),(25,26),(8,26),(7,22)],fill='#8f7350')
        for y in (10,14,18):d.line([(9,y),(16,y)],fill=LIGHT)
        d.line([(7,27),(27,27)],fill='#4a4b3d',width=2)
    elif kind=='harness':
        d.rectangle((7,6,24,28),fill=INK);d.rectangle((9,7,22,26),fill='#9c8050')
        d.rectangle((11,15,20,24),fill='#715d3e')
        for x in (10,20):d.line([(x,7),(x,26)],fill='#343b30',width=2)
        d.line([(11,6),(21,6)],fill=LIGHT,width=2);d.rectangle((14,17,17,19),fill=LIGHT)
    elif kind=='craftsmanship':
        line([(7,26),(25,7)],'#ac8c58',4);line([(19,7),(28,14)],'#b7c0ae',6)
        line([(6,9),(25,27)],STEEL,3);d.ellipse((3,4,10,12),outline=LIGHT,width=2)
    elif kind=='core':
        for box,col in [((3,3,28,28),(80,126,148,40)),((6,6,25,25),(115,182,204,55))]:d.ellipse(box,fill=col)
        d.polygon([(16,4),(26,13),(22,26),(10,26),(6,13)],fill=INK)
        d.polygon([(16,6),(23,13),(19,24),(12,24),(9,13)],fill='#719aab')
        d.polygon([(16,7),(17,16),(12,22),(10,13)],fill='#c3e6e1')
        d.line([(17,16),(21,13)],fill=LIGHT)
    elif kind=='helmet':
        d.polygon([(5,22),(6,13),(11,8),(22,8),(27,14),(28,22)],fill=INK)
        d.polygon([(7,21),(8,14),(12,10),(21,10),(25,14),(26,21)],fill=AMBER)
        d.rectangle((4,22,29,24),fill='#e7ca73');d.rectangle((9,15,11,19),fill='#f6df96')
        d.rectangle((22,18,26,22),fill=INK);d.rectangle((23,19,25,21),fill=LIGHT)
    elif kind=='ammo':
        for x in (7,14,21):
            d.polygon([(x,7),(x+2,3),(x+4,7),(x+4,27),(x,27)],fill=INK)
            d.rectangle((x+1,9,x+3,25),fill='#c7a260');d.line([(x+1,9),(x+1,23)],fill='#f1d293')
    elif kind in ('limestone','tungsten'):
        d.polygon([(5,13),(12,6),(23,8),(28,20),(21,27),(6,25)],fill=INK)
        d.polygon([(7,14),(13,8),(22,10),(25,20),(20,24),(8,23)],fill='#b3ad8b' if kind=='limestone' else '#687483')
        d.polygon([(8,14),(13,9),(19,10),(16,17)],fill='#e5dfbc' if kind=='limestone' else '#b4c0ca')
        d.line([(10,21),(18,19),(22,21)],fill='#817e66' if kind=='limestone' else '#3c475b')
        if kind=='tungsten':
            for x,y in [(11,16),(18,12),(20,21)]:d.rectangle((x,y,x+2,y+1),fill='#d1cee0')
    elif kind=='alloy':
        for y in (6,13,20):
            d.polygon([(3,y+2),(23,y),(28,y+3),(27,y+7),(4,y+8),(1,y+5)],fill=INK)
            d.line([(4,y+3),(24,y+1)],fill='#c4d1c8',width=2)
            d.line([(4,y+5),(24,y+4)],fill='#687e80',width=2)
            d.line([(8,y+2),(8,y+6)],fill=AMBER,width=2)
    elif kind=='glass':
        d.polygon([(5,7),(24,4),(27,24),(8,28)],fill=INK)
        d.polygon([(7,8),(23,6),(25,23),(9,26)],fill='#47656a')
        d.line([(8,9),(22,7),(24,22),(10,25),(8,9)],fill='#b7d6cd')
        d.line([(9,20),(20,9)],fill='#87b1b1',width=2)
        d.line([(16,22),(22,16)],fill='#a6ccc5',width=1)
    elif kind=='lock':
        d.arc((8,4,24,23),180,360,fill=STEEL,width=3)
        d.rectangle((6,14,26,28),fill=INK);d.rectangle((8,15,24,26),fill='#85794c')
        d.rectangle((15,19,17,23),fill=INK)
    elif kind=='check':
        line([(5,17),(12,24),(27,7)],'#aeb780',4)
    return im


def main():
    plate('plate.png');plate('plate_active.png',True);plate('plate_pressed.png',True,True)
    knob=Image.new('RGBA',(22,32)); kd=ImageDraw.Draw(knob)
    kd.rectangle((2,2,19,29),fill=INK)
    kd.rectangle((4,3,17,27),fill='#9d8759')
    kd.line([(4,3),(17,3),(17,27)],fill='#dfc68c')
    kd.line([(5,27),(16,27)],fill='#4f523e',width=2)
    for y in (9,13,17,21):kd.line([(7,y),(14,y)],fill='#414a3b')
    knob.save(ROOT/'slider_knob.png')
    kinds=['workshop','wall','fortress','rifle','shotgun','arcgun','boots','harness','craftsmanship','core','helmet','ammo','limestone','glass','lock','check','tungsten','alloy']
    atlas=Image.new('RGBA',(len(kinds)*32,32))
    for i,kind in enumerate(kinds):atlas.alpha_composite(icon(kind),(i*32,0))
    atlas.save(ROOT/'icons.png')
    font=ImageFont.truetype(str(ROOT.parent/'mono.ttf'),22)
    text='LETZTE SCHICHT'; box=font.getbbox(text)
    mask=Image.new('1',(box[2]+6,29)); d=ImageDraw.Draw(mask)
    d.text((3,-box[1]+3),text,font=font,fill=1,stroke_width=0)
    # Stencil cuts are deliberately sparse; main glyph shapes remain readable.
    for x in (25,50,91,135,157): d.line([(x,8),(x,10)],fill=0)
    word=Image.new('RGBA',mask.size)
    word.paste('#e4e1cb',(0,0),mask)
    word.resize((word.width*2,word.height*2),Image.Resampling.NEAREST).save(ROOT/'wordmark.png')


if __name__=='__main__': main()

#!/usr/bin/env python3
"""Build Bunkercrew's original pixel lettering (requires fontTools).

Every pattern below is original, editable grid artwork. Coordinates remain on a
square grid; there are no traced/borrowed font outlines, diagonal vectors, or
random erosion. Field includes genuine lowercase; Signal is the heavier stamped
companion. A grid square is 1 physical pixel at 14 px, 2 pixels at 28 px.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import unicodedata
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets/fonts/bunkercrew'
UNIT = 100
UPM = 1400
# '/' separates scan lines. Capitals occupy ten rows, x-height seven, descenders
# two. Narrow sidebearings and open apertures keep machine labels readable.
CAPS = {
'A': '.####./##..##/#....#/#....#/#....#/######/#....#/#....#/#....#/#....#',
'B': '#####./#....#/#....#/#....#/#####./#....#/#....#/#....#/#....#/#####.',
'C': '.#####/#...../#...../#...../#...../#...../#...../#...../#...../.#####',
'D': '#####./#....#/#....#/#....#/#....#/#....#/#....#/#....#/#....#/#####.',
'E': '######/#...../#...../#...../#####./#...../#...../#...../#...../######',
'F': '######/#...../#...../#...../#####./#...../#...../#...../#...../#.....',
'G': '.#####/#...../#...../#...../#...../#..###/#....#/#....#/#....#/.#####',
'H': '#....#/#....#/#....#/#....#/######/#....#/#....#/#....#/#....#/#....#',
'I': '###/.#./.#./.#./.#./.#./.#./.#./.#./###',
'J': '..####/.....#/.....#/.....#/.....#/.....#/.....#/#....#/#....#/.####.',
'K': '#....#/#...#./#...#./#..#../###.../#..#../#..#../#...#./#...#./#....#',
'L': '#...../#...../#...../#...../#...../#...../#...../#...../#...../######',
'M': '#.....#/##...##/#.#.#.#/#..#..#/#.....#/#.....#/#.....#/#.....#/#.....#/#.....#',
'N': '#....#/##...#/##...#/#.#..#/#.#..#/#..#.#/#..#.#/#...##/#...##/#....#',
'O': '.####./#....#/#....#/#....#/#....#/#....#/#....#/#....#/#....#/.####.',
'P': '#####./#....#/#....#/#....#/#....#/#####./#...../#...../#...../#.....',
'Q': '.####./#....#/#....#/#....#/#....#/#....#/#....#/#..#.#/#...#./.###.#',
'R': '#####./#....#/#....#/#....#/#....#/#####./#..#../#...#./#...#./#....#',
'S': '.#####/#...../#...../#...../.####./.....#/.....#/.....#/.....#/#####.',
'T': '#######/...#.../...#.../...#.../...#.../...#.../...#.../...#.../...#.../...#...',
'U': '#....#/#....#/#....#/#....#/#....#/#....#/#....#/#....#/#....#/.####.',
'V': '#.....#/#.....#/#.....#/#.....#/.#...#./.#...#./.#...#./..#.#../..#.#../...#...',
'W': '#.......#/#.......#/#...#...#/.#..#..#./.#..#..#./.#.#.#.#./.#.#.#.#./..#...#../..#...#../..#...#..',
'X': '#.....#/#.....#/.#...#./..#.#../...#.../...#.../..#.#../.#...#./#.....#/#.....#',
'Y': '#.....#/#.....#/.#...#./.#...#./..#.#../...#.../...#.../...#.../...#.../...#...',
'Z': '######/.....#/....#./....#./...#../..#.../..#.../.#..../#...../######',
}
LOWER = {
'a': '....../....../....../.####./.....#/.#####/#....#/#....#/#...##/.###.#',
'b': '#...../#...../#...../#.###./##...#/#....#/#....#/#....#/#....#/#####.',
'c': '....../....../....../.#####/#...../#...../#...../#...../#...../.#####',
'd': '.....#/.....#/.....#/.###.#/#...##/#....#/#....#/#....#/#....#/.#####',
'e': '....../....../....../.####./#....#/#....#/######/#...../#...../.#####',
'f': '..###/.#.../.#.../####./.#.../.#.../.#.../.#.../.#.../.#...',
'g': '....../....../....../.#####/#....#/#....#/#....#/#....#/#...##/.###.#/.....#/#####.',
'h': '#...../#...../#...../#.###./##...#/#....#/#....#/#....#/#....#/#....#',
'i': '#/././#/#/#/#/#/#/#',
'j': '..#/.../.../.##/..#/..#/..#/..#/..#/..#/..#/##.',
'k': '#...../#...../#...../#....#/#...#./#..#../###.../#..#../#...#./#....#',
'l': '##/.#/.#/.#/.#/.#/.#/.#/.#/.#',
'm': '........./........./........./##.##.##./#.#..#..#/#.#..#..#/#.#..#..#/#.#..#..#/#.#..#..#/#.#..#..#',
'n': '....../....../....../#.###./##...#/#....#/#....#/#....#/#....#/#....#',
'o': '....../....../....../.####./#....#/#....#/#....#/#....#/#....#/.####.',
'p': '....../....../....../#.###./##...#/#....#/#....#/#....#/#....#/#####./#...../#.....',
'q': '....../....../....../.###.#/#...##/#....#/#....#/#....#/#....#/.#####/.....#/.....#',
'r': '..../..../..../#.##/##../#.../#.../#.../#.../#...',
's': '....../....../....../.#####/#...../#...../.####./.....#/.....#/#####.',
't': '.#.../.#.../.#.../####./.#.../.#.../.#.../.#.../.#.../..###',
'u': '....../....../....../#....#/#....#/#....#/#....#/#....#/#...##/.###.#',
'v': '......./......./......./#.....#/#.....#/.#...#./.#...#./..#.#../..#.#../...#...',
'w': '........./........./........./#.......#/#...#...#/.#..#..#./.#.#.#.#./.#.#.#.#./..#...#../..#...#..',
'x': '....../....../....../#....#/.#..#./..##../..##../..##../.#..#./#....#',
'y': '....../....../....../#....#/#....#/#....#/#....#/#....#/#...##/.###.#/.....#/#####.',
'z': '....../....../....../######/.....#/....#./...#../..#.../.#..../######',
'ß': '.###../#...#./#...#./#..#../#.#.../#..##./#....#/#....#/#....#/#.###.',
'ẞ': '..####./.#....#/#.....#/#....#./#...#../#...##./#.....#/#.....#/#.....#/#..###.',
}
DIGITS = {
'0': '.####./#....#/#....#/#...##/#..#.#/#.#..#/##...#/#....#/#....#/.####.',
'1': '..#.../.##.../#.#.../..#.../..#.../..#.../..#.../..#.../..#.../#####.',
'2': '.####./#....#/.....#/.....#/....#./...#../..#.../.#..../#...../######',
'3': '#####./.....#/.....#/.....#/..###./.....#/.....#/.....#/#....#/.####.',
'4': '...##./..#.#./..#.#./.#..#./.#..#./#...#./######/....#./....#./....#.',
'5': '######/#...../#...../#...../#####./.....#/.....#/.....#/#....#/.####.',
'6': '..###./.#..../#...../#...../#####./#....#/#....#/#....#/#....#/.####.',
'7': '######/.....#/.....#/....#./....#./...#../...#../..#.../..#.../..#...',
'8': '.####./#....#/#....#/#....#/.####./#....#/#....#/#....#/#....#/.####.',
'9': '.####./#....#/#....#/#....#/#....#/.#####/.....#/.....#/....#./.###..',
}
# Symbols use the same ten-row origin; explicit rows leave vertical whitespace.
SYMBOLS = {
'.': '././././././././#/#', ',': '././././././././#/#/#',
':': './././#/././././#/.', ';': './././#/././././#/#/#',
'!': '#/#/#/#/#/#/#/./#/#', '?': '.####./#....#/.....#/.....#/....#./...#../..#.../....../..#.../..#...',
'-': '..../..../..../..../####/..../..../..../..../....',
'_': '....../....../....../....../....../....../....../....../....../######',
'+': '...../...../..#../..#../#####/..#../..#../...../...../.....',
'=': '...../...../...../#####/...../#####/...../...../...../.....',
'/': '....#/....#/...#./...#./..#../..#../.#.../.#.../#..../#....',
'\\': '#..../#..../.#.../.#.../..#../..#../...#./...#./....#/....#',
'(': '..#/.#./#../#../#../#../#../#../.#./..#',
')': '#../.#./..#/..#/..#/..#/..#/..#/.#./#..',
'[': '###/#../#../#../#../#../#../#../#../###',
']': '###/..#/..#/..#/..#/..#/..#/..#/..#/###',
'{': '..##/.#../.#../.#../#.../.#../.#../.#../.#../..##',
'}': '##../..#./..#./..#./...#/..#./..#./..#./..#./##..',
'|': '#/#/#/#/#/#/#/#/#/#',
'\'': '#/#/#/././././././.',
'"': '#.#/#.#/#.#/.../.../.../.../.../.../...',
'<': '..../..../...#/..#./.#../#.../.#../..#./...#/....',
'>': '..../..../#.../.#../..#./...#/..#./.#../#.../....',
'%': '##....#/#.#...#/.##..#./....#../...#.../...#.../..#..##/.#..#.#/#....##/#......',
'&': '.###../#...#./#...#./.#.#../..#.../.#.#.#/#...#./#...#./#...#./.###.#',
'@': '.#####./#.....#/#..##.#/#.#.#.#/#.#.#.#/#.#.#.#/#..###./#....../#....../.#####.',
'#': '.#..#./.#..#./######/.#..#./.#..#./######/.#..#./.#..#./....../......',
'$': '..#.../.#####/#.#.../#.#.../.####./..#..#/..#..#/#####./..#.../......',
'*': '...../#.#.#/.###./#####/.###./#.#.#/...../...../...../.....',
'~': '....../....../....../.##..#/#..##./....../....../....../....../......',
'^': '..#../.#.#./#...#/...../...../...../...../...../...../.....',
'`': '#./.#/../../../../../../../..',
'·': '.../.../.../.../.#./.../.../.../.../...',
'…': '......./......./......./......./......./......./......./......./#..#..#/#..#..#',
'–': '....../....../....../....../######/....../....../....../....../......',
'—': '........./........./........./........./#########/........./........./........./........./.........',
'×': '...../...../#...#/.#.#./..#../.#.#./#...#/...../...../.....',
'←': '......./......./...#.../..#..../.#...../#######/.#...../..#..../...#.../.......',
'→': '......./......./...#.../....#../.....#./#######/.....#./....#../...#.../.......',
'↓': '......./...#.../...#.../...#.../...#.../#..#..#/.#.#.#./..###../...#.../.......',
'↑': '......./...#.../..###../.#.#.#./#..#..#/...#.../...#.../...#.../...#.../.......',
'◇': '......./...#.../..#.#../.#...#./#.....#/.#...#./..#.#../...#.../......./.......',
'●': '......./..###../.#####./#######/#######/#######/.#####./..###../......./.......',
'✓': '......./......./......#/.....#./....#../#..#.../.##..../..#..../......./.......',
}


def pattern(value):
    rows = value.split('/')
    width = max(map(len, rows))
    return width, {(x, 9-y) for y, row in enumerate(rows) for x, pixel in enumerate(row) if pixel == '#'}


def designs():
    result = {char: pattern(value) for char, value in (CAPS | LOWER | DIGITS | SYMBOLS).items()}
    result[' '] = (3, set())
    result['\u00a0'] = result[' ']
    for char in '‘’':
        result[char] = result["'"]
    for char in '“”':
        result[char] = result['"']
    result['„'] = (3, {(x, y-8) for x, y in result['"'][1]})
    result['−'] = result['-']
    result['‹'] = result['<']
    result['›'] = result['>']
    result['°'] = pattern('.##./#..#/#..#/.##./..../..../..../..../..../....')
    result['€'] = pattern('..####/.#..../######/.#..../#####./.#..../.#..../.#..../..####/......')
    for code in range(192, 384):
        char = chr(code)
        base = unicodedata.normalize('NFD', char)
        if len(base) != 2 or base[0] not in result:
            continue
        width, pixels = result[base[0]]
        # Lowercase accent sits at cap height, cap accent above the capitals.
        top = 11 if base[0].isupper() else 8
        mid = width // 2
        marks = {
            '\u0308': {(max(0, mid-2), top), (min(width-1, mid+1), top)},
            '\u0301': {(mid, top), (mid+1, top+1)},
            '\u0300': {(mid, top), (mid-1, top+1)},
            '\u0302': {(mid-1, top), (mid, top+1), (mid+1, top)},
            '\u0303': {(mid-2, top), (mid-1, top+1), (mid, top+1), (mid+1, top), (mid+2, top+1)},
            '\u030a': {(mid-1, top), (mid, top+1), (mid+1, top), (mid, top-1)},
            '\u0327': {(mid, -1), (mid+1, -2), (mid, -3)},
            '\u030c': {(mid-1, top+1), (mid, top), (mid+1, top+1)},
        }
        if base[1] in marks:
            result[char] = (width, pixels | marks[base[1]])
    return result


def boundary_loops(cells):
    """Union filled square cells into contours; no internal rasterization seams."""
    edges = set()
    for x, y in cells:
        square = [(x,y), (x,y+1), (x+1,y+1), (x+1,y)]
        for a,b in zip(square, square[1:]+square[:1]):
            if (b,a) in edges:
                edges.remove((b,a))
            else:
                edges.add((a,b))
    loops = []
    while edges:
        start, nxt = min(edges)
        edges.remove((start, nxt))
        loop = [start, nxt]
        while nxt != start:
            candidates = sorted(b for a,b in edges if a == nxt)
            # At corner-touching cells prefer turning right, keeping independent
            # squares separate instead of creating self-intersecting contours.
            previous = loop[-2]
            dx,dy = nxt[0]-previous[0], nxt[1]-previous[1]
            best = min(candidates, key=lambda b: (-(dy*(b[0]-nxt[0])-dx*(b[1]-nxt[1])), b))
            edges.remove((nxt,best))
            loop.append(best)
            nxt = best
        loops.append(loop[:-1])
    return loops


def build_face(source, filename, family, style, medium=False, display=False):
    names = {char: f'uni{ord(char):04X}' for char in source}
    order = ['.notdef']+list(names.values())
    glyphs, metrics = {}, {}
    all_source = {'.notdef': pattern('######/#....#/#.#..#/#..#.#/#....#/#.#..#/#..#.#/#....#/#....#/######')}
    all_source.update({names[c]: design for c, design in source.items()})
    for name, (width,pixels) in all_source.items():
        # Quarter-square ink traps give Field a stable small-text weight. Signal
        # uses the heavier half-square grid; the authored stepped geometry stays
        # identical, while counters remain open when a 960px viewport shrinks it.
        subdivisions = 2 if display else 4
        cells = {(x*subdivisions+dx, y*subdivisions+dy) for x,y in pixels
                 for dx in range(subdivisions) for dy in range(subdivisions)}
        horizontal_gain = 1 if display or not medium else 2
        original = set(cells)
        for offset in range(1,horizontal_gain+1):
            cells |= {(x+offset,y) for x,y in original}
        cells |= {(x,y+1) for x,y in cells}
        if display:
            # Narrow stencil bridges are deliberate only for enclosed caps.
            char = next((c for c,n in names.items() if n == name), '')
            if char in 'BOPRDQ0689':
                center_y = 11 if char in 'BP68' else 9
                cells = {(x,y) for x,y in cells if not (y == center_y and x < 3)}
        step = UNIT//subdivisions
        pen = TTGlyphPen(None)
        for loop in boundary_loops(cells):
            pen.moveTo((loop[0][0]*step+50, loop[0][1]*step))
            for x,y in loop[1:]:
                pen.lineTo((x*step+50,y*step))
            pen.closePath()
        glyphs[name] = pen.glyph()
        # All numerals occupy the same cell width; strings such as timers never
        # jitter when the value changes. Lowercase remains proportional.
        metrics[name] = (width*UNIT+100+(50 if medium or display else 0), 50 if cells else 0)
    font = FontBuilder(UPM, isTTF=True)
    font.setupGlyphOrder(order)
    font.setupCharacterMap({ord(c): n for c,n in names.items()})
    font.setupGlyf(glyphs)
    font.setupHorizontalMetrics(metrics)
    font.setupHorizontalHeader(ascent=1200, descent=-300, lineGap=0)
    fullname = f'{family} {style}'
    font.setupNameTable({'familyName':family, 'styleName':style, 'uniqueFontIdentifier':f'{filename}-2.000',
        'fullName':fullname, 'psName':filename.removesuffix('.ttf'), 'version':'Version 2.000',
        'copyright':'Copyright 2026 Bunkercrew contributors. Original authored pixel outlines.',
        'licenseDescription':'SIL Open Font License, Version 1.1. No Reserved Font Names.',
        'licenseInfoURL':'https://openfontlicense.org'})
    bold = display
    font.setupOS2(sTypoAscender=1200, sTypoDescender=-300, sTypoLineGap=0,
        usWinAscent=1300, usWinDescent=300, sxHeight=700, sCapHeight=1000,
        usWeightClass=700 if bold else 500 if medium else 400, usWidthClass=5,
        fsSelection=0x20 if bold else 0x40)
    font.setupPost()
    font.setupMaxp()
    font.font['head'].macStyle = 1 if bold else 0
    font.font['head'].created = font.font['head'].modified = 3873744000
    font.font.recalcTimestamp = False
    path = DEST/filename
    font.save(path)
    metadata = {'name':fullname, 'version':'2.000', 'type':'original pixel outline font',
        'generator':'tools/generate_bunkercrew_font.py',
        'source':'Original authored grid patterns in generator; no third-party or traced font outlines.',
        'license':'SIL Open Font License 1.1', 'license_file':'OFL.txt', 'reserved_font_names':[],
        'design':'Industrial proportional pixel lettering, distinct lowercase, open counters, aligned digits. '
            + ('Half-cell stencil bridges in enclosed display capitals.' if display else 'Field equipment lettering.'),
        'grid_units':100, 'units_per_em':UPM, 'native_sizes':[14,28,42,56],
        'rendering':('Nearest bitmap for large display type' if display else '112px MSDF atlas with 4px range preserves small grid contours at fractional scales'),
        'glyph_count':len(glyphs), 'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    path.with_suffix('.ttf.source.json').write_text(json.dumps(metadata,indent=2)+'\n')
    print(f'Built {filename}: {len(glyphs)} glyphs')
    import_path = path.with_suffix('.ttf.import')
    if import_path.exists():
        import re
        settings = {'antialiasing':'0' if display else '1',
                    'multichannel_signed_distance_field':'false' if display else 'true',
                    'msdf_size':'112', 'msdf_pixel_range':'4', 'hinting':'0',
                    'subpixel_positioning':'0', 'oversampling':'1.0' if display else '0.0',
                    'allow_system_fallback':'false'}
        imported = import_path.read_text()
        for key,value in settings.items():
            imported = re.sub(r'^'+key+r'=.*$', key+'='+value, imported, flags=re.MULTILINE)
        import_path.write_text(imported)


def main():
    DEST.mkdir(parents=True,exist_ok=True)
    source = designs()
    build_face(source,'BunkercrewField-Regular.ttf','Bunkercrew Field','Regular')
    build_face(source,'BunkercrewField-Medium.ttf','Bunkercrew Field','Medium',medium=True)
    build_face(source,'BunkercrewSignal-Bold.ttf','Bunkercrew Signal','Bold',display=True)
    for role,filename in [('body','BunkercrewField-Regular.ttf'),('menu','BunkercrewField-Medium.ttf'),('title','BunkercrewSignal-Bold.ttf')]:
        (DEST/f'{role}.tres').write_text('[gd_resource type="FontVariation" load_steps=3 format=3]\n\n'
            f'[ext_resource type="FontFile" path="res://assets/fonts/bunkercrew/{filename}" id="1"]\n'
            '[ext_resource type="FontFile" path="res://assets/mono.ttf" id="2"]\n\n'
            '[resource]\nbase_font = ExtResource("1")\nfallbacks = [ExtResource("2")]\n')

if __name__ == '__main__':
    main()

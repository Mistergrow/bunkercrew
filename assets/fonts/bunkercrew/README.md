# Bunkercrew Field / Signal

Original industrial pixel lettering for the game. All outlines come from the
editable grid patterns in `tools/generate_bunkercrew_font.py`; no existing font
was renamed, traced, or modified.

| Face | Use | Shared resource |
| --- | --- | --- |
| Field Regular | Sentences, HUD values, world labels | `body.tres` / `UiArt.FONT` |
| Field Medium | Main menu actions and location titles | `menu.tres` / `UiArt.MENU_FONT` |
| Signal Bold | Wordmark and short display headings | `title.tres` / `UiArt.TITLE_FONT` |

Each face has 239 glyphs, including distinct lowercase, German umlauts, `ß` and
`ẞ`, aligned numerals, punctuation, arrows, and every character currently used in
the German and English locale files. A separately licensed existing mono face is
the fallback for characters outside this set. All three faces remain original
pixel outlines; letters do not switch to a smooth office font in translated copy.

The design uses 10-square capitals and 7-square lowercase. One design square
equals one pixel at 14 px; small-text stems have a quarter-square weight allowance.
Use 14–16 px for primary copy and 28 px for menu actions. Existing 11–13 px helper
labels are supported, including at the minimum 960×600 window size. Use Signal
only for short display labels from 28 px upwards. Do not stretch text horizontally
or add fake outlines and shadows.

Field uses a 112 px distance-field atlas with a narrow 4 px range. This preserves
its authored square contours while retaining thin rows at fractional viewport
scales; nearest-only rasterization drops rows when the 1440-wide UI shrinks to
960. Signal uses nearest bitmap rendering for large, crisp display lettering.
Automatic hinting and subpixel positioning stay off for both families. The native
research preview checks actual game controls at 960, 1440, and 2560 pixels; the
comparison captures are in `artifacts/bunkercrew-typography/raster-comparison/`.
Adjacent provenance JSON files record generator, license, render policy, and hashes.

Regenerate, import, and inspect the real Godot specimen:

```bash
python tools/generate_bunkercrew_font.py
godot --headless --path . --editor --import --quit
godot --path . --script tests/bunkercrew_typography_preview.gd -- --no-profile-save
```

The generator requires `fontTools` and fixes its font timestamp for reproducible
output. It preserves the tested per-face import settings when rebuilding existing fonts. The
specimen checks native glyph coverage and rendering settings, then captures
1440×900 and 2560×1440 views in `artifacts/bunkercrew-typography/` without loading
or changing player data. The outlines are released under SIL Open Font License
1.1 with no reserved font names; see `OFL.txt`.

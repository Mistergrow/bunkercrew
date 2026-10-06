# Main menu design

The menu uses the game's actual animated landscapes and worker art. The left side has a short text menu; three available workers and three anonymous missing slots sit below it. A rescued character reveals its identity through the local roster. No selection card or tooltip exposes an undiscovered recruit's name, equipment, traits, or location.

## Reference decisions

| Observed principle | Application in Bunkercrew | Tradeoff |
| --- | --- | --- |
| Factorio describes showing real game scenes behind its menu, with a fixed visual focus and an edge vignette. [Friday Facts #362](https://factorio.com/blog/post/fff-362) | Reuse the authored world, layered clouds, water, smoke, lighting and vegetation; softly darken the navigation side. | The landscape runs without enemies or economy simulation. Presentation updates are capped at 30 Hz, or 12 Hz with reduced effects. |
| Factorio's GUI discussion favours restrained presentation that keeps attention on relevant elements. [Friday Facts #238](https://factorio.com/blog/post/fff-238) | Remove the metal panel grid and framed preview. Native transparent buttons have a narrow amber focus marker. Keep mode descriptions contextual. | The menu has less decorative machinery; the visible world supplies the game's material and colour. |
| Dead Cells' accessibility update reorganises options and adds ways to improve readability and control. [Update 29](https://deadcells.com/patchnotes/29) | Keep Options directly reachable, retain keyboard/controller navigation, show focus independently of hover, and keep German/English selection visible. | This change preserves the existing options screen and its settings; it does not claim a complete accessibility audit. |

Continue appears first and receives focus when a campaign checkpoint exists. Choosing a landscape only changes the presentation; it never silently changes the next match's settings. Starting a mode still goes through the existing scenario and crew setup.

## Typography

The interface embeds three original static Barlow faces locally. Barlow takes its shapes from transport signs, plates and public infrastructure; its narrow proportions fit the industrial setting without distressed lettering or additional frames. [Official Barlow project](https://github.com/jpt/barlow)

- `UiArt.FONT`: Barlow Semi Condensed Medium, shared by text rendering, wrapping, controls and width measurements throughout the HUD and panels.
- `UiArt.MENU_FONT`: Barlow Condensed SemiBold for larger menu choices and location names.
- `UiArt.TITLE_FONT`: Barlow Condensed Bold for the left-aligned BUNKERCREW wordmark. Its size fits the available width without stretching letters.

Menu instructions and roster names use larger sizes than the previous monospace layout. Font imports use MSDF scaling for both 2560×1440 and 960×600; the scene artwork retains its pixel filtering. Embedded faces include German umlauts, ß and menu punctuation. A bundled fallback supplies the six arrow/status symbols absent from Barlow, so these controls also work without system fonts. The untouched font files, pinned source URLs and SHA-256 hashes are in `assets/fonts/barlow/`; `OFL.txt` ships with future beta exports.

## Validation

### World composition

All twelve campaign panoramas and Sector 07 have individual menu camera framing
in `menu_composition.gd`. The radar dish, freighter bridge, quarry excavator and
factory gate are placed in the open right side. The dam uses a closer view of
the spillways. Horizontal feathered image edges stay outside the viewport.
Gameplay floor props are hidden in this presentation: the original painted
foreground grounds each landscape without trees floating over water or valleys.

`menu_cloud_composition.gd` uses the existing cloud atlas with different heights,
sizes, spacing, phases and opacity for each climate. All three layers retain
their wind, shape animation and landmark occlusion. `menu_landmark_catalog.gd`
locates additional effects on the source art: lamps and beacons, spillway water,
ivy light, localized dust and steam. Existing painted exhaust receives a slowly
rising brightness variation within its own silhouette. These effects use preview time and
support reduced effects; they do not run machinery or alter campaign state.

`tests/menu_world_gallery.gd` captures all thirteen locations at 2560×1440 and
960×600 in both languages. `tests/menu_cloud_composition_test.gd` checks cloud
continuity at tile boundaries and after reversing wind. `tests/menu_landmarks_test.gd`
compares rendered local effects with the untouched source and different times.
The gallery uses disposable prepared menu states with `--no-profile-save`.

### Earlier menu and typography checks

`tests/main_menu_test.gd` exercises actual keyboard, controller and menu routes. `tests/main_menu_redesign_preview.gd` checks translated native controls at 2560×1440 and 960×600, then captures both languages, bright and dark environments, and a prepared Continue state without reading or writing player progress. `tests/crew_recruits_preview.gd` covers anonymous and rescued roster states in selection and the co-op lobby.

The typography change passed 662 menu checks (including native glyph coverage and actual button-font measurement), 21 compact HUD checks, and 71 localization/UI checks with 14 actual QHD captures. These are prepared menu/gameplay states, not a completed campaign. Screenshots are under `artifacts/expedition/menu/` and `artifacts/localization-ui/`.

## Full location review

`tests/menu_world_gallery.gd` captures all 13 preview locations (the 12 campaign sites plus Sector 07) in German and English at native 2560×1440 and 960×600. The final 52-view run passed 210 checks covering complete viewport coverage, translated title/control widths, image dimensions and an untouched paused match. `artifacts/menu-world-gallery/index.html` filters the images by language and resolution; its adjacent JSON records the prepared state and presentation clocks.

Visual review covered every German QHD location and the small-screen contrast/framing cases in both languages. The harbor bridge, radar dish, refinery towers and megafactory gate are now visible in their own compositions; the steelworks water tower keeps a margin from the right edge. Gameplay-floor vegetation no longer floats over the harbor, reservoir or mountain valley. Soft local shading supports language controls and location labels over snow, water and pale skies without adding frames.

Run the gallery with `godot --path . --script tests/menu_world_gallery.gd -- --no-profile-save`. For a focused follow-up, append `--only=sector07,overgrown_steelworks`; this replaces just those captures and retains the other review entries. All captures use the real paused menu and a disposable roster, without changing player profiles.

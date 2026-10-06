# Score and sound bank

Music, base effects and movement use original procedural
synthesis. Reload revision 2 uses attributed CC0 mechanical recordings; see
`source_recordings/weapon_reload/README.md` and `weapon_sources.json`. No paid
generative-audio services are used.

## Regeneration

Run `python3 tools/generate_audio_expansion.py` from the repository. It requires
NumPy, SciPy, and ffmpeg with libvorbis. It writes 50 mono 32 kHz WAV effects and
six stereo music arrangements. The original `music_calm.ogg` and
`music_combat.ogg` are preserved byte for byte.

`python3 tools/generate_audio.py` rebuilds the original score first, then runs
the expansion, movement, and weapon generators. This is the complete-bank regeneration
command. The expansion entry point preserves the original OGG bytes; the
movement entry point preserves all existing score and gameplay-effect assets.

## Composition and playback

Each new set lasts exactly 48 seconds: 16 bars at 80 BPM. Within a set, the
combat recording contains the same calm recording at the same gain and sample
position, plus rhythmic layers. Keep both arrangements synchronized and use a
linear crossfade; an equal-power blend would raise the shared score's level.

- `foundry`: D minor; bowed low strings, muted felt motif, metal ostinato.
- `tidal`: E minor with Dorian inflections; plucked strings, open chords, brushes.
- `frost`: B minor; soft choir-like pads, struck glass, restrained toms.

Notes and room reflections wrap around the loop boundary. PCM generation is
seeded and deterministic; Vorbis container serials may differ between encodes.
`sources.json` records composition, seeds, original-file checksums, and mix data.

The 29 existing effect filenames remain available with revised transients, body,
resonances, and short reflections. New families have three variants each:
`shotgun`, `cannon`, `arc`, `impact_metal`, `impact_stone`, `impact_wood`, and
`glass_break`. Filenames use `<family>_01.wav` through `<family>_03.wav`.

## Footsteps and wind

### Enemy classes and research confirmations

`python3 tools/generate_enemy_tech_audio.py` builds 160 mono enemy contacts and
12 stereo research confirmations as 48 kHz PCM16 WAV files. Eight chassis/boot
families cover all 18 walking ground enemy classes; each has five recorded-foley
variants on dry ground, steel, packed snow/ice and shallow water. Wheels and
aircraft retain their existing movement behavior. Class contacts use the existing
four spatial footstep voices, shuffle without adjacent repeats, and leave player
footsteps protected from enemy voice stealing.

Research has distinct sounds for Basis, Waffen, Besatzung and Fahrzeug, with
three variants per branch. Successful purchases emit their branch cue through
the existing replicated sound event. A separate two-voice UI pool plays on SFX
while the tech screen pauses the world, without room occlusion or paused-room
muting. Failed purchases do not emit confirmations; the SFX slider also mutes
these sounds. These are layered recorded foley and original synthesis, not AI
audio-model output.

Recorded layers come from [Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds),
licensed CC0. Original downloads, the included license and file hashes are in
`source_recordings/enemy_foley/`; processing, class mappings and output hashes
are in `enemy_tech_sources.json`. The generator preserves every pre-existing
WAV/OGG file and is included in the full `generate_audio.py` entry point.

Run `python3 tests/enemy_tech_audio_assets_test.py` for signal checks and the
listening gallery at `artifacts/enemy-tech-audio/index.html`. Run
`godot --headless --audio-driver Dummy --path . --script tests/enemy_tech_audio_test.gd -- --no-profile-save --no-upnp`
with isolated `XDG_DATA_HOME` for contact routing, actual purchase events,
paused mixer capture and cleanup validation.

`python3 tools/generate_movement_audio.py` writes 15 additional mono 32 kHz
contact effects: three each for `step_dry`, `step_metal`, `step_water`,
`step_ice`, and `step_heavy`. They last 0.25–0.39 seconds and combine short
heel/toe contacts with material-specific friction and resonances. Water denotes
a shallow puddle; the heavy contact is a damped machine foot.

`ambience_wind.ogg` is a 16-second stereo 32 kHz loop of filtered noise and
periodic gust envelopes. It has no melody. Its spectrum and modulation wrap
through the loop boundary without a silent gap. Seeds, synthesis parameters,
and checksums protecting the existing bank are in `movement_sources.json`.

`python3 tests/movement_audio_assets_test.py` checks the decoded movement bank,
regenerates all contact PCM for comparison, and writes a separate
[listening gallery](../../artifacts/movement-effects/audio.html). The score and
gameplay bank retains its separate `sources.json` and validation command below.

## Validation and review

### Aircraft, production and medical contacts

The generator tools/generate_aircraft_audio.py creates six eight-second mono
48 kHz aircraft engine loops and 22 weapon, warning and crash variations.
Rotor, piston propeller, tiltrotor, jet, airship and heavy VTOL sources are
mapped to all twelve aircraft in scripts/aircraft_audio_catalog.gd.
Periodic carriers and circular airflow textures avoid a faded gap at the loop
boundary. Sources contain no baked stereo pan; the local game listener supplies it.

The generator tools/generate_machinery_medical_audio.py creates two eight-second
working loops for the mixer and furnace, plus four short treatment/revive
contacts. Machines sound only while production actually runs. The medical
contacts replace the existing construction cue at a successful treatment;
they do not introduce a second event or voice line.

These 34 recordings are deterministic originals with adjacent source JSON,
generator/file hashes and license files. Distribution is permitted only
together with Bunkercrew. Existing CC0 recording rights remain unchanged.
Both generators preserve all 685 prior WAV/OGG bytes; the good music and
dialogue recordings are retained.

Run python3 tests/aircraft_machinery_audio_assets_test.py for exact PCM
reproduction, headroom, DC, loop, variation, provenance and preservation
checks. The listening bank is artifacts/audio-air-review/assets/index.html.
Run python3 tools/audit_audio_assets.py to decode every repository WAV/OGG and
record measured loudness, clipping, silence, loop edges, usage and export
status in artifacts/audio-air-review/assets/sound-manifest.json.
Its 50-percent column is a dry source/bus estimate; actual spatial and combined
mix captures are linked separately in the review gallery. User sliders and
saved music/voice preferences remain unchanged.

### Weapon handling

`python3 tools/generate_weapon_audio.py` adds 51 mono 32 kHz PCM16
recordings. Rifle, shotgun, arc rifle, roof cannon and flak each have three
opening, feeding and closing variations: `reload_<family>_<phase>_01.wav`
through `_03.wav`. `weapon_mount` and `weapon_switch` each add three handling
variations. The 45 reload phases are regenerated from CC0 airsoft and magazine recordings
by SpringySpringo and Brian MacIntosh, using documented cuts and dry contact
layering without synthesized pitch sweeps. Mount/switch retain their original
procedural synthesis. `weapon_sources.json` records source URLs, licenses,
hashes and deterministic editing parameters.

Normal reload logic plays opening at acceptance, feeding at 48% elapsed and
closing after ammunition transfers. Cancelling a handheld reload suppresses its
remaining cues. Spatial sound events carry all three phases to the other player.
The existing twelve-voice pool and sound-volume control apply to these effects.
Reloads have priority over ordinary combat effects and briefly lower nearby music.
Music has an internal −8 dB trim without changing saved slider values; cannon
reports gain 6 dB and handling gains 5 dB relative to the previous mix.


Run `python3 tests/weapon_audio_assets_test.py` for PCM reproducibility, variation,
peak, spectrum and preservation checks. `tests/weapon_reload_audio_test.gd`
uses actual weapons, protocol-decoded events and the Dummy audio driver to capture
the real mixer without speaker output. The [weapon review gallery](../../artifacts/weapon-audio/index.html)
contains source phases and complete runtime reload recordings. Existing reload
durations and ammunition costs remain unchanged.

Run `python3 tests/audio_assets_test.py`. It decodes the shipped files, measures
peaks and DC, checks loop lengths and edge steps, compares variations, and checks
one regenerated effect against its shipped PCM. It writes measurements and an
[audio gallery](../../artifacts/audio-refresh/index.html).

These are signal checks, not a listening assessment. The preserved original
combat track has DC below 0.001; the new bank must remain below 0.0002. Fourfold
oversampling checks reconstruction peaks but is not a certified true-peak meter.

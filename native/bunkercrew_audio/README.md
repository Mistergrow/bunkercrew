# Bunkercrew native live music

This GDExtension links the supplied first-party Tessel engine directly into
Godot 4.7.2's audio mixer. JUCE is not a build or runtime dependency of the game.
Godot C++ bindings use the pinned official revision recorded in
`third_party/godot-cpp/SOURCE.json`, generated from this project's actual 4.7.2 API.

For public path-neutral rebuilds, use [PATH_NEUTRAL_BUILD.md](PATH_NEUTRAL_BUILD.md).
The existing development builder below does not add publication prefix maps.

Build Linux and Windows x86_64 for development, with the default two-hour verification:

```sh
python3 tools/build_live_music.py --platform all --verify --jobs 4
```

The script installs both libraries into `assets/audio/live`, checks native C++
transport/DSP behavior, renders 7,200 seconds at 48 kHz across all four genres,
checks 64 phrase variants per test profile, and measures EBU R128 integrated
loudness and true peak for 52 world/genre settings. It also creates 64 distinct
16-bar listening clips (all 13 defaults and all four Aschewerk styles) and a
640-second Aschewerk audio simulation. `--skip-verification` is an explicit
local-development shortcut and must not be used for beta release validation.
`--sample-seconds 640` renders extended listening material. Generated material is
not a claim that a person has listened to and approved it.

Windows builds use installed MinGW or extract Ubuntu MinGW packages into the
user cache. No elevated installation is required. `BUNKERCREW_GODOT_CPP` and
`BUNKERCREW_MINGW_ROOT` can select existing dependency locations. CMake outputs
are inside `.gdignore` so Godot does not import compiler intermediates.

## GDScript API

Instantiate `TesselStream`, call `set_theme(seed, settings)` before assigning it
to an `AudioStreamPlayer`, and start playback. `TesselPlayback` implements the
native `_mix()` virtual and contains only preallocated DSP buffers and a shared
native session. Both classes expose:

- `set_intensity(0..3)`: request the next 8- or 16-bar phrase boundary.
- `request_intensity_at_bar(level, bar)`: deterministic replicated request;
  adoption happens at the first phrase boundary at or after `bar`.
- `request_interlude(kind, sample)`: next-beat cue, `boss`, `victory`, `loss`.
- `seek_samples(sample)`: integer sample transport alignment for late joins.
- `poll_events(max_events=256)`: drain a bounded event ring and refill phrase
  snapshots on the main thread. Keep polling every rendered frame.
- `mixed_samples()`, `bpm()`, `beats_per_bar()`, `mix_rate()`, `metadata()`.
- `current_intensity()`: current mixer arrangement without constructing metadata.

The optional `initial_intensity` setting initializes a late join's current
arrangement before playback starts. Publish any separate future
`request_intensity_at_bar()` before starting that playback as well, so a guest
joining during combat retains combat until the host's scheduled quiet phrase.
Omitting the initial setting starts at intensity 0.

A seek or same-core restart invalidates queued phrase banks and events from
the previous transport generation. The audio consumer returns old bank slots;
the main-thread `poll_events()` composes snapshots for the new target phrase.
Until that refill completes, the mixer outputs silence and holds the integer
sample position at the target. It emits no obsolete pattern hits or synthetic
clock events during that wait. Continue polling once per rendered frame.
An ordinary first `start(0)` reuses its precompiled opening without a silent
block; normal phrase transitions keep their existing prepared-bank behavior.
Adaptive rewinds before a pending intensity command restore `initial_intensity`,
while jumps beyond that command adopt its requested bank.

`composition_version` defaults to 1 for existing themes. The nine revised
minimal-techno world scores opt into version 2: shorter tuned kicks, gated
offbeat sub-bass, a sustained lead motif, rounded analogue hooks and phrase
relief. `melody_level` controls the version-2 lead. `score_form` defaults to 0
for gameplay-driven intensity; form 1 authors Kernimpuls as four eight-bar
sections (intro 0, build 1, drop 2, relief 1). Original menu recordings and
explicitly selected other genres retain their previous compositions. Sources,
paired recording masters and the actual mixer checks are available in
`artifacts/music-beat-refresh`.

Each event carries `sample`, `track`, `strength`, `bar`, `beat`, `accent`, and
`kind` (`hit`, `beat`, `bar`, `phrase`, `interlude`). Events are timestamps in the
mixed sample timeline; visuals subtract local audio output latency and user
calibration. The limiter has no lookahead and introduces no additional sample
delay. Beat grid events use the nearest integer sample. Sort events by sample
before dispatching because a block can contain several kinds at the same time.

A theme's tempo, key, motif and seed remain constant for a session. Scale codes
are 0 minor pentatonic, 1 major pentatonic, 2 Dorian and 3 Phrygian. Motifs use
scale degrees. Profiles and their semitone-to-degree conversion live in
`scripts/music_theme_catalog.gd`. Changing the theme creates a new stream core;
an existing playback retains its original immutable theme until stopped.

Genre setting codes are 0 Minimal Techno, 1 Schranz, 2 Hip-Hop/boom-bap and
3 Breakbeat. Minimal Techno and Schranz keep a quarter-note kick foundation once
the groove starts. Schranz adds a faster driven kick, Reese weight and industrial
sixteenths. Hip-Hop uses a broken kick grid, backbeat snare, swung eighths and
longer bass notes; Breakbeat combines syncopated kicks, snare ghosts and tighter
sixteenths. Tempo and instrument colour come from the world/genre catalog.

Intensity 0 carries a slow, connected lead motif over a quiet bass/room bed.
Intensity 1 brings in a softer groove while continuing the lead; intensities 2
and 3 foreground kick and bass with sparse short synth stabs and phrase fills.
Transitions occur on 8/16-bar boundaries and retain released voice/effect tails.
The motif's key and seed remain shared between styles. This is instrumental
procedural composition, with no sampled vocals or rap performance.

## Thread ownership

`LiveMusic::compose`, Pattern vectors, `compile`, phrase preview production,
Godot arrays and dictionaries all run on the main thread. Three prepared phrase
banks cover roughly 40–135 seconds across the configured tempos. Audio ownership transfers through fixed
SPSC index rings; banks are never freed on the audio thread. A fixed 8,192-entry
SPSC event ring never blocks. If a consumer stalls beyond its capacity, overflow
is counted and sound continues. Audio processing uses no allocation or locks,
and intensity plus target bar is published as one lock-free atomic value.

The supplied engine also keeps its bounded `PatternQueue` for standalone Tessel.
`DrumEngine::setPattern` quantizes adoption to a bar by default, preserves effects
and voice tails, forwards Reese bass controls, and computes probability choices
from seed, absolute bar and hit position. Explicit transport reset remains a
separate operation. The native arranger schedules engine adoption only at whole
phrase boundaries. A late join can reset local effect history; its subsequent
notes and shared piece remain deterministic while local output timing is its own.

The mix preserves intentional quieter phrases. A measured per-world/genre gain and sample
limiter reserve target approximately -16.5 LUFS over an arrangement while leaving
true peak headroom; per-profile measurements are in
`artifacts/live-music/native-verification.json`. The game's Music bus, user volume
and dialogue ducking own listening level. Rhythm does not modify movement,
shots, enemies or hit timing.

Version-2 recorded calm/combat pairs use a common mastering gain. Combat masters
measure about -16.45 LUFS; calm masters retain their quieter dynamics at
-19.14 to -18.47 LUFS. Their true peaks remain below -3.52 dBTP. The corresponding
source settings, PCM and event markers are preserved beside the generated
assets; `artifacts/music-beat-refresh/asset-verification.json` records decode,
duration, seam and original-menu preservation checks.

## Licenses and provenance

Tessel is licensed for use and distribution only together with Bunkercrew under
the rights-holder authorization for this task. See `third_party/tessel/LICENSE`.
Godot C++ remains MIT; its complete upstream notice is preserved in
`third_party/godot-cpp/LICENSE.md`. No JUCE source or binary is linked or shipped.
Source revision, API checksum and binary hashes are recorded beside the assets.

Linux and Windows event-timing/PCM comparisons are recorded in
`artifacts/live-music/cross-platform.json`. Platform math libraries can produce
small waveform differences; no cross-platform bit-identical floating point
waveform claim is made.

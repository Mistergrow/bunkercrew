# Licenses and asset provenance

The project code license does not relicense third-party code or game assets.
Keep the notices below and adjacent metadata with distributions.

| Component | Recorded terms / evidence |
| --- | --- |
| Godot engine | MIT and bundled dependency notices; binary distributions must retain Godot's engine/dependency notices |
| godot-cpp integration | MIT; `native/bunkercrew_audio/third_party/godot-cpp/LICENSE.md` and `SOURCE.json` |
| Audiote / Tessel | Redistribution solely as part of Bunkercrew, including source/build tooling; `native/bunkercrew_audio/third_party/tessel/LICENSE` and `SOURCE.json` |
| Windows compiler runtime | Retain `native/bunkercrew_audio/third_party/mingw-w64/NOTICE` and `GCC-NOTICE` |
| DejaVu Sans Mono Bold | `assets/font-license.txt`; source recorded in `assets/sources.json` |
| Noto Sans, Barlow and original Bunkercrew fonts | SIL Open Font License 1.1; each font directory includes `OFL.txt` and source metadata |
| Kenney Impact Sounds and edited impact effects | CC0-1.0; `assets/audio/enemy_tech_sources.json`, adjacent licenses and source recordings |
| SpringySpringo and Brian MacIntosh reload recordings | CC0-1.0; `assets/audio/source_recordings/weapon_reload/README.md`, source pages and metadata |
| Synthetic dialogue | Qwen3-TTS generation documented in `assets/audio/story_voices/` and `story_voices_v2/`; model Apache-2.0 notices are retained; models are not shipped |
| godot_mcp editor addon | Its own license in `addons/godot_mcp/LICENSE`; optional editor tooling |
| Original generated / procedural art and audio | Source metadata in `assets/sources.json` and adjacent source JSON; any Bunkercrew-only notices remain binding |

Generated images are recorded as project-generated output; this documentation
makes no independent copyright assertion about model output. It does not assign
an invented third-party license or override existing distribution restrictions.
Reference images under `reference/` are reference-only and excluded.

## Privacy-neutral provenance

Repository files use repository-relative paths. Historical files outside the
repository use `local-archive:` identifiers: these retain original generation
IDs and filenames without disclosing a username or machine path. They identify
external local archives, not files included in this repository. Prompts,
processing descriptions, hashes, source URLs and existing rights statements
are preserved. No original image, font or recording is modified by this cleanup.

# Repository Guidelines

## Project Structure & Module Organization

Bunkercrew is a Godot 4.7.2 bunker defense game using GDScript and the Compatibility renderer.

- `project.godot` opens the project; `scenes/main.tscn` starts `scripts/game.gd`.
- `scripts/` contains gameplay, UI, and drawing code; `scenes/` contains reusable `.tscn` entities. Keep shared balance values in `scripts/config.gd` and feature data in the relevant `*_catalog.gd`.
- `assets/` holds textures, fonts, audio, generators, and source metadata; `shaders/` holds visual shaders. `tools/generate_audio.py` generates audio.
- `tests/` contains regression scripts, integration runs, and visual galleries. `artifacts/` stores captures and logs; `reference/` holds art references; `beta/` contains versioned Ubuntu and Windows packages.

## Build, Test, and Development Commands

Run from the repository root with Godot 4.7.2:

```bash
# Import resources and check editor loading
godot --headless --path . --editor --import --quit
# Launch the game; requires a graphical display
godot --path .
# Run a targeted regression test without saving player progress
godot --headless --path . --script tests/scenario_selection_test.gd -- --no-profile-save
# Capture rendered scenario views; requires a graphical display
godot --path . --script tests/scenario_selection_test.gd -- --no-profile-save --capture
# Build Windows release; requires matching export templates
godot --headless --path . --export-release "Windows Desktop" "beta/Bunkercrew.exe"
```

## Coding Style & Naming Conventions

Use tabs for GDScript indentation. Follow existing `snake_case` filenames, functions, and variables, `PascalCase` class names, and `UPPER_SNAKE_CASE` constants. Prefix internal helpers with `_`; use explicit types where practical. Use English code identifiers. Keep player-facing messages in both `locales/de.json` and `locales/en.json`; translate before formatting and measuring text with `LocaleText`. No formatter or linter is configured; match nearby code and avoid unrelated reformatting.

## Testing Guidelines

Tests use standalone `SceneTree` scripts and Python integration drivers with nonzero exit codes on failure. Name GDScript regressions `<feature>_test.gd`. Run affected tests; add coverage for behavior changes. Network tests use `--no-upnp` and separate processes. No coverage threshold is configured. Use `tests/scene_cleanup.gd` for teardown. For visual changes, run relevant galleries or previews and inspect captures. Record prepared scene states when reporting results.

## Commit & Pull Request Guidelines

This copy has no Git metadata, so historical commit conventions cannot be verified. Use short imperative subjects, such as `Fix ladder exit collision`. Keep changes focused. PRs should describe behavior changes, link relevant issues, list validation commands and results, and include screenshots for visual changes. Update `README.md` when controls or gameplay change.

## Assets & Generated Files

Preserve asset provenance in adjacent source JSON files and licenses. Keep `.godot/`, temporary files, and generated logs out of commits, following `.gitignore`.

## Version and Changelog Maintenance

Before completing a visible behavior or content improvement, raise the release version explicitly with `tools/bump_version.py` and record the milestone, German/English changes, and validation evidence. `application/config/version` in `project.godot` is the single release source; maintain the generated `CHANGELOG.md` and shipped `assets/releases/changelog.json` with that tool. Do not bump versions at runtime or modify archived packages. Network protocol and world compatibility versions remain separate and change only when their contracts require it. A development milestone does not establish Beta 0.5 acceptance; keep unperformed play, platform, Internet, and performance checks explicit.

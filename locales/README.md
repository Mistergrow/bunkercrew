# Localization

`de.json` and `en.json` are the authoritative catalogs. Both use the complete German source message as the same stable key. German values equal their keys; English values contain the translation. Keep machine IDs, resource paths, input actions, save data and network fields unchanged.

## Display APIs

```gdscript
LocaleText.text("Material aufnehmen")
LocaleText.format("%s ×%d aufnehmen · antippen", [material_name, amount])
LocaleText.data(display_record)
```

- `text(source)` resolves the current language. Uppercase and capitalized display forms are supported, as are previously translated catalog values.
- `format(source, values)` translates the complete template and string arguments before interpolation. Preserve placeholder count, order and types in both catalogs. Use `%%` for a literal percent sign inside a formatted message. Ordinary descriptions such as `6 % eigener Schaden` need no escaping.
- `data(value)` returns translated strings, arrays or dictionary values while preserving dictionary keys and designated ID/path fields. Keep shared catalogs and gameplay state in their original form; translate their display getters.
- `set_locale("en")` or `set_locale("de")` changes the local preference. `current_locale()` reads it. The preference is stored in `user://language.cfg`; `--no-profile-save` prevents normal test runs from writing it.
- The `Localization.locale_changed(locale)` signal refreshes native controls. Drawn labels use `Art.text`/`UiArt.text`; translate before measuring or wrapping text. Existing objects must update when switching languages without restarting a scene.
- `message_payload(text)` and `message_text(payload)` carry language-neutral message keys and format arguments between peers. Use `valid_message_payload(payload)` before accepting external data. A bounded cache retains formatted-message metadata; localization is not a replacement for authoritative gameplay IDs.

Dialogue recordings are selected separately by dialogue ID, speaker and language in `story_dialogue_catalog.gd`; translating a subtitle does not generate a recording.

## Check changes

```bash
python3 tools/check_locales.py
python3 tools/check_locales.py --json artifacts/localization/source-coverage.json
python3 tests/locales_checker_test.py
```

The checker uses only Python's standard library and exits nonzero on failure. It checks duplicate keys, key parity, nonempty values, source identity and compatible format placeholders. Its tokenizer follows known render/text calls, explicit translation calls, local display variables and appended lists, display properties, catalog text fields, scene text, and environment titles/details in `assets/environments/catalog.json`.

Technical calls, dictionary selectors, input labels, paths, numeric measurements and internal snapshot diagnostics have explicit exclusions in the checker. A lowercase or ASCII-only word is not automatically exempt. Player-facing connection errors and router hints remain covered. When introducing a new text helper or catalog schema, extend `RENDER_CALLS`, `TEXT_FIELDS` or the relevant source rule and add a missing-message fixture. Do not silence an actual display string by adding a technical exemption.

This static check does not prove every arbitrary computed string or external payload is translated, nor does it inspect clipping or voice playback. Retain runtime language-switch, UI, dialogue and multiplayer checks. The isolated checker fixtures deliberately remove ASCII messages and introduce bad placeholders, empty values and duplicate keys; they never alter shipping catalogs.

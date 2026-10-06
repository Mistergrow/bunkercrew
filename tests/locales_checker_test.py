#!/usr/bin/env python3
"""Mutation fixtures for the localization audit; no game files are changed."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("check_locales", ROOT / "tools/check_locales.py")
CHECKER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CHECKER
SPEC.loader.exec_module(CHECKER)


class LocalizationAuditTest(unittest.TestCase):
    def test_core_content_json_remains_covered_after_catalog_migration(self):
        self.catalogs({'Bereit':'Ready', 'Bauteil':'Component'})
        self.write('assets/content/core/items.json', json.dumps({'items':[{'id':'pack:opaque_id','label':'Bauteil'}]}))
        self.assertTrue(CHECKER.check_repository(self.root)['ok'])
        self.write('assets/content/core/items.json', json.dumps({'items':[{'id':'pack:opaque_id','label':'Missing visible label'}]}))
        report = CHECKER.check_repository(self.root)
        self.assertFalse(report['ok'])
        self.assertTrue(any(row['source']=='Missing visible label' for row in report['missing_sources']))
        self.assertFalse(any(row['source']=='pack:opaque_id' for row in report['missing_sources']))

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="lastshift-locale-audit-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.catalogs({"Bereit": "Ready"})

    def write(self, relative, contents):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")

    def catalogs(self, translations):
        self.write("locales/de.json", json.dumps({key: key for key in translations}, ensure_ascii=False))
        self.write("locales/en.json", json.dumps(translations, ensure_ascii=False))

    def scan(self, source, path="scripts/fixture.gd"):
        self.write(path, source)
        return CHECKER.check_repository(self.root)

    def missing(self, source, expected, path="scripts/fixture.gd"):
        report = self.scan(source, path)
        self.assertFalse(report["ok"])
        self.assertIn(expected, {entry["source"] for entry in report["missing_sources"]})
        return report

    def test_ascii_render_message_is_not_missed(self):
        report = self.missing('func _draw():\n\tUiArt.text(self, Vector2.ZERO, "Material fehlt", 12)\n', "Material fehlt")
        self.assertEqual(report["missing_sources"][0]["line"], 2)
        self.assertEqual(report["missing_sources"][0]["path"], "scripts/fixture.gd")

    def test_lowercase_single_word_is_not_automatically_an_id(self):
        self.missing('func _draw():\n\tArt.text(self, Vector2.ZERO, "bereit", 12)\n', "bereit")

    def test_multiline_text_and_comments_are_tokenized(self):
        self.catalogs({"Bereit # jetzt": "Ready # now"})
        report = self.scan('# "Untranslated comment"\nfunc _draw():\n\tUiArt.text(\n\t\tself, Vector2.ZERO,\n\t\t"Bereit # jetzt", 12) # "Other comment"\n')
        self.assertTrue(report["ok"], report["issues"])

    def test_local_binding_and_typed_collection_are_followed(self):
        self.missing('func _draw():\n\tvar lines: Array[String] = []\n\tlines.append("Kein Material")\n\tvar title: String = " ".join(lines)\n\tUiArt.text(self, Vector2.ZERO, title, 12)\n', "Kein Material")

    def test_catalog_text_is_checked_without_rendering_it(self):
        self.missing('const RECIPES = [{"id":"raw_ore", "tech":"mining_tier", "detail":"Material fehlt"}]\n', "Material fehlt")

    def test_solo_story_paragraphs_are_checked_before_discovery(self):
        for field in ("summary", "objective", "body", "name", "role", "job_title", "intro", "rescue", "after"):
            with self.subTest(field=field):
                value = '["Unbekannter Absatz"]' if field in ("intro", "rescue", "after") else '"Unbekannter Absatz"'
                self.missing('const CHAPTERS = {"quarry":{"'+field+'":'+value+'}}\n', "Unbekannter Absatz", "scripts/solo_story_catalog.gd")

    def test_solo_tutorial_paragraphs_are_checked_before_learning(self):
        self.missing('const ENTRIES = {"move":{"title":"Bereit", "body":"Unbekannter Lernschritt"}}\n',
                     "Unbekannter Lernschritt", "scripts/solo_tutorial_catalog.gd")

    def test_tutorial_binding_alias_exempts_only_its_selector_arguments(self):
        source = '''func _draw():
\tUiArt.text(self, Vector2.ZERO, Labels.action(worker, "interact"), 12)
\tUiArt.text(self, Vector2.ZERO, Labels.menu(game, "help"), 12)
\tUiArt.text(self, Vector2.ZERO, _menu_label(worker, "upgrades"), 12)
\tUiArt.text(self, Vector2.ZERO, Labels.action("Unbekannter Besitzer", "jump"), 12)
\tUiArt.text(self, Vector2.ZERO, OtherLabels.action(worker, "Unbekannter Text"), 12)
\tUiArt.text(self, Vector2.ZERO, "interact", 12)
'''
        report = self.scan(source, "scripts/solo_tutorial_controller.gd")
        self.assertEqual({item["source"] for item in report["missing_sources"]},
                         {"Unbekannter Besitzer", "Unbekannter Text", "interact"})
        (self.root / "scripts/solo_tutorial_controller.gd").unlink()
        report = self.scan('func _draw():\n\tUiArt.text(self, Vector2.ZERO, Labels.action(worker, "interact"), 12)\n')
        self.assertEqual({item["source"] for item in report["missing_sources"]}, {"interact"})

    def test_weapon_family_ids_do_not_hide_visible_catalog_titles(self):
        source = '''const WEAPONS = {"veteran_rifle":{"family":"rifle", "title":"Gewehr fehlt"}}
func weapon_name():
	return WEAPONS.get("veteran_rifle", {}).get("title", "Bereit")
'''
        report = self.missing(source, "Gewehr fehlt")
        self.assertEqual({item["source"] for item in report["missing_sources"]}, {"Gewehr fehlt"})

    def test_project_setting_key_is_excluded_but_visible_default_is_checked(self):
        source = 'func update():\n\tget_tree().root.title = str(ProjectSettings.get_setting("application/config/name", "Spielname fehlt"))\n'
        report = self.missing(source, "Spielname fehlt")
        self.assertEqual({item["source"] for item in report["missing_sources"]}, {"Spielname fehlt"})

    def test_qualified_campaign_selectors_are_ids_but_display_text_is_not(self):
        source = '''var selected_id := "harbor"
func _draw():
	var entry = CampaignCatalog.node(selected_id)
	var route = CampaignCatalog.journey(selected_id)
	var stop = CampaignCatalog.stop("harbor:fuel")
	var cost = CampaignCatalog.route_fuel(selected_id, "harbor:fuel", [])
	UiArt.text(self, Vector2.ZERO, str(entry, route, stop, cost), 12)
	UiArt.text(self, Vector2.ZERO, "harbor", 12)
	UiArt.text(self, Vector2.ZERO, CustomCatalog.node("Unbekannter UI-Text"), 12)
'''
        report = self.missing(source, "harbor")
        self.assertEqual({item["source"] for item in report["missing_sources"]}, {"harbor", "Unbekannter UI-Text"})
        self.assertEqual(sum(item["source"] == "harbor" for item in report["missing_sources"]), 1)

    def test_scene_text_is_checked(self):
        self.missing('[gd_scene format=3]\n[node name="Hint" type="Label"]\ntext = "Material fehlt"\n', "Material fehlt", "scenes/menu.tscn")

    def test_input_label_selectors_do_not_hide_visible_or_unrelated_text(self):
        source = '''func _draw():
\tUiArt.text(self, Vector2.ZERO, InputLabels.action(worker, "interact"), 12)
\tUiArt.text(self, Vector2.ZERO, InputLabels.menu(game, "story_journal"), 12)
\tUiArt.text(self, Vector2.ZERO, OtherLabels.action(worker, "Unbekannter Text"), 12)
\tUiArt.text(self, Vector2.ZERO, "interact", 12)
'''
        report = self.missing(source, "Unbekannter Text")
        self.assertEqual({item["source"] for item in report["missing_sources"]}, {"Unbekannter Text", "interact"})

    def test_manual_recipe_ids_do_not_hide_visible_or_unrelated_text(self):
        self.catalogs({"%s": "%s"})
        source = '''func _draw():
	UiArt.text(self, Vector2.ZERO, L.format("%s", _recipe("furnace")), 12)
	UiArt.text(self, Vector2.ZERO, "mixer", 12)
	UiArt.text(self, Vector2.ZERO, L.format("%s", OtherCatalog._recipe("Unbekannter UI-Text")), 12)
'''
        report = self.scan(source, "scripts/help_manual_catalog.gd")
        self.assertEqual({item["source"] for item in report["missing_sources"]}, {"mixer", "Unbekannter UI-Text"})
        (self.root / "scripts/help_manual_catalog.gd").unlink()
        report = self.scan('func _draw():\n\tUiArt.text(self, Vector2.ZERO, L.format("%s", _recipe("furnace")), 12)\n')
        self.assertEqual({item["source"] for item in report["missing_sources"]}, {"furnace"})

    def test_environment_json_is_checked(self):
        self.write("assets/environments/catalog.json", json.dumps({"environments":[{"id":"world_id", "title":"Bereit", "detail":"Rauch am Kai"}]}))
        report = CHECKER.check_repository(self.root)
        self.assertEqual(report["missing_sources"][0]["source"], "Rauch am Kai")
        self.assertEqual(report["scanned"]["environment_entries"], 1)

    def test_native_control_and_dictionary_display_fields(self):
        for source in ['button.tooltip_text = "Material fehlt"', 'result["text"] = "Material fehlt"']:
            with self.subTest(source=source):
                self.missing('func build():\n\t' + source + '\n', "Material fehlt")

    def test_explicit_translation_and_format_arguments(self):
        self.catalogs({"Status: %s": "Status: %s"})
        self.missing('func status():\n\treturn LocaleText.format("Status: %s", "Material fehlt")\n', "Material fehlt")
        self.missing('func status():\n\treturn L.text("Material fehlt")\n', "Material fehlt")

    def test_diagnostics_ids_paths_and_predicates_are_excluded(self):
        report = self.scan('''const LABELS = {"internal_id":"Bereit"}
var state = "inactive_id"
func _draw():
	push_error("Internal diagnostic without translation")
	var label = LABELS.get("internal_id", "Bereit")
	UiArt.text(self, Vector2.ZERO, label if state=="inactive_id" else "Bereit", 12)
	Art.text(self, Vector2.ZERO, "-24 M", 12)
	assert(has_method("internal_method"), "Diagnostic only")
''')
        self.assertTrue(report["ok"], report["issues"])

    def test_network_player_errors_are_not_excluded_with_diagnostics(self):
        report = self.scan('func apply():\n\treturn _fail("Internal snapshot rejection")\n', "scripts/network_world.gd")
        self.assertTrue(report["ok"], report["issues"])
        self.missing('func join():\n\t_fail("Code fehlt")\n', "Code fehlt", "scripts/network_session.gd")
        self.missing('func join():\n\terror.emit("Code fehlt")\n', "Code fehlt", "scripts/network_transport.gd")

    def test_background_router_hint_is_checked(self):
        self.missing('func run():\n\treport("", "Router nicht erreichbar")\n', "Router nicht erreichbar", "scripts/network_transport.gd")

    def test_dictionary_join_error_is_checked(self):
        self.missing('func decode():\n\treturn {"error":"Code fehlt"}\n', "Code fehlt", "scripts/network_join_code.gd")

    def test_relay_schema_exemption_does_not_hide_real_errors(self):
        source = 'func _valid_relay_control(message):\n\tvar keys = {"error":["op","code","message"]}\n\t_fail("Code fehlt")\n'
        report = self.missing(source, "Code fehlt", "scripts/network_session.gd")
        self.assertEqual({item["source"] for item in report["missing_sources"]}, {"Code fehlt"})

    def test_catalog_key_parity_is_enforced(self):
        self.write("locales/en.json", '{}')
        self.assertTrue(any("missing key" in issue for issue in CHECKER.check_repository(self.root)["issues"]))

    def test_duplicate_keys_are_reported_in_both_catalogs(self):
        for language in ("de", "en"):
            with self.subTest(language=language):
                self.catalogs({"Bereit":"Ready"})
                self.write(f"locales/{language}.json", '{"Bereit":"Bereit", "Bereit":"Bereit"}')
                self.assertTrue(any("duplicate key" in issue for issue in CHECKER.check_repository(self.root)["issues"]))

    def test_empty_and_nonstring_values_are_rejected(self):
        for value in ("", "   ", None, 17, []):
            with self.subTest(value=value):
                self.write("locales/en.json", json.dumps({"Bereit":value}))
                self.assertFalse(CHECKER.check_repository(self.root)["ok"])

    def test_german_values_are_stable_source_ids(self):
        self.write("locales/de.json", '{"Bereit":"Changed source"}')
        self.assertTrue(any("source msgid differs" in issue for issue in CHECKER.check_repository(self.root)["issues"]))

    def test_placeholder_type_order_count_and_escaping(self):
        source = "%s: %d / %.1f %%"
        for translated in ("%s: %s / %.1f %%", "%d: %s / %.1f %%", "%s: %d", "%s: %d / %.1f %"):
            with self.subTest(translated=translated):
                self.catalogs({source:translated})
                self.assertFalse(CHECKER.check_repository(self.root)["ok"])
        self.catalogs({source:"%s: %02i / %.2f %%"})
        self.assertTrue(CHECKER.check_repository(self.root)["ok"])

    def test_literal_percentage_is_not_a_float_placeholder(self):
        self.catalogs({"6 % eigener Schaden":"6% personal damage"})
        report = self.scan('func _draw():\n\tArt.text(self, Vector2.ZERO, "6 % eigener Schaden", 12)\n')
        self.assertTrue(report["ok"], report["issues"])

    def test_runtime_case_and_target_aliases_are_recognized(self):
        report = self.scan('func _draw():\n\tArt.text(self, Vector2.ZERO, "BEREIT", 12)\n\tArt.text(self, Vector2.ZERO, "READY", 12)\n')
        self.assertTrue(report["ok"], report["issues"])

    def test_cli_nonzero_exit_and_machine_report_on_missing_ascii(self):
        self.write("scripts/hint.gd", 'func prompt():\n\treturn "Material fehlt"\n')
        output = self.root / "audit.json"
        result = subprocess.run([sys.executable, str(ROOT / "tools/check_locales.py"), "--root", str(self.root), "--json", str(output)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("LOCALES FAIL", result.stdout)
        report = json.loads(output.read_text())
        self.assertEqual(report["missing_sources"][0]["source"], "Material fehlt")


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Exercise explicit milestones in disposable projects; never rewrite the game."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('versioning', ROOT / 'tools/bump_version.py')
versioning = importlib.util.module_from_spec(spec)
spec.loader.exec_module(versioning)


class Milestones(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='bunkercrew-version-regression-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.previous = '0.1.6-beta.20261003'
        self.next = '0.1.7-beta.20261005'
        (self.root / 'assets/releases').mkdir(parents=True)
        (self.root / 'beta/historical').mkdir(parents=True)
        (self.root / 'beta/historical/package.zip').write_bytes(b'PRESERVE-HISTORICAL-PACKAGE')
        (self.root / 'project.godot').write_text(f'[application]\nconfig/version="{self.previous}"\n')
        (self.root / 'export_presets.cfg').write_text(
            '[preset.0]\nname="Windows Beta"\nplatform="Windows Desktop"\n'
            'include_filter="assets/releases/changelog.json"\n'
            f'export_path="beta/{self.previous}/windows-x86_64/Bunkercrew.exe"\n'
            '[preset.0.options]\napplication/file_version="0.1.6.0"\n'
            'application/product_version="0.1.6.0"\napplication/file_description="fixture"\n')
        self.notes = {'schema': 1, 'releases': [{'version': self.previous, 'date': '2026-10-03',
            'title': {'de': 'Basis', 'en': 'Baseline'}, 'changes': [{'de': 'Vorher', 'en': 'Before'}]}]}
        (self.root / versioning.NOTES).write_text(json.dumps(self.notes))
        (self.root / 'CHANGELOG.md').write_text(versioning.markdown(self.notes))

    def snapshot(self):
        return {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}

    def bump(self, **kwargs):
        return versioning.bump(self.root, self.next, {'de': 'Werkstatt', 'en': 'Workshop'},
                               [{'de': 'Verbessert', 'en': 'Improved'}], **kwargs)

    def start_public(self, **kwargs):
        return versioning.bump(self.root, '0.1.0-beta', {'de': 'Öffentliche Beta', 'en': 'Public beta'},
                               [{'de': 'Entwicklungsstand erhalten', 'en': 'Development history retained'}],
                               start_public_series=True, release_date='2026-10-06', **kwargs)

    def public_bump(self, release, **kwargs):
        return versioning.bump(self.root, release, {'de': 'Verbesserung', 'en': 'Improvement'},
                               [{'de': 'Geprüft', 'en': 'Verified'}], release_date='2026-10-07', **kwargs)

    def test_current_source_validation(self):
        versioning.validate_release(ROOT)

    def test_explicit_milestone_and_preserved_archives(self):
        previous = self.snapshot()
        self.bump()
        versioning.validate_release(self.root)
        self.assertEqual(versioning.project_version(self.root), self.next)
        notes = json.loads((self.root / versioning.NOTES).read_text())
        self.assertEqual(notes['releases'][1:], self.notes['releases'])
        self.assertEqual(notes['releases'][0]['date'], '2026-10-05')
        presets = (self.root / 'export_presets.cfg').read_text()
        self.assertIn('application/file_version="0.1.7.0"', presets)
        self.assertIn('application/product_version="0.1.7.0"', presets)
        self.assertIn(f'beta/{self.next}/windows', presets)
        self.assertEqual((self.root / 'beta/historical/package.zip').read_bytes(),
                         previous[Path('beta/historical/package.zip')])
        self.assertIn('Improved', (self.root / 'CHANGELOG.md').read_text())

    def test_dry_run_changes_nothing(self):
        previous = self.snapshot()
        self.assertTrue(self.bump(dry_run=True)['dry_run'])
        self.assertEqual(self.snapshot(), previous)

    def test_strict_development_and_public_forms(self):
        self.assertEqual(versioning.parse_version('0.1.0-beta'), (0, 1, 0, ''))
        self.assertEqual(versioning.parse_version('0.1.12-beta.20261005'), (0, 1, 12, '20261005'))
        for release in ('v0.1.0-beta', '0.01.0-beta', '0.1.00-beta', '0.1.0', '0.1.0-beta.1',
                        '0.1.0-beta.', '0.1.0-beta.extra', '0.1.0-beta.20260230', None):
            with self.subTest(release=release):
                with self.assertRaises(ValueError): versioning.parse_version(release)

    def test_public_transition_preserves_historical_entries_and_archives(self):
        pretty_history = json.dumps(self.notes, ensure_ascii=False, indent=2) + '\n'
        (self.root / versioning.NOTES).write_text(pretty_history)
        historical_body = pretty_history.split('"releases": [\n', 1)[1].rsplit('\n  ]', 1)[0]
        previous = self.snapshot()
        result = self.start_public()
        versioning.validate_release(self.root)
        self.assertTrue(result['start_public_series'])
        self.assertEqual(versioning.project_version(self.root), '0.1.0-beta')
        text = (self.root / versioning.NOTES).read_text()
        notes = json.loads(text)
        self.assertEqual(notes['releases'][1:], self.notes['releases'])
        self.assertIn(historical_body, text)
        self.assertEqual(notes['releases'][0]['date'], '2026-10-06')
        self.assertEqual(notes['releases'][1]['version'], self.previous)
        presets = (self.root / 'export_presets.cfg').read_text()
        self.assertIn('application/file_version="0.1.0.0"', presets)
        self.assertIn('application/product_version="0.1.0.0"', presets)
        self.assertIn('application/file_description="Bunkercrew 0.1.0-beta"', presets)
        self.assertIn('beta/0.1.0-beta/windows', presets)
        self.assertEqual((self.root / 'beta/historical/package.zip').read_bytes(),
                         previous[Path('beta/historical/package.zip')])
        self.assertIn('Development history retained', (self.root / 'CHANGELOG.md').read_text())

    def test_public_transition_dry_run_changes_nothing(self):
        previous = self.snapshot()
        self.assertTrue(self.start_public(dry_run=True)['dry_run'])
        self.assertEqual(self.snapshot(), previous)

    def test_normal_milestone_cannot_silently_start_public_series(self):
        previous = self.snapshot()
        for release in ('0.1.0-beta', '0.1.7-beta', '1.0.0-beta'):
            with self.subTest(release=release):
                with self.assertRaises(ValueError): self.public_bump(release)
                self.assertEqual(self.snapshot(), previous)

    def test_public_transition_requires_new_public_series(self):
        previous = self.snapshot()
        for release in (self.next, self.previous):
            with self.subTest(release=release):
                with self.assertRaises(ValueError):
                    versioning.bump(self.root, release, {'de': 'D', 'en': 'E'},
                                    [{'de': 'D', 'en': 'E'}], start_public_series=True)
                self.assertEqual(self.snapshot(), previous)
        self.start_public()
        public = self.snapshot()
        with self.assertRaises(ValueError): self.start_public()
        with self.assertRaises(ValueError): self.public_bump('0.1.1-beta', start_public_series=True)
        self.assertEqual(self.snapshot(), public)

    def test_public_downgrade_repeat_and_return_to_development_rejected(self):
        self.start_public()
        self.public_bump('0.1.1-beta')
        previous = self.snapshot()
        for release in ('0.1.1-beta', '0.1.0-beta', '0.0.9-beta', '0.1.13-beta.20261008'):
            with self.subTest(release=release):
                with self.assertRaises(ValueError): self.public_bump(release)
                self.assertEqual(self.snapshot(), previous)

    def test_public_bumps_keep_suffix_and_independent_dates(self):
        self.start_public()
        self.assertEqual(versioning.next_release('0.1.0-beta', 'patch', '2026-10-07'), '0.1.1-beta')
        self.assertEqual(versioning.next_release('0.1.0-beta', 'minor', '2026-10-07'), '0.2.0-beta')
        self.assertEqual(versioning.next_release('0.1.0-beta', 'major', '2026-10-07'), '1.0.0-beta')
        self.assertEqual(versioning.next_release(self.previous, 'patch', '2026-10-07'), '0.1.7-beta.20261007')
        self.public_bump('0.1.1-beta')
        versioning.validate_release(self.root)
        notes = json.loads((self.root / versioning.NOTES).read_text())
        self.assertEqual([entry['version'] for entry in notes['releases']],
                         ['0.1.1-beta', '0.1.0-beta', self.previous])
        self.assertEqual([entry['date'] for entry in notes['releases']],
                         ['2026-10-07', '2026-10-06', '2026-10-03'])
        self.assertEqual(notes['releases'][2:], self.notes['releases'])

    def test_public_dates_invalid_or_out_of_order_rejected(self):
        previous = self.snapshot()
        for recorded in ('2026-02-30', '2026-10-02'):
            with self.subTest(recorded=recorded):
                with self.assertRaises(ValueError):
                    versioning.bump(self.root, '0.1.0-beta', {'de': 'D', 'en': 'E'},
                                    [{'de': 'D', 'en': 'E'}], start_public_series=True,
                                    release_date=recorded)
                self.assertEqual(self.snapshot(), previous)

    def test_mixed_history_rejects_duplicate_reordered_and_second_boundary(self):
        self.start_public()
        self.public_bump('0.1.1-beta')
        notes = json.loads((self.root / versioning.NOTES).read_text())
        public_new, public_old, development = notes['releases']
        for releases in ([public_new, public_old, public_old, development],
                         [public_old, public_new, development],
                         [public_new, development, public_old],
                         [public_new, public_old, development, development]):
            with self.subTest(versions=[entry['version'] for entry in releases]):
                with self.assertRaises(ValueError):
                    versioning.validate_notes({'schema': 1, 'releases': releases}, releases[0]['version'])

    def test_public_transition_write_failure_rolls_back_all_files(self):
        previous = self.snapshot()
        real_replace = versioning.os.replace
        calls = 0
        def fail_second(source, target):
            nonlocal calls
            calls += 1
            if calls == 2: raise OSError('Disposable failed public transition')
            real_replace(source, target)
        with patch.object(versioning.os, 'replace', side_effect=fail_second):
            with self.assertRaises(OSError): self.start_public()
        self.assertEqual(self.snapshot(), previous)
        self.assertFalse(list(self.root.rglob('.version-*')))

    def test_cli_public_transition_and_next_patch(self):
        arguments = [sys.executable, '-B', str(ROOT / 'tools/bump_version.py'), '--root', str(self.root),
                     '--date', '2026-10-06', '--title-de', 'Beta', '--title-en', 'Beta',
                     '--change-de', 'Geprüft', '--change-en', 'Verified']
        previous = self.snapshot()
        preview = subprocess.run(arguments + ['--to', '0.1.0-beta', '--start-public-series', '--dry-run'],
                                 capture_output=True, text=True)
        self.assertEqual(preview.returncode, 0, preview.stderr)
        self.assertEqual(self.snapshot(), previous)
        for action in ('--check', '--bump'):
            extra = [action] if action == '--check' else [action, 'patch']
            rejected = subprocess.run(arguments + extra + ['--start-public-series'], capture_output=True, text=True)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertEqual(self.snapshot(), previous)
        result = subprocess.run(arguments + ['--to', '0.1.0-beta', '--start-public-series'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        patched = subprocess.run(arguments + ['--bump', 'patch'], capture_output=True, text=True)
        self.assertEqual(patched.returncode, 0, patched.stderr)
        self.assertEqual(json.loads(patched.stdout)['version'], '0.1.1-beta')
        versioning.validate_release(self.root)

    def test_invalid_milestones_rejected_before_writing(self):
        previous = self.snapshot()
        for release in [self.previous, '0.1.5-beta.20261005', '0.01.7-beta.20261005',
                        '0.1.7-beta.20260230', '0.1.7-beta.20261005.extra', 'anything']:
            with self.subTest(release=release):
                with self.assertRaises(ValueError):
                    versioning.bump(self.root, release, {'de': 'DE', 'en': 'EN'}, [{'de': 'DE', 'en': 'EN'}])
                self.assertEqual(self.snapshot(), previous)
        for title, changes in [({'de': 'Missing English'}, [{'de': 'D', 'en': 'E'}]),
                               ({'de': 'D', 'en': 'E'}, []),
                               ({'de': 'D', 'en': 'E'}, [{'de': 'D', 'en': ''}])]:
            with self.assertRaises(ValueError): versioning.bump(self.root, self.next, title, changes)
            self.assertEqual(self.snapshot(), previous)

    def test_write_failure_restores_all_originals(self):
        previous = self.snapshot()
        real_replace = versioning.os.replace
        calls = 0
        def fail_second(source, target):
            nonlocal calls
            calls += 1
            if calls == 2: raise OSError('Disposable failed write')
            real_replace(source, target)
        with patch.object(versioning.os, 'replace', side_effect=fail_second):
            with self.assertRaises(OSError): self.bump()
        self.assertEqual(self.snapshot(), previous)
        self.assertFalse(list(self.root.rglob('.version-*')))

    def test_ambiguous_project_identity_rejected(self):
        with (self.root / 'project.godot').open('a') as file:
            file.write('config/version="9.9.9-beta.20261005"\n')
        with self.assertRaises(ValueError): versioning.validate_release(self.root)

    def test_changelog_and_export_drift_rejected(self):
        path = self.root / 'CHANGELOG.md'; original = path.read_text()
        path.write_text('Stale document')
        with self.assertRaises(ValueError): versioning.validate_release(self.root)
        path.write_text(original)
        presets = self.root / 'export_presets.cfg'; original = presets.read_text()
        presets.write_text(original.replace('0.1.6.0', '0.1.5.0'))
        with self.assertRaises(ValueError): versioning.validate_release(self.root)
        presets.write_text(original.replace('assets/releases/changelog.json', 'missing.json'))
        with self.assertRaises(ValueError): versioning.validate_release(self.root)


if __name__ == '__main__': unittest.main()

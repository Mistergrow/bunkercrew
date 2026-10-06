#!/usr/bin/env python3
"""Provenance failures prevent reuse of mismatched native audio in a candidate."""

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("candidate", ROOT / "tools/export_network_beta_candidate.py")
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class NativeCandidateTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="bunkercrew-candidate-unit-")
        self.project = Path(self.temporary.name)
        self.audio = self.project / "assets/audio/live"
        self.audio.mkdir(parents=True)
        self.source = self.project / "native/source.cpp"
        self.source.parent.mkdir()
        self.source.write_text("fixture native source")
        self.libraries = {}
        for name in ("libbunkercrew_audio.linux.x86_64.so", "bunkercrew_audio.windows.x86_64.dll"):
            path = self.audio / name
            path.write_bytes(name.encode())
            self.libraries[name] = {"bytes": path.stat().st_size, "sha256": digest(path)}
        self.metadata = {"native_source_sha256": {"native/source.cpp": digest(self.source)}, "binaries": self.libraries}
        self.write_metadata()

    def tearDown(self):
        self.temporary.cleanup()

    def write_metadata(self):
        (self.audio / "native.source.json").write_text(json.dumps(self.metadata))

    def test_matching_sources_and_binaries_preserve_scope(self):
        result = candidate.verify_native_sources(self.project, digest)
        self.assertEqual(result["libraries"], self.libraries)
        self.assertFalse(result["new_endurance_run"])

    def test_changed_source_is_rejected(self):
        self.source.write_text("new source not represented by shipped binary")
        with self.assertRaisesRegex(RuntimeError, "Native source differs"):
            candidate.verify_native_sources(self.project, digest)

    def test_changed_binary_is_rejected(self):
        (self.audio / "bunkercrew_audio.windows.x86_64.dll").write_bytes(b"unmatched replacement")
        with self.assertRaisesRegex(RuntimeError, "Native library differs"):
            candidate.verify_native_sources(self.project, digest)

    def test_unrecorded_platform_is_rejected(self):
        self.metadata["binaries"].pop("bunkercrew_audio.windows.x86_64.dll")
        self.write_metadata()
        with self.assertRaisesRegex(RuntimeError, "both desktop libraries"):
            candidate.verify_native_sources(self.project, digest)

    def test_source_path_cannot_escape_project(self):
        self.metadata["native_source_sha256"] = {"../untrusted.cpp": "0" * 64}
        self.write_metadata()
        with self.assertRaisesRegex(RuntimeError, "Native source differs"):
            candidate.verify_native_sources(self.project, digest)

    def test_test_kit_is_portable_and_preserves_outcomes(self):
        docs = self.project / "docs"
        docs.mkdir()
        source = ("[Results](beta-playtest-template.json) [Coop](beta-coop-test.md)\n"
                  "[Controls](../scripts/input_setup.gd) [Evidence](../artifacts/review.json)\n"
                  "[Plan](beta-0.5-plan.md)\n")
        (docs / "beta-playtest.md").write_text(source)
        template = b'{"human_cases":[{"id":"native-pad","status":"NOT_RUN"}]}\n'
        (docs / "beta-playtest-template.json").write_bytes(template)
        package = self.project / "package"
        package.mkdir()
        (package / "README.md").write_text("Existing coop guide")
        machine_result = b'{"success":true,"checks":["compiled-export"]}\n'
        (package / "TEST_RESULTS.json").write_bytes(machine_result)
        candidate.copy_test_kit(self.project, package)
        portable = (package / "TESTING.md").read_text()
        self.assertIn("[Results](HUMAN_TEST_TEMPLATE.json)", portable)
        self.assertIn("[Coop](README.md)", portable)
        self.assertNotIn("../", portable)
        self.assertNotIn("(beta-0.5-plan.md)", portable)
        self.assertIn("Controls", portable)
        self.assertEqual((package / "HUMAN_TEST_TEMPLATE.json").read_bytes(), template)
        self.assertEqual((package / "TEST_RESULTS.json").read_bytes(), machine_result)
        self.assertEqual((docs / "beta-playtest.md").read_text(), source)
        self.assertEqual((package / "README.md").read_text(), "Existing coop guide")


if __name__ == "__main__":
    unittest.main()

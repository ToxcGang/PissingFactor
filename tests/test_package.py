import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from verify import GATES, LUA_PREFIX, PAK_PATH, ROOT, read_json, validate_acceptance, validate_zip


class ReleaseGateTests(unittest.TestCase):
    def evidence(self):
        return {"version": "1.0.0", "protocol": 1, "sourceCommit": "a" * 40,
                "pakSha256": "b" * 64, "dependencies": read_json(ROOT / "dependencies.lock.json"),
                "checks": {gate: {"status": "passed", "tester": "Test fixture",
                                  "date": "2026-09-10", "evidence": "Synthetic validator fixture only"}
                           for gate in GATES}}

    def test_complete_evidence_is_accepted(self):
        validate_acceptance(self.evidence(), "a" * 40, "b" * 64)

    def test_every_gate_is_required(self):
        for gate in GATES:
            with self.subTest(gate=gate):
                data = self.evidence()
                data["checks"][gate]["status"] = "pending"
                with self.assertRaisesRegex(ValueError, gate):
                    validate_acceptance(data, "a" * 40, "b" * 64)

    def test_stale_commit_or_different_binary_is_rejected(self):
        for commit, digest in [("c" * 40, "b" * 64), ("a" * 40, "c" * 64)]:
            with self.assertRaises(ValueError):
                validate_acceptance(self.evidence(), commit, digest)

    def test_unfilled_template_is_not_approval(self):
        with self.assertRaises(ValueError):
            validate_acceptance(read_json(ROOT / "validation/results.json"), "a" * 40, "b" * 64)

    def test_missing_tester_is_rejected(self):
        data = self.evidence()
        data["checks"]["controller"]["tester"] = ""
        with self.assertRaisesRegex(ValueError, "tester"):
            validate_acceptance(data, "a" * 40, "b" * 64)


class ZipTests(unittest.TestCase):
    def write_zip(self, path, extra=None, corrupt=False):
        files = {PAK_PATH: b"synthetic fixture, never install",
                 LUA_PREFIX + "scripts/main.lua": b"return {}",
                 LUA_PREFIX + "enabled.txt": b"", LUA_PREFIX + "config.lua": b"return {}",
                 "README.md": b"fixture", "LICENSE": b"fixture", "dependencies.lock.json": b"{}"}
        files.update(extra or {})
        manifest = {"version": "1.0.0", "files": {
            name: hashlib.sha256(data).hexdigest() for name, data in files.items()}}
        if corrupt:
            files["README.md"] = b"changed after hashing"
        with zipfile.ZipFile(path, "w") as z:
            for name, data in files.items():
                z.writestr(name, data)
            z.writestr("package-manifest.json", json.dumps(manifest))

    def test_expected_layout_and_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.zip"
            self.write_zip(path)
            validate_zip(path)

    def test_private_content_and_path_traversal_are_rejected(self):
        for name in ["../escaped.lua", "C:/file", "docs/../../file", "docs\\file",
                     LUA_PREFIX + "game.dll", "game.uasset", "UE4SS_ObjectDump.txt"]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "test.zip"
                self.write_zip(path, {name: b"private fixture"})
                with self.assertRaises(ValueError):
                    validate_zip(path)

    def test_tampered_payload_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.zip"
            self.write_zip(path, corrupt=True)
            with self.assertRaisesRegex(ValueError, "Hash mismatch"):
                validate_zip(path)


if __name__ == "__main__":
    unittest.main()

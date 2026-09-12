from pathlib import Path
import tempfile
import unittest

from Tools.content_audit import scan_tree


class ContentAuditTests(unittest.TestCase):
    def test_rejects_prohibited_extension(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "zm_test.ff"
            p.write_bytes(b"synthetic")
            findings = scan_tree(Path(td), set())
            self.assertTrue(any("prohibited extension" in f.reason for f in findings))

    def test_rejects_eboot_signature_name(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "EBOOT.BIN"
            p.write_bytes(b"synthetic")
            findings = scan_tree(Path(td), set())
            self.assertTrue(any("prohibited filename" in f.reason for f in findings))

    def test_rejects_misnamed_elf(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "fixture.dat"
            p.write_bytes(b"\x7fELF" + b"\x00" * 32)
            findings = scan_tree(Path(td), set())
            self.assertTrue(any("ELF signature" in f.reason for f in findings))

    def test_accepts_plain_source(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "Example.swift"
            p.write_text("struct Example {}")
            self.assertEqual(scan_tree(Path(td), set()), [])


if __name__ == "__main__":
    unittest.main()

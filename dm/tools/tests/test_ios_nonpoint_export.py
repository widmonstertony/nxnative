"""Supplemental shader exports must preserve data and reject mixed identities."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[2] / "ios/tools/export_nonpoint_sources.py"
SPEC = importlib.util.spec_from_file_location("nonpoint_export", TOOL)
assert SPEC is not None and SPEC.loader is not None
EXPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXPORT)


class NonPointExportTests(unittest.TestCase):
    FRAGMENT = b'''#include <metal_stdlib>
using namespace metal;
struct main0_out {\n    float4 a [[color(0)]];\n    float4 b [[color(1)]];\n    float z [[depth(any)]];\n};
fragment main0_out main0() {main0_out out = {}; out.a=float4(.5); out.b=float4(.25); out.z=.5; return out;}
fragment main0_out main0_u() {main0_out out = {}; return out;}
'''

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.cache, self.libs, self.out = root / "cache/b-abc", root / "ios/b-abc", root / "export"
        self.cache.mkdir(parents=True)
        self.libs.mkdir(parents=True)
        self.source = b"float gl_PointSize [[point_size]];\n"
        (self.cache / "a_b.metal").write_bytes(self.source)
        (self.libs / "a_b.metallib").write_bytes(b"MTLB-original")
        self.reflection = self.libs / "a_b.json"
        self.meta = {"stage": "vs", "key": "a_b", "chain": "abc"}
        self.reflection.write_text(json.dumps(self.meta))

    def test_export_preserves_source_and_binds_both_hashes(self):
        self.assertEqual(EXPORT.export(self.cache, self.libs, self.out, "abc"), 1)
        manifest = json.loads((self.out / "manifest.json").read_text())
        self.assertEqual(manifest["chain"], "abc")
        self.assertEqual((self.out / "a_b.metal").read_bytes(), self.source)
        self.assertEqual(manifest["shaders"]["a_b"], {
            "source_sha256": hashlib.sha256(self.source).hexdigest(),
            "library_sha256": hashlib.sha256(b"MTLB-original").hexdigest(),
        })

    def test_rejects_wrong_chain_directory_and_reflection(self):
        with self.assertRaises(ValueError):
            EXPORT.export(self.cache, self.libs, self.out, "def")
        self.meta["chain"] = "def"
        self.reflection.write_text(json.dumps(self.meta))
        with self.assertRaises(ValueError):
            EXPORT.export(self.cache, self.libs, self.out, "abc")
        self.assertFalse((self.out / "manifest.json").exists())

    def test_does_not_export_fragment_or_nonpoint_free_source(self):
        self.meta["stage"] = "ps"
        self.reflection.write_text(json.dumps(self.meta))
        self.assertEqual(EXPORT.export(self.cache, self.libs, self.out, "abc"), 0)
        self.meta["stage"] = "vs"
        self.reflection.write_text(json.dumps(self.meta))
        (self.cache / "a_b.metal").write_text("float4 position [[position]];\n")
        self.assertEqual(EXPORT.export(self.cache, self.libs, self.out, "abc"), 0)
        self.assertEqual(json.loads((self.out / "manifest.json").read_text())["shaders"], {})

    def test_depth_output_metadata_is_bound_to_the_original_library(self):
        self.meta["stage"] = "ps"
        self.reflection.write_text(json.dumps(self.meta))
        source = b"struct O { float z [[depth(any)]]; };\n"
        (self.cache / "a_b.metal").write_bytes(source)
        self.assertEqual(EXPORT.export(self.cache, self.libs, self.out, "abc"), 0)
        manifest = json.loads((self.out / "manifest.json").read_text())
        self.assertEqual(manifest["fragment_depth_outputs"]["a_b"], {
            "source_sha256": hashlib.sha256(source).hexdigest(),
            "library_sha256": hashlib.sha256(b"MTLB-original").hexdigest(),
        })
        self.assertFalse((self.out / "a_b.metal").exists())

    def test_dual_source_keeps_primary_and_other_entries_unchanged(self):
        alternate = EXPORT.dual_source(self.FRAGMENT)
        self.assertTrue(alternate.startswith(self.FRAGMENT))
        self.assertEqual(alternate.count(b"main0_u("), 1)
        self.assertEqual(alternate.count(b"main0_d("), 1)
        self.assertIn(b"float4 b [[color(0), index(1)]]", alternate)
        self.assertIn(b"float z [[depth(any)]]", alternate)
        self.assertIn(b"return main0_out_d{out.a, out.b, out.z};", alternate)
        self.assertIn(b"out.a=float4(.5); out.b=float4(.25); out.z=.5;", alternate)

    def test_dual_source_accepts_function_whitespace(self):
        alternate = EXPORT.dual_source(self.FRAGMENT.replace(b"fragment main0_out main0()", b"fragment\nmain0_out main0 ()"))
        self.assertIn(b"fragment main0_out_d main0_d()", alternate)

    def test_dual_source_rejects_unsupported_output_shapes(self):
        self.assertIsNone(EXPORT.dual_source(b"fragment float4 main0() {return 0;}"))
        self.assertIsNone(EXPORT.dual_source(self.FRAGMENT.replace(b"color(1)", b"color(2)")))
        self.assertIsNone(EXPORT.dual_source(self.FRAGMENT.replace(b"float4 b", b"uint4 b")))
        with self.assertRaises(ValueError):
            EXPORT.dual_source(self.FRAGMENT.replace(b"return out;", b"return unexpected;"))

    def test_dual_export_is_hash_bound_and_native_entry_is_not_replaced(self):
        self.meta["stage"] = "ps"
        self.reflection.write_text(json.dumps(self.meta))
        (self.cache / "a_b.metal").write_bytes(self.FRAGMENT)
        EXPORT.export(self.cache, self.libs, self.out, "abc")
        manifest = json.loads((self.out / "manifest.json").read_text())
        alternate = (self.out / "a_b.dual.metal").read_bytes()
        self.assertEqual(manifest["fragment_dual_sources"]["a_b"], {
            "source_sha256": hashlib.sha256(alternate).hexdigest(),
            "original_source_sha256": hashlib.sha256(self.FRAGMENT).hexdigest(),
            "library_sha256": hashlib.sha256(b"MTLB-original").hexdigest(),
        })
        self.meta["entry_d"] = "main0_d"
        self.reflection.write_text(json.dumps(self.meta))
        EXPORT.export(self.cache, self.libs, self.out, "abc")
        self.assertEqual(json.loads((self.out / "manifest.json").read_text())["fragment_dual_sources"], {})


if __name__ == "__main__":
    unittest.main()

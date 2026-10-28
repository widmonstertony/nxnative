#!/usr/bin/env python3
"""Keep old-GPU layered compatibility from dropping ordinary shader entries."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
HEADER = ROOT / "gfx/nvn/nvn_layered_slices.h"


class LayeredShaderFallbackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = HEADER.read_text()

    def test_unproven_companion_can_only_fall_back_to_a_split_base_entry(self):
        self.assertIn('meta[@"entry_layer"]', self.source)
        self.assertIn('![entry isEqualToString:layered]', self.source)
        self.assertIn('if (split && exact)', self.source)
        self.assertIn('return original;', self.source)

    def test_fallback_requires_exact_library_and_reflection_hashes(self):
        self.assertIn('[record[@"library_sha256"] isEqual:nonpoint_digest(base)]', self.source)
        self.assertIn('[record[@"reflection_sha256"] isEqual:nonpoint_digest(reflection)]', self.source)

    def test_unsplit_unproven_shader_still_fails_closed(self):
        fallback = self.source.index('if (split && exact)')
        rejection = self.source.index('reason = [@"Unproven per-slice shader:', fallback)
        self.assertGreater(rejection, fallback)


if __name__ == "__main__":
    unittest.main()

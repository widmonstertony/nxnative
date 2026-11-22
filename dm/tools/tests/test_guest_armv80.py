import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from guest_armv80 import atomic_thunk, atomics, ldar, returns


class GuestArmv80Tests(unittest.TestCase):
    def test_scans_only_aligned_executable_instructions(self):
        image = struct.pack("<5I", 0xD65F0FFF, 0x88E87C14, 0xF8BFC3E9, 0x88E87C14, 0x4860FFE6)
        ranges = [(0, 12), (16, 20)]
        self.assertEqual(list(returns(image, ranges)), [(0, 0xD50323FF)])
        self.assertEqual(list(atomics(image, ranges)),
                         [(4, 0x88E87C14, "cas"), (8, 0xF8BFC3E9, "rcpc"), (16, 0x4860FFE6, "pair")])
        self.assertEqual(ldar(0xF8BFC3E9), 0xC8DFFFE9)

    def test_acquire_cas_thunk_keeps_flags_and_returns_to_next_instruction(self):
        # CASA W8, W20, [X0] was the first unsupported atomic on the old iPad.
        code = atomic_thunk(0x88E87C14, "cas", 0x100, 0x200)
        # The earlier x18 stub can keep scratch at SP-24.
        spill = (code[0] >> 15) & 0x7F
        self.assertEqual(((spill ^ 0x40) - 0x40) * 8, -144)
        self.assertIn(0x885FFC09, code)  # ldaxr w9, [x0]
        self.assertIn(0x880B7C14, code)  # stxr w11, w20, [x0]
        self.assertIn(0xD5033F5F, code)  # clrex on a failed comparison
        last = 0x200 + 4 * (len(code) - 1)
        immediate = code[-1] & 0x3FFFFFF
        self.assertEqual(last + ((immediate ^ 0x2000000) - 0x2000000) * 4, 0x104)


if __name__ == "__main__":
    unittest.main()

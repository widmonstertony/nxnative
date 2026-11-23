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

    def test_ldset_in_address_rewrite_stub_returns_the_old_value(self):
        instruction = 0xB8313160  # ldset w17, w0, [x11]
        stub = struct.pack("<4I", 0x8B000021, 0xF9400020, instruction, 0xF9000020)
        self.assertEqual(list(atomics(stub, [(0, len(stub))])), [(8, instruction, "rmw")])

        thunk = atomic_thunk(instruction, "rmw", 8, 0x100)
        self.assertEqual(thunk[2:7], [
            0x885F7D69,  # ldxr w9, [x11]
            0x2A11012A,  # orr w10, w9, w17
            0x880C7D6A,  # stxr w12, w10, [x11]
            0x35FFFFAC,  # cbnz w12, back to the load
            0x2A0903E0,  # mov w0, w9
        ])
        emitted = struct.pack(f"<{len(thunk)}I", *thunk)
        self.assertFalse(list(atomics(emitted, [(0, len(emitted))])))


if __name__ == "__main__":
    unittest.main()

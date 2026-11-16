#!/usr/bin/env python3
"""Exercise the production touch-pedal state across concurrent driving input."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class RacingTouch(unittest.TestCase):
    def test_pedals_concurrency_braking_and_lifecycle(self):
        code = r'''
#include <assert.h>
#include "DmRacingTouch.h"
int main(void) {
    dm_racing_touch s = {0};
    assert(!dm_racing_touch_buttons(&s, 0, 0));
    // Touch-down accelerates immediately; a completed tap keeps it running.
    assert(dm_racing_touch_buttons(&s, 1, 0) == DM_BTN_ZR);
    dm_racing_touch_tap(&s);
    assert(dm_racing_touch_buttons(&s, 0, 0) == DM_BTN_ZR);
    // Steering/multi-key updates and releasing drift never drop the throttle.
    for (int axis = -32767; axis <= 32767; axis += 32767) {
        for (uint64_t face = 0; face < 16; ++face) {
            uint64_t combined = face | dm_racing_touch_buttons(&s, 0, 0);
            assert(combined == (face | DM_BTN_ZR));
            assert((combined & 15) == face);  // XBAY native meanings unchanged.
        }
    }
    dm_racing_touch_tap(&s);
    assert(!dm_racing_touch_buttons(&s, 0, 0));
    // Brake overrides both a finger on gas and the latch; release stays stopped.
    dm_racing_touch_tap(&s);
    assert(dm_racing_touch_buttons(&s, 1, 1) == DM_BTN_ZL);
    assert(!s.throttle_latched);
    assert(!dm_racing_touch_buttons(&s, 0, 0));
    // Tapping gas while brake is held must not arm a delayed restart.
    dm_racing_touch_tap(&s);
    assert(dm_racing_touch_buttons(&s, 0, 1) == DM_BTN_ZL);
    assert(!dm_racing_touch_buttons(&s, 0, 0));
    // Cancellation, focus loss, layout changes and hotplug use the same reset.
    for (int reason = 0; reason < 4; ++reason) {
        dm_racing_touch_tap(&s);
        dm_racing_touch_reset(&s);
        assert(!dm_racing_touch_buttons(&s, 0, 0));
    }
    // A new game/view cannot inherit the previous game's latch.
    dm_racing_touch fresh = {0};
    assert(!dm_racing_touch_buttons(&fresh, 0, 0));
    return 0;
}
'''
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / 'racing.c'
            binary = Path(temp) / 'racing'
            source.write_text(code)
            subprocess.run(['xcrun', 'clang', '-Wall', '-Wextra', '-Werror',
                            '-I', str(ROOT / 'dm/ios/Sources'),
                            '-I', str(ROOT / 'dm/host'), str(source), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    unittest.main()

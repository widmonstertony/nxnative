// The boot window size a WINDOW_SIZE frame-step stub takes (the fixups table's WINDOW_SIZE; Ocarina of Time's patches.py window_size: nnMain's window, and the graphics init's 3D base and crop): the loader writes it into the
// state page at +0x2c0 as a u64 width | height << 32 (loader.c dm_fps_state_apply). From DM_DISPLAY_BUFFER, docked only: 2160 → 3840x2160, 1440 → 2560x1440, 1080 → 1920x1080;
// anything else (unset, 720, max, handheld) is 0, the game's own size. A header of its own so the rule is tested without the loader (dm/host/tests/t_window_size.c)
#pragma once
#include <stdint.h>
#include <string.h>
#define DM_WINDOW_SIZE_OFF 0x2c0
static inline uint64_t dm_window_size_word(const char *display_buffer, int docked) {
    static const struct { const char *v; uint32_t w, h; } k[] = {{"2160", 3840, 2160}, {"1440", 2560, 1440}, {"1080", 1920, 1080}};
    if (!docked || !display_buffer) return 0;
    for (unsigned i = 0; i < sizeof k / sizeof *k; i++) if (!strcmp(display_buffer, k[i].v)) return k[i].w | (uint64_t)k[i].h << 32;
    return 0;
}

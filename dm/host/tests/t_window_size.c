// The boot window size word WINDOW_SIZE stubs read (window_size.h; Ocarina of Time's patches.py window_size: nnMain's window and the graphics init's 3D base and crop at
// arg+8, both a u32 width then a u32 height, so the word's low half is the width):
// 1. the rule: DM_DISPLAY_BUFFER 2160 / 1440 / 1080 docked give 3840x2160 / 2560x1440 / 1920x1080 as width | height << 32; unset, 720, max, anything else and handheld give 0,
//    the game's own 2560x1440;
// 2. the loader: dm_fps_state_apply writes it at state +0x2c0 for a module whose fixups table declares WINDOW_SIZE, and leaves that word alone for one that does not.
// No game files or guest code needed
#include "../hle.c"
#include "../loader.c"
#include <assert.h>
#include <stdio.h>

void mtl_present_screen(uint32_t w, uint32_t h) { (void)w; (void)h; }   // loader.c: DM_SCREEN_ASPECT only
static int opmode = 1;
int dm_opmode(void) { return opmode; }
const struct dm_profile *dm_profile(void) {
    static const struct dm_profile profile = {.fps_target = DM_GAME_FPS_TARGET};
    return &profile;
}
struct dm_flags g_flag;
uint64_t unimpl_stubs[MAX_STUB];
uint64_t now_ns(void) { return 0; }
uint64_t guest_ns(void) { return 0; }
uint64_t guest_ticks(void) { return 0; }
void guest_clock_read_wait(void) {}
void hlecount_seal(void) {}
int svc_nro_deactivate(module_t *m) { m->loaded = 0; return 1; }
void thr_svc_enter(uint64_t *r, uint64_t a) { (void)r; (void)a; }
void thr_svc_leave(void) {}
void dm_spin_wait(uint64_t r, uint64_t a) { (void)r; (void)a; }
uint64_t svc_dispatch(int n, uint64_t *r, uint64_t a) { (void)n; (void)r; (void)a; return 0; }
void *hlecount_wrap(const char *kind, const char *name, void *fn) { (void)kind; (void)name; return fn; }

#define W(w, h) ((uint64_t)(w) | (uint64_t)(h) << 32)
static uint64_t applied(module_t *m, const char *display_buffer, int mode) {
    if (display_buffer) setenv("DM_DISPLAY_BUFFER", display_buffer, 1); else unsetenv("DM_DISPLAY_BUFFER");
    opmode = mode;
    uint64_t sentinel = 0x5a5a5a5a5a5a5a5aull; memcpy(m->base + m->fps_state_off + DM_WINDOW_SIZE_OFF, &sentinel, 8);
    install_fps_state(m); dm_fps_state_apply();
    uint64_t v; memcpy(&v, m->base + m->fps_state_off + DM_WINDOW_SIZE_OFF, 8); return v;
}

int main(void) {
    // 1. the rule
    assert(DM_WINDOW_SIZE_OFF == 0x2c0);   // the offset the stub reads (ldr x8,[x16,#0x2c0], 0xf9416208)
    assert(dm_window_size_word("2160", 1) == W(3840, 2160));
    assert(dm_window_size_word("1440", 1) == W(2560, 1440));
    assert(dm_window_size_word("1080", 1) == W(1920, 1080));
    assert(dm_window_size_word("2160", 0) == 0);   // handheld: the game's own
    const char *zero[] = {NULL, "", "720", "max", "4k", "2160 ", "02160"};
    for (unsigned i = 0; i < sizeof zero / sizeof *zero; i++) assert(dm_window_size_word(zero[i], 1) == 0);
    // 2. the loader, on a module laid out as the rewriter leaves Ocarina's main: key page, then the state page
    static module_t m; strcpy(m.name, "main"); m.size = 0x20000; m.base = calloc(1, m.size);
    m.key_page_off = 0x10000; m.key_page_size = 0x4000; m.fps_state_off = 0x14000;
    unsetenv("DM_FPS_TARGET"); unsetenv("DM_RENDER_SCALE"); unsetenv("DM_DYNAMIC_RESOLUTION"); unsetenv("DM_SCREEN_ASPECT");
    m.window_size = 1;
    assert(applied(&m, "2160", 1) == W(3840, 2160));
    assert(applied(&m, "1440", 1) == W(2560, 1440));
    assert(applied(&m, "1080", 1) == W(1920, 1080));
    assert(applied(&m, "2160", 0) == 0);   // handheld
    assert(applied(&m, NULL, 1) == 0);
    assert(applied(&m, "max", 1) == 0);    // vi's largest screen: not a window size
    m.window_size = 0;                      // a build without the stub: the word is not the host's to write
    assert(applied(&m, "2160", 1) == 0x5a5a5a5a5a5a5a5aull);
    puts("window size word: 2160 / 1440 / 1080 docked as width | height << 32, handheld, unset and anything else 0 (the game's own); "
         "the loader writes it at state +0x2c0 only for a WINDOW_SIZE build");
    free(m.base); return 0;
}

// nn::vi::QueryDisplayBufferMaxResolution (hle_vi.c): 0 720p, 1 1080p, 2 1440p, 3 4K. Handheld: the Switch 2's own 1080p screen; docked: the largest of the four the window's screen
// holds (1080p when it is not known). DM_DISPLAY_BUFFER=720|1080|1440|2160 fixes it in both modes; max takes the largest screen attached instead of the window's (a 4K TV beside a
// MacBook whose 3456x2234 screen holds only 1440p); anything else is said once in red and changes nothing. t_vi_hdr_front.c holds the screens and the log
#include "../../gfx/hle_vi.c"
#include <assert.h>

extern int t_disp_w, t_disp_h, t_big_w, t_big_h, t_hdr_lines, t_log_lines;
extern char t_last_line[512];
static int t_opmode = 1;
uint64_t dm_nvn_frame_count(void) { return 0; }
void mtl_present_progress(uint64_t *q, uint64_t *d) { *q = *d = 0; }
double mtl_presented_time(uint64_t n) { (void)n; return 0; }
void mtl_present_layer(uint32_t w, uint32_t h) { (void)w; (void)h; }
uint64_t guest_ns(void) { return 0; }
uint64_t now_ns(void) { return 0; }
int dm_sdk_ounce(void) { return 0; }
int dm_opmode(void) { return t_opmode; }

static uint32_t ask(int opmode, int dw, int dh, int bw, int bh, const char *env) {
    t_opmode = opmode; t_disp_w = dw; t_disp_h = dh; t_big_w = bw; t_big_h = bh;
    if (env) setenv("DM_DISPLAY_BUFFER", env, 1); else unsetenv("DM_DISPLAY_BUFFER");
    uint32_t r = 0xaa; assert(h_vi_BufMaxRes(&r, &g_display) == RES_OK); return r;
}

int main(void) {
    // Unset: as before
    assert(ask(1, 3456, 2234, 3840, 2160, NULL) == 2);   // docked on the MacBook's screen: 1440p (2234 rows hold no 2160)
    assert(ask(1, 3840, 2160, 3840, 2160, NULL) == 3);   // docked on the 4K TV: 4K
    assert(ask(1, 1920, 1080, 0, 0, NULL) == 1);
    assert(ask(1, 2160, 3840, 0, 0, NULL) == 3);         // a portrait screen counts by its long side
    assert(ask(1, 0, 0, 0, 0, NULL) == 1);               // no screen known: 1080p
    assert(ask(0, 3840, 2160, 3840, 2160, NULL) == 1);   // handheld: the Switch 2's own 1080p screen
    // Fixed values, in both modes, whatever the screens
    assert(ask(1, 3456, 2234, 0, 0, "2160") == 3 && ask(0, 1280, 800, 0, 0, "2160") == 3);
    assert(ask(1, 3840, 2160, 0, 0, "720") == 0 && ask(1, 3840, 2160, 0, 0, "1080") == 1 && ask(1, 0, 0, 0, 0, "1440") == 2);
    // max: the largest screen attached, not the window's
    assert(ask(1, 3456, 2234, 3840, 2160, "max") == 3);
    assert(ask(0, 3456, 2234, 3840, 2160, "max") == 3);  // in handheld mode too, as the fixed values
    assert(ask(1, 3456, 2234, 0, 0, "max") == 2);        // largest not known: the window's screen, as unset
    // Not one of them: said once in red, the display's own answer stands
    int before = t_log_lines;
    assert(ask(1, 3456, 2234, 3840, 2160, "4k") == 2);
    assert(t_log_lines > before && strstr(t_last_line, "[RED] DM_DISPLAY_BUFFER=4k"));
    before = t_log_lines; assert(ask(1, 3456, 2234, 3840, 2160, "4k") == 2 && t_log_lines == before);
    puts("vi display buffer: 1440p on the MacBook, 4K on the TV, 1080p handheld or unknown; DM_DISPLAY_BUFFER fixed values in both modes, max by the largest screen, others ignored once in red");
    return 0;
}

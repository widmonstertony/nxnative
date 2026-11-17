// nn::vi's HDR answers (hle_vi.c): SDR by default; HDR10 (HdrOutputFormat 1) while the present draws into an HDR layer (front_hdr_present, DM_HDR_PRESENT), or the format
// DM_HDR forces; the peak from DM_HDR_PEAK, else the screen's estimate (front_screen_peak_nits), else 1000; the extended content luminance maximum forwarded to the HDR10
// metadata (front_hdr_content_max_nits) only with HDR on; the layer metadata logged once per change of value, at most 200 lines. hle_vi.c reads its environment once, so each
// case runs in a child process of its own (t_vi_hdr_front.c holds the front end and the log)
#include "../../gfx/hle_vi.c"
#include <assert.h>
#include <sys/wait.h>
#include <unistd.h>

extern int t_front_hdr, t_front_peak, t_content_calls, t_log_lines, t_hdr_lines, t_gamut, t_gamut_calls;
extern float t_content_max;
extern char t_last_line[512];

// hle_vi.c's other dependencies (the frame history, the buffer size query), unused here
uint64_t dm_nvn_frame_count(void) { return 0; }
void mtl_present_progress(uint64_t *q, uint64_t *d) { *q = *d = 0; }
double mtl_presented_time(uint64_t n) { (void)n; return 0; }
void mtl_present_layer(uint32_t w, uint32_t h) { (void)w; (void)h; }
uint64_t guest_ns(void) { return 0; }
uint64_t now_ns(void) { return 0; }
int dm_sdk_ounce(void) { return 0; }
int dm_opmode(void) { return 0; }

typedef struct { uint8_t on; uint32_t fmt; uint16_t peak; } status;
static status query(void) {
    status s = {0xaa, 0xaaaaaaaa, 0xaaaa};
    assert(h_vi_HdrStatus(&s.on, &s.fmt, &s.peak, &g_display) == RES_OK);
    return s;
}
static void expect(status s, int on, uint32_t fmt, uint16_t peak) {
    if (s.on != on || s.fmt != fmt || s.peak != peak) { fprintf(stderr, "HDR status on %u fmt %u peak %u, want %d %u %u\n", s.on, s.fmt, s.peak, on, fmt, peak); assert(0); }
}
// The metadata a frame of Mario Kart World 1.8.0 sends in HDR (its probe run): gamut 1, tone mapping 2, standard 0..203, extended 0..ext, the Bezier curve 0 / 1 / 0.8
static void frame_metadata(uint32_t ext) {
    assert(h_vi_HdrGamut(&g_layer, 1) == RES_OK);
    assert(h_vi_HdrToneMap(&g_layer, 2) == RES_OK);
    assert(h_vi_HdrStdLum(&g_layer, 0, 203) == RES_OK);
    assert(h_vi_HdrExtLum(&g_layer, 0, ext) == RES_OK);
    assert(h_vi_HdrBezier(&g_layer, 0, 1, 0.8f) == RES_OK);
}

// One case in a child: env is "NAME=value" pairs (NULL-terminated), front the front end's HDR kind and peak
static void run(const char *name, const char *const *env, int front, int front_peak, void (*body)(void)) {
    pid_t p = fork(); assert(p >= 0);
    if (!p) {
        unsetenv("DM_HDR"); unsetenv("DM_HDR_PEAK");
        for (; env && *env; env++) { char kv[64]; snprintf(kv, sizeof kv, "%s", *env); char *eq = strchr(kv, '='); *eq = 0; setenv(kv, eq + 1, 1); }
        t_front_hdr = front; t_front_peak = front_peak;
        body(); _exit(0);
    }
    int st; assert(waitpid(p, &st, 0) == p);
    if (!WIFEXITED(st) || WEXITSTATUS(st)) { fprintf(stderr, "t_vi_hdr: case \"%s\" failed\n", name); exit(1); }
    printf("  %s: ok\n", name);
}

static void sdr_by_default(void) {
    expect(query(), 0, 0, 0);
    frame_metadata(1000);
    assert(t_content_calls == 0 && t_gamut_calls == 0 && t_hdr_lines == 0);   // SDR: nothing forwarded, nothing logged
    uint16_t pw = 0; assert(h_vi_PaperWhite(&pw, &g_display) == RES_OK && pw == 203);
}
static void hdr_layer_screen_peak(void) {   // DM_HDR_PRESENT on an XDR MacBook Pro: headroom 16, about 1600 nits
    expect(query(), 1, 1, 1600);
    expect(query(), 1, 1, 1600);
    assert(t_hdr_lines == 1 && strstr(t_last_line, "format 1, peak 1600 nits (DM_HDR_PRESENT)"));   // the answer is logged once, naming why
    frame_metadata(1000);
    assert(t_content_calls == 1 && t_content_max == 1000);
    frame_metadata(710);                     // the game lowers its extended maximum
    assert(t_content_calls == 2 && t_content_max == 710);
    assert(h_vi_HdrExtLum(&g_layer, 0, 0) == RES_OK && t_content_calls == 2);   // a maximum of 0 says nothing: the metadata keeps 710
    assert(t_gamut == 1);   // Mario Kart World's content gamut, Display P3 content in a BT.2020 signal, forwarded to the front end (front_hdr_content_gamut)
    assert(h_vi_HdrGamut(&g_layer, 0) == RES_OK && t_gamut == 0);   // Ocarina of Time's, 0 (BT.709 content)
    assert(h_vi_HdrGamutClear(&g_layer) == RES_OK && t_gamut == -1);   // cleared: none
}
static void hdr_layer_no_screen_peak(void) { expect(query(), 1, 1, 1000); }   // the screen's EDR not known
static void hdr_peak_env_wins(void) { expect(query(), 1, 1, 800); }
static void hdr_peak_env_out_of_range(void) { expect(query(), 1, 1, 1000); }
static void probe_forces_format(void) {   // DM_HDR forces the answer without an HDR layer, with its own format; the extended maximum is forwarded as well
    expect(query(), 1, 2, 1000);
    assert(strstr(t_last_line, "format 2, peak 1000 nits (DM_HDR probe)"));
    frame_metadata(1000);
    assert(t_content_calls == 1 && t_content_max == 1000);
}
static void probe_zero_is_sdr(void) { expect(query(), 0, 0, 0); }   // DM_HDR=0 with no HDR layer
static void metadata_logged_on_change_capped(void) {
    for (int i = 0; i < 10; i++) frame_metadata(1000);
    assert(t_hdr_lines == 5);                // five kinds, each logged once while its values stay
    frame_metadata(710);
    assert(t_hdr_lines == 6 && strstr(t_last_line, "extended luminance range 0 710 0"));
    for (int i = 0; i < 400; i++) assert(h_vi_HdrBezier(&g_layer, 0, 1, (float)i / 400) == RES_OK);   // a curve that changes every frame
    assert(t_hdr_lines == 200);              // capped
    assert(h_vi_HdrBezierClear(&g_layer) == RES_OK && h_vi_HdrGamutClear(&g_layer) == RES_OK && h_vi_HdrToneMapClear(&g_layer) == RES_OK);
    assert(t_hdr_lines == 200);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    puts("vi HDR answers:");
    run("SDR by default", NULL, 0, 1600, sdr_by_default);
    run("HDR layer: HDR10 at the screen's peak, extended maximum forwarded", NULL, 1, 1600, hdr_layer_screen_peak);
    run("HDR layer, screen peak not known: 1000 nits", NULL, 1, 0, hdr_layer_no_screen_peak);
    run("DM_HDR_PEAK wins over the screen", (const char *[]){"DM_HDR_PEAK=800", NULL}, 1, 1600, hdr_peak_env_wins);
    run("DM_HDR_PEAK out of range: 1000 nits", (const char *[]){"DM_HDR_PEAK=20000", NULL}, 1, 1600, hdr_peak_env_out_of_range);
    run("DM_HDR=2 forces its format", (const char *[]){"DM_HDR=2", NULL}, 0, 0, probe_forces_format);
    run("DM_HDR=0 without an HDR layer: SDR", (const char *[]){"DM_HDR=0", NULL}, 0, 1600, probe_zero_is_sdr);
    run("metadata logged on change, at most 200 lines", (const char *[]){"DM_HDR=1", NULL}, 0, 0, metadata_logged_on_change_capped);
    puts("vi HDR answers: 8 cases ok (gamut forwarded with HDR on)");
    return 0;
}

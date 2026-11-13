#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

static int dz_clock_gettime(clockid_t clock, struct timespec *ts) { (void)clock; *ts = (struct timespec){.tv_sec = 1}; return 0; }
static int dz_usleep(useconds_t usec) { (void)usec; return 0; }
#define clock_gettime dz_clock_gettime
#define usleep dz_usleep
#include "../hle_hid.c"
#undef clock_gettime
#undef usleep

static int g_mode = 1;
int dm_opmode(void) { return g_mode; }
uint64_t guest_ns(void) { return 1000000000ull; }
uint64_t now_ns(void) { return 1000000000ull; }
uint64_t guest_ns_at_host_time(uint64_t host_ns) { return host_ns; }
int guest_clock_pinned(void) { return 0; }
uint64_t dm_guest_frame(void) { return 0; }
void dm_oe_execute(int index, const void *param, size_t n) { (void)index; (void)param; (void)n; }
void front_web_shot(const char *path) { (void)path; }
int front_ctrl_support(int min, int max) { (void)min; (void)max; return -1; }
void (*_Atomic dm_touch_observer)(const dm_touch *t, int n);
void dm_touch_set(const dm_touch *t, int n) { (void)t; (void)n; }
void dm_touch_script(const dm_touch *t, int n) { (void)t; (void)n; }
int touch_fill_n(void *out, int max, uint64_t now, int points) { (void)out; (void)max; (void)now; (void)points; return 0; }
int gesture_fill(void *out, int n, uint64_t now) { (void)out; (void)n; (void)now; return 0; }
void dm_gfx_shot_at(long frame, const char *path) { (void)frame; (void)path; }
void hle_bind_system_event(void *g, int autoclear) { (void)g; (void)autoclear; }
void hle_signal_system_event(void *g) { (void)g; }
int hle_signal_bound_system_event(void *g) { (void)g; return 1; }
void dm_gfx_texlist(int target) { (void)target; }
void dm_gfx_restop(void) {}
void dm_gfx_texraw(uint64_t serial, const char *path) { (void)serial; (void)path; }
void dm_ctl_peek(uint64_t a, int n) { (void)a; (void)n; }
void crash_dump_now(const char *why) { (void)why; }
void dm_ctl_memdump(uint64_t a, uint64_t n, const char *path) { (void)a; (void)n; (void)path; }
void dm_ctl_cvar_i32(uint64_t off, int32_t v) { (void)off; (void)v; }
void dm_ctl_cvar_f32(uint64_t off, float v) { (void)off; (void)v; }
void dm_gfx_texdump_next(const char *path) { (void)path; }
void dm_gfx_passdump_next(long n) { (void)n; }
void dm_gfx_addr_note(uint64_t a, char *note, size_t n) { (void)a; if (n) note[0] = 0; }
void dm_gfx_bufsnap(const char *key, uint64_t a, size_t n, const char *path) { (void)key; (void)a; (void)n; (void)path; }
void probe_atrace(uint64_t lo, uint64_t n) { (void)lo; (void)n; }
void dm_applet_enter(const char *name) { (void)name; }
void dm_applet_leave(void) {}
int dm_guest_as_contains(uintptr_t a) { (void)a; return 0; }

static void reset_deadzone_cache(const char *l, const char *r) {
    if (l) setenv("DM_STICK_DEADZONE_L", l, 1); else unsetenv("DM_STICK_DEADZONE_L");
    if (r) setenv("DM_STICK_DEADZONE_R", r, 1); else unsetenv("DM_STICK_DEADZONE_R");
    atomic_store(&g_stick_dz[0], -1);
    atomic_store(&g_stick_dz[1], -1);
}

static void t_percent(void) {
    assert(stick_deadzone_percent(NULL) == 0 && stick_deadzone_percent("") == 0);   // unset: the stick is left alone
    assert(stick_deadzone_percent("0") == 0 && stick_deadzone_percent("25") == 25 && stick_deadzone_percent("50") == 50);
    assert(stick_deadzone_percent("51") == 0 && stick_deadzone_percent("-3") == 0 && stick_deadzone_percent("12x") == 0 && stick_deadzone_percent("1.5") == 0);
}
static void t_unset_is_unchanged(void) {
    int32_t x = 1234, y = -4321;
    stick_deadzone_apply(&x, &y, 0);
    assert(x == 1234 && y == -4321);
}
static void t_inside_reads_centred(void) {
    int32_t x = DM_STICK_MAX / 10, y = DM_STICK_MAX / 10;   // radius 0.14, inside 20%
    stick_deadzone_apply(&x, &y, 20);
    assert(x == 0 && y == 0);
}
static void t_outside_is_rescaled_and_radial(void) {
    int32_t x = DM_STICK_MAX / 2, y = 0;   // half travel with a 20% deadzone: (0.5-0.2)/(0.8) = 0.375 of the range
    stick_deadzone_apply(&x, &y, 20);
    assert(abs(x - (int32_t)(0.375f * DM_STICK_MAX)) <= 1 && y == 0);
    int32_t dx = DM_STICK_MAX * 6 / 10, dy = DM_STICK_MAX * 6 / 10;   // a diagonal keeps its angle
    stick_deadzone_apply(&dx, &dy, 20);
    assert(dx == dy && dx > 0);
}
static void t_full_travel_stays_full(void) {
    int32_t x = DM_STICK_MAX, y = 0;
    stick_deadzone_apply(&x, &y, 50);
    assert(x == DM_STICK_MAX && y == 0);
    int32_t cx = DM_STICK_MAX, cy = DM_STICK_MAX;   // a square corner is beyond a full radius: not rotated
    stick_deadzone_apply(&cx, &cy, 30);
    assert(cx == DM_STICK_MAX && cy == DM_STICK_MAX);
    int32_t nx = -DM_STICK_MAX, ny = 0;
    stick_deadzone_apply(&nx, &ny, 10);
    assert(nx == -DM_STICK_MAX);
}
static void t_monotonic(void) {
    int32_t last = -1;
    for (int v = 0; v <= DM_STICK_MAX; v += 97) {
        int32_t x = v, y = 0;
        stick_deadzone_apply(&x, &y, 35);
        assert(x >= last); last = x;
    }
}
static void t_joy_set_deadzones(void) {
    g_mode = 1;
    uint32_t ids[] = {0, 1};
    h_hid_SetIds(ids, 2);
    h_hid_SetStyles(STYLE_FULLKEY | STYLE_HANDHELD | STYLE_JOYDUAL | STYLE_JOYLEFT | STYLE_JOYRIGHT);

    // Unset deadzones leave Joy-Con sticks untouched
    reset_deadzone_cache(NULL, NULL);
    dm_pad_players(1u);
    dm_joy_attach(0, 3);
    dm_joy_set(0, 0, DM_BTN_DOWN, 1234, -2345);
    dm_joy_set(0, 1, DM_BTN_A, -3456, 4567);
    NpadState s = {0};
    h_hid_StatesJoyDual(&s, 1, &(uint32_t){0});
    assert(s.attributes != 0 && s.lx == 1234 && s.ly == -2345 && s.rx == -3456 && s.ry == 4567);

    // Distinct left (20%) and right (30%) deadzones apply to JoyDual (side 0 = left, side 1 = right)
    reset_deadzone_cache("20", "30");
    dm_joy_set(0, 0, DM_BTN_DOWN, DM_STICK_MAX / 10, DM_STICK_MAX / 10);   // radius ~0.14 < 0.20 -> zero
    dm_joy_set(0, 1, DM_BTN_A, DM_STICK_MAX / 4, 0);                       // radius 0.25 < 0.30 -> zero on right
    h_hid_StatesJoyDual(&s, 1, &(uint32_t){0});
    assert(s.lx == 0 && s.ly == 0 && s.rx == 0 && s.ry == 0);
    assert((s.buttons & 0xffffull) == (DM_BTN_DOWN | DM_BTN_A));

    // Smooth radial rescaling outside the deadzone on paired JoyDual
    dm_joy_set(0, 0, 0, DM_STICK_MAX / 2, 0);           // (0.50 - 0.20) / 0.80 = 0.375
    dm_joy_set(0, 1, 0, DM_STICK_MAX * 65 / 100, 0);    // (0.65 - 0.30) / 0.70 = 0.500
    h_hid_StatesJoyDual(&s, 1, &(uint32_t){0});
    assert(abs(s.lx - (int32_t)(0.375f * DM_STICK_MAX)) <= 2 && s.ly == 0);
    assert(abs(s.rx - (int32_t)(0.5f * DM_STICK_MAX)) <= 2 && s.ry == 0);

    // Smooth transition across the 20% threshold on dm_joy_set
    int32_t prev = 0;
    for (int pct = 0; pct <= 100; pct += 5) {
        dm_joy_set(0, 0, 0, DM_STICK_MAX * pct / 100, 0);
        h_hid_StatesJoyDual(&s, 1, &(uint32_t){0});
        if (pct <= 20) assert(s.lx == 0);
        else assert(s.lx > 0);
        assert(s.lx >= prev);
        prev = s.lx;
    }
    assert(prev == DM_STICK_MAX);

    // Auto-split single assignment (JoyLeft on No1, JoyRight on No2)
    h_hid_JoySingle(&(uint32_t){0});
    dm_joy_set(0, 0, DM_BTN_LSL, DM_STICK_MAX * 15 / 100, 0);
    dm_joy_set(0, 1, DM_BTN_RSR, 0, -DM_STICK_MAX * 28 / 100);
    NpadState sl = {0}, sr = {0};
    h_hid_StatesJoyLeft(&sl, 1, &(uint32_t){0});
    h_hid_StatesJoyRight(&sr, 1, &(uint32_t){1});
    assert(sl.attributes != 0 && sl.lx == 0 && sl.ly == 0);
    assert(sr.attributes != 0 && sr.rx == 0 && sr.ry == 0);
    dm_joy_set(0, 0, DM_BTN_LSL, 0, DM_STICK_MAX * 60 / 100);          // (0.60 - 0.20) / 0.80 = 0.500
    dm_joy_set(0, 1, DM_BTN_RSR, -DM_STICK_MAX * 65 / 100, 0);         // -(0.65 - 0.30) / 0.70 = -0.500
    h_hid_StatesJoyLeft(&sl, 1, &(uint32_t){0});
    h_hid_StatesJoyRight(&sr, 1, &(uint32_t){1});
    assert(abs(sl.ly - DM_STICK_MAX / 2) <= 2 && sl.lx == 0);
    assert(abs(sr.rx + DM_STICK_MAX / 2) <= 2 && sr.ry == 0);

    // Independent single Joy-Con slots (sideways JoyLeft on player 1, sideways JoyRight on player 2)
    dm_joy_attach(0, 0);
    dm_pad_players(0x3u);
    dm_joy_attach(0, 1);
    dm_joy_attach(1, 2);
    dm_joy_set(0, 0, 0, -DM_STICK_MAX / 10, 0);
    dm_joy_set(1, 1, 0, DM_STICK_MAX / 5, 0);
    h_hid_StatesJoyLeft(&sl, 1, &(uint32_t){0});
    h_hid_StatesJoyRight(&sr, 1, &(uint32_t){1});
    assert(sl.lx == 0 && sl.ly == 0 && sr.rx == 0 && sr.ry == 0);
    dm_joy_set(0, 0, 0, -DM_STICK_MAX, 0);
    dm_joy_set(1, 1, 0, 0, DM_STICK_MAX);
    h_hid_StatesJoyLeft(&sl, 1, &(uint32_t){0});
    h_hid_StatesJoyRight(&sr, 1, &(uint32_t){1});
    assert(sl.lx == -DM_STICK_MAX && sr.ry == DM_STICK_MAX);

    dm_joy_attach(0, 0);
    dm_joy_attach(1, 0);
    dm_pad_players(1u);
    reset_deadzone_cache(NULL, NULL);
}
int main(void) {
    t_percent(); t_unset_is_unchanged(); t_inside_reads_centred(); t_outside_is_rescaled_and_radial(); t_full_travel_stays_full(); t_monotonic();
    t_joy_set_deadzones();
    puts("t_stick_deadzone: ok");
    return 0;
}

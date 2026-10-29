// Exact-build camera/HUD adaptation. Only saved registers change; original
// guest tables and executable pages remain untouched. See the game's note.
#include "hle.h"
#include <math.h>
#include "display_hud_geometry.h"
#include <stdatomic.h>
#include "hle_arceus_timing.inc"

static _Atomic int g_display_active;
static uint32_t g_aspect_bits;
static float g_hud_rect[4];

void dm_arceus_display_init(void) {
    const char *enabled = getenv("DM_FULLSCREEN"), *ratio = getenv("DM_ASPECT");
    if (!enabled || strcmp(enabled, "1")) return;
    double w, h; char extra;
    if (!ratio || sscanf(ratio, "%lf:%lf%c", &w, &h, &extra) != 2 ||
            !isfinite(w) || !isfinite(h) || h <= 0 || w / h < 1 || w / h > 4) return;
    module_t *m = NULL;
    for (int i = 0; i < g_nmod; i++) if (!strcmp(g_mod[i].name, "main")) m = &g_mod[i];
    if (!m || !m->base || strcmp(m->build_id, "aee8f150dda1b5a838806e1a5ea6827a") ||
            m->text_end != 0x32a5690 || m->ro_off != 0x32a6000 || m->data_off != 0x401a000 ||
            m->size < 0x401a000 || !gate_obs_present(OBS_ARCEUS_ASPECT) || !gate_obs_present(OBS_ARCEUS_HUD)) return;
    float aspect = (float)(w / h);
    memcpy(&g_aspect_bits, &aspect, sizeof aspect);
    const float native_rect[4]={0,0,1920,1080};
    if (!dm_display_hud_rect(native_rect, w/h, g_hud_rect)) return;
    atomic_store_explicit(&g_display_active, 1, memory_order_release);
    dm_game_fullscreen_activate();
    LOG("Arceus fullscreen: exact build, camera %.9f HUD %.3f,%.3f %.3fx%.3f", aspect, g_hud_rect[0], g_hud_rect[1], g_hud_rect[2], g_hud_rect[3]);
}
static void arceus_aspect(uint64_t *regs, int param) {
    if (!atomic_load_explicit(&g_display_active, memory_order_acquire)) return;
    if (param == 8 || param == 9) regs[param] = g_aspect_bits;
    else if (param == 10) {
        // The camera descriptor setter copies aspect from descriptor+0x20 to
        // camera+0x240 after construction. Preserve non-screen camera ratios;
        // only the original 16:9 value needs the device projection correction.
        uint32_t bits = (uint32_t)regs[10];
        float aspect; memcpy(&aspect, &bits, sizeof aspect);
        if (fabsf(aspect - 16.0f / 9.0f) < .00001f) {
            regs[10] = g_aspect_bits;
            static _Atomic unsigned corrected;
            unsigned n = atomic_fetch_add_explicit(&corrected, 1, memory_order_relaxed);
            if (n < 4 || (n + 1) % 600 == 0) {
                float device_aspect; memcpy(&device_aspect, &g_aspect_bits, sizeof device_aspect);
                LOG("Arceus camera descriptor: 16:9 -> %.9f, count %u", device_aspect, n + 1);
            }
        }
    }
}
static void arceus_hud(uint64_t *regs, int param) {
    (void)param;
    if (!atomic_load_explicit(&g_display_active, memory_order_acquire)) return;
    // Original code loads s0/s1 at +4, s2/s3 at +12, then returns without
    // reading x8 again. SIMD values are read by the original LDP instructions.
    static _Thread_local struct { uint32_t unused; float rect[4]; } shadow;
    float original[4], aspect;
    memcpy(original, (const char *)(uintptr_t)regs[8]+4, sizeof original);
    memcpy(&aspect, &g_aspect_bits, sizeof aspect);
    if (!dm_display_hud_rect(original, aspect, shadow.rect)) return;
    regs[8] = (uint64_t)(uintptr_t)&shadow;
}
__attribute__((constructor)) static void arceus_display_gates(void) {
    gate_obs_set(OBS_ARCEUS_ASPECT, arceus_aspect);
    gate_obs_set(OBS_ARCEUS_HUD, arceus_hud);
}

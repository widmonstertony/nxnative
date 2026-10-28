// Violet 4.0.0: native camera/HUD adaptation, not a timing or physics patch.
#include "hle.h"
#include "gate_frame.h"
#include <math.h>
#include <stdatomic.h>
static _Atomic int g_violet_display_active;
static float g_violet_camera_scale, g_violet_hud[4];
void dm_violet_display_init(void) {
    const char *enabled = getenv("DM_FULLSCREEN"), *ratio = getenv("DM_ASPECT");
    double w, h; char extra;
    if (!enabled || strcmp(enabled, "1") || !ratio ||
            sscanf(ratio, "%lf:%lf%c", &w, &h, &extra) != 2 || !isfinite(w) || !isfinite(h) ||
            h <= 0 || w / h < 1 || w / h > 4) return;
    module_t *m = NULL;
    for (int i = 0; i < g_nmod; i++) if (!strcmp(g_mod[i].name, "main")) m = &g_mod[i];
    if (!m || !m->base || strcmp(m->build_id, "709bfd66115298640155fcc4979dba15") ||
            m->text_end != 0x343fc90 || m->ro_off != 0x3440000 || m->data_off != 0x4383000 ||
            m->size < 0x4383000 || !gate_obs_present(OBS_VIOLET_CAMERA) || !gate_obs_present(OBS_VIOLET_HUD)) return;
    g_violet_camera_scale = (float)((w / h) / (16.0 / 9));
    g_violet_hud[2] = (float)(1920.0 / g_violet_camera_scale);
    g_violet_hud[0] = (1920 - g_violet_hud[2]) * .5f;
    g_violet_hud[1] = 0; g_violet_hud[3] = 1080;
    atomic_store_explicit(&g_violet_display_active, 1, memory_order_release);
    dm_game_fullscreen_activate();
    LOG("Violet fullscreen: exact build, camera scale %.9f HUD %.3f,0 %.3fx1080", g_violet_camera_scale, g_violet_hud[0], g_violet_hud[2]);
}
static void violet_camera(uint64_t *regs, int param) {
    (void)param;
    // The original LDR S16 has already executed. The next original instruction
    // writes V6, and its later consumers use the scaled camera value in S16.
    if (atomic_load_explicit(&g_violet_display_active, memory_order_acquire)) dm_gate_scale_s(regs, 16, g_violet_camera_scale);
}
static void violet_hud(uint64_t *regs, int param) {
    (void)param;
    if (!atomic_load_explicit(&g_violet_display_active, memory_order_acquire)) return;
    // The two original LDPs read +4 and +12; x8 is dead through the epilogue.
    static _Thread_local struct { uint32_t unused; float rect[4]; } shadow;
    memcpy(shadow.rect, g_violet_hud, sizeof g_violet_hud);
    regs[8] = (uint64_t)(uintptr_t)&shadow;
}
__attribute__((constructor)) static void violet_display_gates(void) {
    gate_obs_set(OBS_VIOLET_CAMERA, violet_camera);
    gate_obs_set(OBS_VIOLET_HUD, violet_hud);
}

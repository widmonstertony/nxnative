// Z-A 2.0.2 camera/HUD aspect adaptation. The author patch changes the float
// at main+0x319fc7c and replaces LDUR Q0 at main+0x1802f50. Use an offline
// observation gate instead of a code cave or runtime executable writes.
// Reference: Fl4sh9174, Z-A 2.0.2 21:9 patch; geometry follows the target screen.
#include "hle.h"
#include "za_display_geometry.h"
#include <mach/mach.h>
#include <stdatomic.h>

static _Atomic int g_za_fullscreen;
static float g_za_rect[4];
int dm_za_fullscreen_active(void) { return atomic_load_explicit(&g_za_fullscreen, memory_order_acquire); }
__attribute__((weak)) void front_za_fullscreen_ready(void) {}
void dm_za_display_init(void) {
    const char *enabled = getenv("DM_ZA_FULLSCREEN"), *ratio = getenv("DM_ZA_ASPECT");
    if (!enabled || strcmp(enabled, "1")) return;
    double w = 0, h = 0; char extra;
    if (!ratio || sscanf(ratio, "%lf:%lf%c", &w, &h, &extra) != 2 || h <= 0 || !za_display_rect(w / h, g_za_rect)) {
        LOG("[RED] Z-A fullscreen: invalid DM_ZA_ASPECT, expected width:height"); return;
    }
    module_t *m = NULL;
    for (int i = 0; i < g_nmod; i++) if (!strcmp(g_mod[i].name, "main")) m = &g_mod[i];
    if (!m || !m->base || strcmp(m->build_id, "b1f12fd919eae86ab8a978317677e64b") ||
            m->text_end != 0x3163f70 || m->ro_off != 0x3164000 || m->data_off != 0x3bc2000 ||
            m->size < 0x319fc80 || !gate_obs_present(OBS_ZA_HUD_RECT)) {
        LOG("[RED] Z-A fullscreen: exact module layout/HUD gate not available; disabled"); return;
    }
    uint32_t *p = (uint32_t *)(m->base + 0x319fc7c);
    vm_address_t at = (vm_address_t)p; vm_size_t size = 0; natural_t depth = 0;
    vm_region_submap_info_data_64_t info; mach_msg_type_number_t count;
    for (;;) {
        count = VM_REGION_SUBMAP_INFO_COUNT_64;
        if (vm_region_recurse_64(mach_task_self(), &at, &size, &depth, (vm_region_recurse_info_t)&info, &count) != KERN_SUCCESS) return;
        if (!info.is_submap) break;
        if (++depth > 16) return;
    }
    if (at > (vm_address_t)p || size < 4 || (vm_address_t)p - at > size - 4 ||
            (info.protection & (VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE)) != (VM_PROT_READ | VM_PROT_WRITE)) {
        LOG("[RED] Z-A fullscreen: aspect constant is not mapped RW/non-executable"); return;
    }
    uint32_t expected = 0x3fe38e39, bits; float aspect = (float)(w / h);
    memcpy(&bits, &aspect, sizeof bits);
    if (!__atomic_compare_exchange_n(p, &expected, bits, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
        LOG("[RED] Z-A fullscreen: original camera aspect mismatch; disabled"); return;
    }
    atomic_store_explicit(&g_za_fullscreen, 1, memory_order_release);
    front_za_fullscreen_ready();
    LOG("Z-A fullscreen: camera %.9f, HUD %.6f,%.6f %.6fx%.6f; game projection and display mapping enabled",
        aspect, g_za_rect[0], g_za_rect[1], g_za_rect[2], g_za_rect[3]);
}
static void za_hud_rect(uint64_t *regs, int param) {
    (void)param;
    if (!dm_za_fullscreen_active()) return;
    // Original LDUR reads [x9+4], then overwrites w9 with 1. A thread-local
    // shadow preserves the original table and prevents concurrent writers.
    static _Thread_local struct { uint32_t unused; float rect[4]; } shadow;
    memcpy(shadow.rect, g_za_rect, sizeof g_za_rect);
    regs[9] = (uint64_t)(uintptr_t)&shadow;
}
__attribute__((constructor)) static void za_display_gates(void) { gate_obs_set(OBS_ZA_HUD_RECT, za_hud_rect); }

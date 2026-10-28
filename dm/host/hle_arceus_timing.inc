// Arceus 1.1.1's render interval and two fixed animation steps. The observation
// sites follow the public dynamic-FPS patch's consumers, without injecting its
// code cave or changing executable pages at runtime. Only this exact build runs.
static uint8_t *g_arceus_time_base;
static uint64_t g_arceus_last_ns;
static _Atomic uint32_t g_arceus_step_bits;
static int g_arceus_target;
static uint64_t g_arceus_measure_start, g_arceus_measure_game;
static unsigned g_arceus_measure_frames;

void dm_arceus_timing_init(void) {
    const char *value = getenv("DM_ARCEUS_FPS");
    int target = !value || !strcmp(value, "120") ? 120 : !strcmp(value, "60") ? 60 : !strcmp(value, "30") ? 30 : 0;
    if (target != 30 && target != 60 && target != 120) return;
    module_t *m = NULL;
    for (int i = 0; i < g_nmod; i++) if (!strcmp(g_mod[i].name, "main")) m = &g_mod[i];
    if (!m || !m->base || strcmp(m->build_id, "aee8f150dda1b5a838806e1a5ea6827a") ||
        m->text_end != 0x32a5690 || m->ro_off != 0x32a6000 || m->data_off != 0x401a000 ||
        m->size < 0x401a000 || !gate_obs_present(OBS_ARCEUS_TIMING)) return;
    uint64_t initial;
    memcpy(&initial, m->base + 0x397e8d8, sizeof initial);
    if (initial != 33333334) { LOG("[RED] Arceus timing: unexpected original frame duration; disabled"); return; }
    g_arceus_target = target;
    g_arceus_time_base = m->base;
    float dt = 1.f / target;
    uint32_t bits; memcpy(&bits, &dt, sizeof bits);
    atomic_store(&g_arceus_step_bits, bits);
    char hz[16]; snprintf(hz, sizeof hz, "%d", target);
    setenv("DM_PRESENT_HZ", hz, 1);
    setenv("DM_PRESENT_INTERVAL", "display", 1);
    setenv("DM_PRESENT_LINK", "2", 1);
    LOG("Arceus timing: target %d, real elapsed game clock; display scheduling is not measured FPS", target);
}

static void arceus_timing(uint64_t *regs, int param) {
    if (!g_arceus_time_base) return;
    if (param == 0) {
        // guest_ns excludes time spent suspended/backgrounded. A long hitch is
        // bounded to the public patch's 15-fps step; no minimum step forces a
        // high-FPS frame to advance 1/30 second. Dropped frames keep real dt.
        uint64_t now = guest_ns();
        uint64_t elapsed = g_arceus_last_ns && now > g_arceus_last_ns ? now - g_arceus_last_ns : 1000000000ull / g_arceus_target;
        int measured = g_arceus_last_ns != 0;
        g_arceus_last_ns = now;
        if (elapsed > 66666667) elapsed = 66666667;
        __atomic_store_n((uint64_t *)(g_arceus_time_base + 0x397e8d8), elapsed, __ATOMIC_RELAXED);
        if (measured) {
            g_arceus_measure_game += elapsed;
            if (++g_arceus_measure_frames == 300) {
                double wall = (double)(now - g_arceus_measure_start) / 1e9;
                LOG("Arceus timing measured: %u frames in %.3fs (%.2f fps), game steps %.3fs, target %d",
                    g_arceus_measure_frames, wall, g_arceus_measure_frames / wall,
                    (double)g_arceus_measure_game / 1e9, g_arceus_target);
                g_arceus_measure_start = now; g_arceus_measure_game = 0; g_arceus_measure_frames = 0;
            }
        } else g_arceus_measure_start = now;
        float dt = (float)((double)elapsed / 1e9);
        uint32_t bits; memcpy(&bits, &dt, sizeof bits);
        atomic_store_explicit(&g_arceus_step_bits, bits, memory_order_release);
    } else if (param == 1) {
        // The original FMOV reads w8 next. Keep every other saved register.
        regs[8] = atomic_load_explicit(&g_arceus_step_bits, memory_order_acquire);
    } else if (param == 2) {
        // After ADD w1,w8,#1, before the original LDR w10 and NVN setter.
        regs[1] = 1;
    }
}
__attribute__((constructor)) static void arceus_timing_gate(void) {
    gate_obs_set(OBS_ARCEUS_TIMING, arceus_timing);
}

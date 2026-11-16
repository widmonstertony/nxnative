// Witcher 3 4.04a/b: FPSLocker-Warehouse B151A224A429F9A7.
// LimitFPS is separate from the dynamic-resolution controller's time budgets.
// Leave simulation delta, movie timing and frame-buffer ownership unchanged.
static void witcher_fps_tick(void) {
    if (!dm_frame_limit_unlimited()) return;
    static int logged;
    for (int i=0; i<g_nmod; i++) {
        module_t *m=&g_mod[i];
        if (strcmp(m->name,"main") || strcmp(m->build_id,"b151a224a429f9a73abb05c5a3de9468") ||
            !m->base || m->size < 0x41312e8) continue;
        const uint32_t offsets[]={0x411dcfc,0x41312b4,0x41312e4};
        uint32_t cur[3];
        for(int k=0;k<3;k++) if(!rd((uintptr_t)m->base+offsets[k],&cur[k],4)) return;
        int32_t limit;float game_ms,movie_ms;
        memcpy(&limit,&cur[0],4);memcpy(&game_ms,&cur[1],4);memcpy(&movie_ms,&cur[2],4);
        if(limit<0 || limit>1000 || !(game_ms>0 && game_ms<=1000) || !(movie_ms>0 && movie_ms<=1000)) return;
        // These are GPU resolution budgets, not waits. Preserve their values;
        // changing them is an independent image-quality policy.
        if(cur[0]) { uint32_t *p=(uint32_t *)(m->base+offsets[0]);dm_guest_write_prepare(p,4);__atomic_store_n(p,0,__ATOMIC_RELAXED); }
        if(!logged) { logged=1;LOG("main: Witcher engine LimitFPS=0 (unlimited); simulation/movie clocks unchanged; actual FPS unverified"); }
        return;
    }
}

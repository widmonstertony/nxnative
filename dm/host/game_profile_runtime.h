// A selected profile for an iOS game library. Selection is process-wide and
// happens before any guest module, graphics, or controller state is created.
#pragma once
#include <stddef.h>
#include <stdint.h>

typedef struct {
    const char *build;
    const char *ver;
} dm_display_version;

typedef struct {
    const char *id, *name, *romfs_marker, *args, *env, *feedback_snap;
    char embed_ns[3]; // two base36 characters; distinguishes signed guest sections
    uint64_t program_id, mem_reserve, mem_alias, mem_stack, app_pool;
    uint64_t mem_used, sys_resource, stdalloc_cap;
    const char *modules[8];
    size_t nmod;
    dm_display_version display_versions[32];
    size_t display_version_count;
    int mem_map_limit, present_display, core_preempt, alloc_big_align;
    int fps_target, fps_hold, present_snap, pso_mtl4, pad_layout;
    int opmode, perf_boost, tex_flush_upload, render_cond, tex_dirty_upload;
    int tex_dyn_slots, gpu_ts_segment, vconv_range;
    int shared_font_ttf; // -1: SDK/import default
    int nvn_api_major, nvn_api_minor; // -1: SDK default
} dm_game_profile;

const dm_game_profile *dm_profile_list(size_t *count);
const dm_game_profile *dm_profile_find(const char *title_id);
int dm_profile_select(const char *title_id); // only before host initialization
const dm_game_profile *dm_profile_current(void);

// The frontend expands its canvas only after an exact-build adapter is armed.
#include "hle.h"
#include <stdatomic.h>
static _Atomic int g_game_fullscreen_active;
__attribute__((weak)) void front_fullscreen_ready(void) {}
int dm_game_fullscreen_active(void) {
    return atomic_load_explicit(&g_game_fullscreen_active, memory_order_acquire);
}
void dm_game_fullscreen_activate(void) {
    atomic_store_explicit(&g_game_fullscreen_active, 1, memory_order_release);
    front_fullscreen_ready();
}

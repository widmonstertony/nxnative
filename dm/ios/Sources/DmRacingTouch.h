#ifndef DM_RACING_TOUCH_H
#define DM_RACING_TOUCH_H
#include "dm_input.h"

// Only the racing touch overlay owns this latch. Physical and keyboard input
// are combined later, so no native button is renamed or kept pressed for them.
typedef struct { int throttle_latched; } dm_racing_touch;
static inline void dm_racing_touch_reset(dm_racing_touch *s) { s->throttle_latched = 0; }
static inline void dm_racing_touch_tap(dm_racing_touch *s) { s->throttle_latched = !s->throttle_latched; }
static inline uint64_t dm_racing_touch_buttons(dm_racing_touch *s, int gas_held, int brake_held) {
    if (brake_held) {
        s->throttle_latched = 0;  // Releasing the brake must not restart the car.
        return DM_BTN_ZL;
    }
    return gas_held || s->throttle_latched ? DM_BTN_ZR : 0;
}
#endif

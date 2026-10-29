#pragma once
#include <stdint.h>
#include <ctype.h>
#include "dm_input.h"

static inline int dm_controller_is_backbone(const char *name) {
    const char *needle = "backbone";
    for (const unsigned char *p = (const unsigned char *)(name ? name : ""); *p; ++p) {
        unsigned i = 0;
        while (needle[i] && p[i] && tolower(p[i]) == needle[i]) ++i;
        if (!needle[i]) return 1;
    }
    return 0;
}
// GameController names the south/east/west/north inputs A/B/X/Y. Backbone's
// printed letters match those names; retain Nintendo positional mapping for
// other controllers. This policy never changes touch geometry or keyboard bits.
static inline uint64_t dm_controller_face_buttons(int a, int b, int x, int y, int backbone) {
    return (a ? (backbone ? DM_BTN_A : DM_BTN_B) : 0) |
           (b ? (backbone ? DM_BTN_B : DM_BTN_A) : 0) |
           (x ? (backbone ? DM_BTN_X : DM_BTN_Y) : 0) |
           (y ? (backbone ? DM_BTN_Y : DM_BTN_X) : 0);
}
// A connected physical gamepad always takes precedence over keep-touch. The
// latter still applies to keyboards and mice when no controller is present.
static inline int dm_controller_hides_touch(int controller, int keyboard, int mouse, int touch_preferred, int keep_touch) {
    return controller || (!keep_touch && (keyboard || (mouse && !touch_preferred)));
}

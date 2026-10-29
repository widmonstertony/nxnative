// Preserve a 16:9 HUD inside the device-aspect game picture.
#pragma once
#include "display_hud_geometry.h"
static inline int za_display_rect(double aspect, float rect[4]) {
    const float original[4]={0,0,1920,1080};
    return dm_display_hud_rect(original, aspect, rect);
}

#pragma once
#include <math.h>
// Adapt only a native full-screen 16:9 viewport. Menu/panel rectangles retain
// their own geometry. Preserve the native logical canvas in handheld/docked
// mode instead of replacing every intercepted rectangle with 1920x1080.
static inline int dm_display_hud_rect(const float original[4], double aspect, float result[4]) {
    if (!isfinite(aspect) || aspect < 1 || aspect > 4) return 0;
    for (int i=0;i<4;i++) if (!isfinite(original[i])) return 0;
    double w=original[2], h=original[3];
    if (w<1 || h<1 || w>16384 || h>16384 || fabs(w/h-16.0/9.0)>.005) return 0;
    double width=h*(16.0/9.0)*(16.0/9.0)/aspect;
    result[0]=original[0]+(w-width)*.5; result[1]=original[1];
    result[2]=width; result[3]=h;
    return 1;
}

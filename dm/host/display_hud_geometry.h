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
    // Fit the HUD in the native canvas on either side of 16:9. Extending
    // width beyond the canvas on a 4:3 iPad clips edge-anchored widgets.
    const double native=16.0/9.0;
    double width=w, height=h;
    if (aspect >= native) width=w*(native/aspect);
    else height=h*(aspect/native);
    result[0]=original[0]+(w-width)*.5; result[1]=original[1]+(h-height)*.5;
    result[2]=width; result[3]=height;
    return 1;
}

// Compensate Trinity's logical 1920x1080 HUD before mapping its 16:9 target
// to the wider screen. The camera uses that screen's aspect ratio as well.
#pragma once
#include <math.h>
static inline int za_display_rect(double aspect, float rect[4]) {
    if (!isfinite(aspect) || aspect < 1.0 || aspect > 4.0) return 0;
    double width = 1920.0 * (16.0 / 9.0) / aspect;
    rect[0] = (float)((1920.0 - width) * 0.5);
    rect[1] = 0; rect[2] = (float)width; rect[3] = 1080;
    return 1;
}

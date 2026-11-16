// Library preference shared by the host and both Metal backends.
#ifndef DM_FRAME_LIMIT_H
#define DM_FRAME_LIMIT_H
#include <stdlib.h>
#include <string.h>
// Absence preserves command-line/profile behavior. iOS boot supplies the
// library default explicitly; "0" in DM_FPS_TARGET still means original game.
static inline int dm_frame_limit_unlimited(void) {
    const char *p = getenv("DM_FRAME_LIMIT");
    return p && !strcmp(p, "unlimited");
}
#endif

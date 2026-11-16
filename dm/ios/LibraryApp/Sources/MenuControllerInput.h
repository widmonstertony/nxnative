#pragma once
#include <math.h>
#include <stddef.h>
#include <stdbool.h>

typedef enum { TTMenuNone, TTMenuLeft, TTMenuRight, TTMenuUp, TTMenuDown } TTMenuDirection;
enum { TTMenuOpen = 1, TTMenuSettings = 2 };
typedef struct { double x, y; } TTMenuPoint;
typedef struct {
    TTMenuDirection direction;
    double repeatAt;
    unsigned buttons;
    bool initialized;
} TTMenuInput;
typedef struct { TTMenuDirection move; unsigned pressed; } TTMenuEvent;

static TTMenuDirection TTMenuReadDirection(float dx, float dy, float sx, float sy, TTMenuDirection previous) {
    float x = sx, y = sy;
    if (fmaxf(fabsf(dx), fabsf(dy)) >= 0.5f) { x = dx; y = dy; }
    float threshold = previous == TTMenuNone ? 0.55f : 0.35f;
    if (!isfinite(x) || !isfinite(y) || fmaxf(fabsf(x), fabsf(y)) < threshold) return TTMenuNone;
    if (fabsf(x) > fabsf(y)) return x < 0 ? TTMenuLeft : TTMenuRight;
    return y > 0 ? TTMenuUp : TTMenuDown;
}
static TTMenuEvent TTMenuStep(TTMenuInput *state, TTMenuDirection direction, unsigned buttons, double now) {
    TTMenuEvent event = {TTMenuNone, 0};
    // Seed held buttons when reconnecting or returning from another screen.
    if (state->initialized) event.pressed = buttons & ~state->buttons;
    state->initialized = true;
    state->buttons = buttons;
    if (direction == TTMenuNone) { state->direction = TTMenuNone; state->repeatAt = 0; }
    else if (direction != state->direction) {
        state->direction = direction; state->repeatAt = now + 0.32; event.move = direction;
    } else if (now >= state->repeatAt) {
        state->repeatAt = now + 0.11; event.move = direction;
    }
    return event;
}
static size_t TTMenuNavigate(const TTMenuPoint *points, size_t count, size_t current, TTMenuDirection direction) {
    if (!count) return 0;
    if (current >= count) current = count - 1;
    size_t best = current;
    double bestPrimary = INFINITY, bestCross = INFINITY;
    for (size_t i = 0; i < count; i++) {
        double x = points[i].x - points[current].x, y = points[i].y - points[current].y;
        bool horizontal = direction == TTMenuLeft || direction == TTMenuRight;
        double primary = direction == TTMenuLeft ? -x : direction == TTMenuRight ? x : direction == TTMenuUp ? -y : y;
        double cross = horizontal ? fabs(y) : fabs(x);
        if (direction == TTMenuNone || primary <= 1 || (horizontal && cross > 1)) continue;
        if (primary < bestPrimary - 1 || (fabs(primary - bestPrimary) <= 1 && cross < bestCross)) {
            best = i; bestPrimary = primary; bestCross = cross;
        }
    }
    return best;
}

// Keyboard profiles publish Switch buttons separately from physical controllers. The Mac front end owns capture and events.
#pragma once
#include "dm_input.h"
#include "input_map.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define DESKTOP_KEYS 131
#define DESKTOP_MOUSE_LEFT 128
#define DESKTOP_MOUSE_RIGHT 129
#define DESKTOP_MOUSE_MIDDLE 130
#define DESKTOP_RUN (1ull << 62)

typedef struct {
    int enabled, look, movement;   // movement: 0 stick, 1 steering, 2 D-pad, 3 none
    unsigned char down[DESKTOP_KEYS];
    uint64_t binding[DESKTOP_KEYS];
    int8_t axis[DESKTOP_KEYS];   // NX2Apple function ids for the remappable stick directions
    double walk, sensitivity, dx, dy, rx, ry, quiet;
    int invert_y;
} desktop_input;

static const struct { const char *name; int code; } desktop_keys[] = {
    {"A",0},{"S",1},{"D",2},{"F",3},{"H",4},{"G",5},{"Z",6},{"X",7},{"C",8},{"V",9},
    {"Q",12},{"W",13},{"E",14},{"R",15},{"Y",16},{"T",17},{"1",18},{"2",19},{"3",20},{"4",21},
    {"6",22},{"5",23},{"9",25},{"7",26},{"8",28},{"0",29},{"O",31},{"U",32},{"I",34},{"P",35},
    {"Enter",36},{"L",37},{"J",38},{"K",40},{"N",45},{"M",46},{"Tab",48},{"Space",49},{"Escape",53},
    {"Shift",56},{"Alt",58},{"Ctrl",59},{"Left",123},{"Right",124},{"Down",125},{"Up",126},
    {"MouseLeft",DESKTOP_MOUSE_LEFT},{"MouseRight",DESKTOP_MOUSE_RIGHT},{"MouseMiddle",DESKTOP_MOUSE_MIDDLE}
};
static int desktop_key(const char *name) {
    for (size_t i = 0; i < sizeof desktop_keys / sizeof *desktop_keys; i++)
        if (!strcasecmp(name, desktop_keys[i].name)) return desktop_keys[i].code;
    return -1;
}
static int desktop_button(const char *name, uint64_t *button) {
    static const char *const names[] = {"A","B","X","Y","LS","RS","L","R","ZL","ZR","PLUS","MINUS","LEFT","UP","RIGHT","DOWN"};
    if (!strcmp(name,"RUN")) { *button = DESKTOP_RUN; return 1; }
    if (!strcmp(name,"TOUCH") || !strcmp(name,"NONE")) { *button = 0; return 1; }
    for (int i = 0; i < 16; i++) if (!strcmp(name,names[i])) { *button = 1ull << i; return 1; }
    return 0;
}
static void desktop_release(desktop_input *s) {
    memset(s->down,0,sizeof s->down);
    s->dx = s->dy = s->rx = s->ry = s->quiet = 0;
}
static int desktop_remap(desktop_input *s, const char *spec);
// Validate a whole profile before enabling it. Unknown or malformed bindings keep the classic keyboard available.
static int desktop_load(desktop_input *s, const char *path) {
    memset(s,0,sizeof *s); s->walk = s->sensitivity = 1;
    memset(s->axis, -1, sizeof s->axis);
    FILE *f = path ? fopen(path,"r") : NULL;
    if (!f) return 0;
    desktop_input next = *s;
    static const int aliases[] = {38,40,32,34,3,5,12,14,6,8,36,48,123,126,124,125};
    for (int i = 0; i < 16; i++) next.binding[aliases[i]] = 1ull << i;
    char line[1024]; int valid = 1, bindings = 0;
    while (fgets(line,sizeof line,f)) {
        if (line[0] == '#' || line[0] == '\n' || line[0] == '\r') continue;
        char *end = strpbrk(line,"\r\n"); if (end) *end = 0;
        char *value = strchr(line,'\t');
        if (!value) { valid = 0; break; }
        *value++ = 0;
        char *note = strchr(value,'\t'); if (note) *note = 0;
        if (!strcmp(line,"mouse_look")) {
            if (strcmp(value,"0") && strcmp(value,"1")) { valid = 0; break; }
            next.look = atoi(value);
        } else if (!strcmp(line,"movement")) {
            static const char *const modes[] = {"stick","steering","dpad","none"};
            int found = 0;
            for (int i = 0; i < 4; i++) if (!strcmp(value,modes[i])) { next.movement = i; found = 1; }
            if (!found) { valid = 0; break; }
        } else if (!strcmp(line,"walk_scale")) {
            char *tail; double v = strtod(value,&tail);
            if (*tail || !isfinite(v) || v <= 0 || v > 1) { valid = 0; break; }
            next.walk = v;
        } else {
            int code = desktop_key(line); uint64_t mask;
            if (code < 0 || !desktop_button(value,&mask)) { valid = 0; break; }
            next.binding[code] = mask; bindings++;
        }
    }
    if (ferror(f)) valid = 0;
    fclose(f);
    if (!valid || !bindings) return -1;
    next.enabled = 1; *s = next;
    desktop_remap(s, NULL);
    return 1;
}
// NX2Apple's DM_KEYMAP protocol moves a function, including all aliases, to one physical key.
// Profiles remain the defaults; this override is kept in the game's launcher preferences.
static int desktop_remap(desktop_input *s, const char *spec) {
    key_map map;
    memset(map.fn, -1, sizeof map.fn);
    for (int c = 0; c < DESKTOP_KEYS; c++) {
        uint64_t b = s->binding[c];
        if (b == DESKTOP_RUN) map.fn[c] = IM_RUN;
        else for (int f = 0; f < 16; f++) if (b == (1ull << f)) map.fn[c] = (int8_t)f;
    }
    if (s->movement != 3) {
        map.fn[0] = s->movement == 2 ? 12 : IM_LLEFT;
        map.fn[2] = s->movement == 2 ? 14 : IM_LRIGHT;
        if (s->movement != 1) { map.fn[13] = s->movement == 2 ? 13 : IM_LUP; map.fn[1] = s->movement == 2 ? 15 : IM_LDOWN; }
    }
    int bad = key_map_parse(&map, spec);
    for (int c = 0; c < DESKTOP_KEYS; c++) {
        int f = map.fn[c];
        s->binding[c] = f >= 0 && f < 16 ? 1ull << f : f == IM_RUN ? DESKTOP_RUN : f == IM_SHAKE ? DM_BTN_SHAKE : 0;
        s->axis[c] = f >= IM_LUP && f <= IM_RRIGHT ? (int8_t)f : -1;
    }
    return bad;
}
static void desktop_camera_tick(desktop_input *s, double dt) {
    if (dt <= 0 || !isfinite(dt)) return;
    double x = s->dx, y = -s->dy; s->dx = s->dy = 0;
    s->quiet = x || y ? 0 : s->quiet + dt;
    // NxNative Launcher's radial deadzone compensation and 18 ms stop, normalized
    // to its 120 Hz ticker so event delivery frequency does not set the turn speed.
    if (s->quiet >= 0.018) { s->rx = s->ry = 0; return; }
    if (x || y) {
        double speed = hypot(x,y);
        double deflection = fmin((3600 + speed * s->sensitivity * 700 / (120 * dt)) / DM_STICK_MAX, 1);
        s->rx = x / speed * deflection;
        s->ry = y / speed * deflection;
        if (s->invert_y) s->ry = -s->ry;
    }
}
static uint64_t desktop_sample(const desktop_input *s, int32_t axes[4]) {
    uint64_t buttons = 0;
    for (int i = 0; i < DESKTOP_KEYS; i++) if (s->down[i]) buttons |= s->binding[i];
    double scale = buttons & DESKTOP_RUN ? 1 : s->walk;
    axes[0] = axes[1] = 0;
    {
        int held[8] = {0};
        for (int c = 0; c < DESKTOP_KEYS; c++) if (s->down[c] && s->axis[c] >= IM_LUP && s->axis[c] <= IM_RRIGHT) held[s->axis[c] - IM_LUP] = 1;
        double x = held[3] - held[2], y = held[0] - held[1];
        double length = hypot(x,y);
        if (length > 1) { x /= length; y /= length; }
        axes[0] = (int32_t)(x * scale * DM_STICK_MAX); axes[1] = (int32_t)(y * scale * DM_STICK_MAX);
        axes[2] = held[7] != held[6] ? (held[7] - held[6]) * DM_STICK_MAX : (int32_t)(s->rx * DM_STICK_MAX);
        axes[3] = held[4] != held[5] ? (held[4] - held[5]) * DM_STICK_MAX : (int32_t)(s->ry * DM_STICK_MAX);
    }
    return buttons & ~DESKTOP_RUN;
}

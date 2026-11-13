// Test the production keyboard parser and state publisher without a window or game save.
#include "../desktop_input.h"
#include <assert.h>

int main(int argc, char **argv) {
    int profiles = 0;
    for (int i = 1; i < argc; i++) {
        desktop_input s;
        assert(desktop_load(&s,argv[i]) == 1 && s.enabled);
        int32_t axes[4];
        s.down[13] = 1;
        s.down[2] = 1;
        uint64_t buttons = desktop_sample(&s,axes);
        assert(hypot(axes[0],axes[1]) <= DM_STICK_MAX + 1);
        assert(!(buttons & DESKTOP_RUN));
        desktop_release(&s);
        assert(desktop_sample(&s,axes) == 0);
        assert(!axes[0] && !axes[1] && !axes[2] && !axes[3]);
        profiles++;
    }
    desktop_input s = { .enabled = 1, .walk = 0.5, .sensitivity = 1 };
    s.binding[38] = s.binding[DESKTOP_MOUSE_LEFT] = DM_BTN_A;
    s.binding[56] = DESKTOP_RUN;
    desktop_remap(&s, NULL);
    s.down[38] = s.down[DESKTOP_MOUSE_LEFT] = 1;
    int32_t axes[4];
    assert(desktop_sample(&s,axes) == DM_BTN_A);
    s.down[38] = 0;
    assert(desktop_sample(&s,axes) == DM_BTN_A);   // releasing an alias does not release the other held source
    s.down[DESKTOP_MOUSE_LEFT] = 0;
    s.down[13] = 1;
    assert(desktop_sample(&s,axes) == 0 && axes[1] == DM_STICK_MAX / 2);
    s.down[56] = 1;
    assert(desktop_sample(&s,axes) == 0 && axes[1] == DM_STICK_MAX);
    desktop_release(&s);
    assert(desktop_remap(&s,"A=49,LUp=14,Run=58") == 0);
    s.down[38] = 1; s.down[13] = 1;
    assert(desktop_sample(&s,axes) == 0 && axes[1] == 0); // old action and movement keys leave their functions
    s.down[49] = 1; s.down[14] = 1; s.down[58] = 1;
    assert(desktop_sample(&s,axes) == DM_BTN_A && axes[1] == DM_STICK_MAX);
    desktop_release(&s);
    s.dx = 5; s.dy = -3;
    desktop_camera_tick(&s,1.0 / 120);
    assert(s.rx > 0 && s.ry > 0 && s.rx <= 1 && s.ry <= 1);
    s.dx = 5; s.dy = -3; s.invert_y = 1;
    desktop_camera_tick(&s,1.0 / 120);
    assert(s.rx > 0 && s.ry < 0);
    for (int i = 0; i < 20; i++) desktop_camera_tick(&s,1.0 / 120);
    assert(s.rx == 0 && s.ry == 0);   // stopping the mouse stops the camera
    desktop_release(&s);
    assert(desktop_sample(&s,axes) == 0 && !axes[0] && !axes[1] && !axes[2] && !axes[3]);
    puts("desktop input: keyboard aliases, walk/run, diagonal speed, camera direction, stop and focus release passed");
    printf("validated %d profiles\n",profiles);
    return 0;
}

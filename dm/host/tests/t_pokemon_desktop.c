// Check the player's two Legends layouts and small-motion camera response.
#include "../desktop_input.h"
#include <assert.h>
static uint64_t press(desktop_input *s, int code) {
    int32_t a[4]; desktop_release(s); s->down[code] = 1; return desktop_sample(s,a);
}
int main(int argc, char **argv) {
    assert(argc == 3);
    for (int i = 1; i < 3; i++) {
        desktop_input s; int32_t axes[4]; assert(desktop_load(&s,argv[i]) == 1);
        assert(s.look && s.gain == 3 && s.deadzone == 0.32);
        assert(press(&s,24) == DM_BTN_PLUS && press(&s,69) == DM_BTN_PLUS);
        desktop_release(&s); s.down[56] = s.down[24] = 1;
        assert(desktop_sample(&s,axes) == DM_BTN_PLUS);
        s.down[24] = 0; assert(desktop_sample(&s,axes) == 0);
        s.down[56] = 0; desktop_sample(&s,axes);
        s.down[56] = 1; assert(desktop_sample(&s,axes) == s.binding[56]);
        assert(press(&s,27) == DM_BTN_MINUS && press(&s,78) == DM_BTN_MINUS);
        assert(press(&s,DESKTOP_MOUSE_RIGHT) == DM_BTN_ZL);
        assert(press(&s,DESKTOP_MOUSE_LEFT) == DM_BTN_ZR);
        desktop_release(&s); s.dx = 0.25; desktop_camera_tick(&s,1.0/120);
        desktop_sample(&s,axes); assert(axes[2] > 10000 && !axes[3]);
        desktop_camera_tick(&s,0.05); desktop_sample(&s,axes); assert(!axes[2] && !axes[3]);
        assert(desktop_remap(&s,"LUp=126") == 0); press(&s,126); desktop_sample(&s,axes);
        assert(axes[1] == DM_STICK_MAX);
        if (i == 2) {
            desktop_release(&s); s.down[DESKTOP_MOUSE_RIGHT] = 1;
            s.dx = 1; desktop_camera_tick(&s,1.0/120);
            uint64_t focus = desktop_sample(&s,axes);
            assert((focus & (DM_BTN_ZL|DM_BTN_R)) == (DM_BTN_ZL|DM_BTN_R));
            desktop_camera_tick(&s,0.05); focus = desktop_sample(&s,axes);
            assert(focus == DM_BTN_ZL);
            assert(press(&s,34) == DM_BTN_X); // I: top
            assert(press(&s,38) == DM_BTN_Y); // J: left
            assert(press(&s,40) == DM_BTN_B); // K: bottom
            assert(press(&s,37) == DM_BTN_A); // L: right
        }
    }
    puts("Legends: small camera motion, throw/focus, +/- and IJKL diamond passed");
}

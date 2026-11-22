// Raw HID gamepads (pad_hid.h, GitHub issue #637): the default map and DM_HID_MAP, the Xbox 360 layout of virtual pads (issue #2465), the HORI Taiko Drum layout, report 0x3F's map, raw sticks and Nintendo's descriptor (PR #989), hat directions, axis scaling, the stick dead zone and analog triggers
#include <stdio.h>
#include "../pad_hid.h"
#include "../pad_joycon.h"

static int checks, fails;
#define CHECK(c) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); } } while (0)

static void pack_stick(uint8_t *p, int x, int y) {
    p[0] = (uint8_t)(x & 0xff);
    p[1] = (uint8_t)(((x >> 8) & 0x0f) | ((y & 0x0f) << 4));
    p[2] = (uint8_t)((y >> 4) & 0xff);
}

static void test_joycon_split(void) {
    CHECK(joycon_is_pid(0x057e, 0x2006) && joycon_is_pid(0x057e, 0x2007));
    CHECK(!joycon_is_pid(0x057e, 0x2009) && !joycon_is_pid(0x045e, 0x2006));

    joycon_state jl, jr;
    joycon_init(&jl, JOYCON_PID_L);
    joycon_init(&jr, JOYCON_PID_R);
    uint8_t rep[49];
    memset(rep, 0, sizeof rep);
    CHECK(!joycon_decode_0x30(&jl, rep, sizeof rep));   // report id 0x00 rejected
    rep[0] = 0x30;
    CHECK(!joycon_decode_0x30(&jl, rep, 11));           // truncated report rejected

    // Real Joy-Con (L) 0x30 sample captured on macOS (center 1958, 2117, battery 0x4e = not charging, level 2; 0x5e = charging, level 2)
    rep[2] = 0x4e;
    pack_stick(rep + 6, 1958, 2117);
    CHECK(joycon_decode_0x30(&jl, rep, sizeof rep));
    CHECK(jl.calibrated && jl.cx == 1958 && jl.cy == 2117);
    CHECK(jl.charging == 0 && jl.battery == 2);
    rep[2] = 0x5e;
    CHECK(joycon_decode_0x30(&jl, rep, sizeof rep) && jl.charging == 1 && jl.battery == 2);
    CHECK(jl.buttons == 0 && jl.sx == 0.0f && jl.sy == 0.0f);

    // Sideways Left Joy-Con buttons: Down->A, Left->B, Right->X, Up->Y, SL->L, SR->R, L->ZL, ZL->ZR, Minus->PLUS, Capture->MINUS, LS->LS
    // Upright Left Joy-Con npad buttons (dm_joy_set): native D-pad, LSL/LSR, L/ZL, MINUS, LS
    CHECK(joycon_side(JOYCON_PID_L) == 0 && joycon_side(JOYCON_PID_R) == 1);
    rep[5] = 0x01; CHECK(joycon_decode_0x30(&jl, rep, sizeof rep) && jl.buttons == DM_BTN_A && jl.joy_buttons == DM_BTN_DOWN);
    rep[5] = 0x08; CHECK(joycon_decode_0x30(&jl, rep, sizeof rep) && jl.buttons == DM_BTN_B && jl.joy_buttons == DM_BTN_LEFT);
    rep[5] = 0x04; CHECK(joycon_decode_0x30(&jl, rep, sizeof rep) && jl.buttons == DM_BTN_X && jl.joy_buttons == DM_BTN_RIGHT);
    rep[5] = 0x02; CHECK(joycon_decode_0x30(&jl, rep, sizeof rep) && jl.buttons == DM_BTN_Y && jl.joy_buttons == DM_BTN_UP);
    rep[5] = 0x20 | 0x10; CHECK(joycon_decode_0x30(&jl, rep, sizeof rep) && jl.buttons == (DM_BTN_L | DM_BTN_R) && jl.joy_buttons == (DM_BTN_LSL | DM_BTN_LSR));
    rep[5] = 0x40 | 0x80; CHECK(joycon_decode_0x30(&jl, rep, sizeof rep) && jl.buttons == (DM_BTN_ZL | DM_BTN_ZR) && jl.joy_buttons == (DM_BTN_L | DM_BTN_ZL));
    rep[5] = 0; rep[4] = 0x01 | 0x20 | 0x08;
    CHECK(joycon_decode_0x30(&jl, rep, sizeof rep) && jl.buttons == (DM_BTN_PLUS | DM_BTN_MINUS | DM_BTN_LS) && jl.joy_buttons == (DM_BTN_MINUS | DM_BTN_LS));
    rep[4] = 0;

    // Sideways Left Joy-Con stick rotation (90 deg CCW): physical right (+X) is sideways up (+Y), physical down (-Y) is sideways right (+X)
    pack_stick(rep + 6, 1958 + 1400, 2117);
    CHECK(joycon_decode_0x30(&jl, rep, sizeof rep) && jl.sx == 0.0f && jl.sy > 0.99f && jl.joy_sx > 0.99f && jl.joy_sy == 0.0f);
    pack_stick(rep + 6, 1958, 2117 - 1400);
    CHECK(joycon_decode_0x30(&jl, rep, sizeof rep) && jl.sx > 0.99f && jl.sy == 0.0f && jl.joy_sx == 0.0f && jl.joy_sy < -0.99f);

    // Real Joy-Con (R) 0x30 sample captured on macOS (center 2067, 2415, battery 0x80 = full, not charging)
    memset(rep, 0, sizeof rep);
    rep[0] = 0x30; rep[2] = 0x80;
    pack_stick(rep + 9, 2067, 2415);
    CHECK(joycon_decode_0x30(&jr, rep, sizeof rep));
    CHECK(jr.calibrated && jr.cx == 2067 && jr.cy == 2415);
    CHECK(jr.charging == 0 && jr.battery == 4);

    // Sideways Right Joy-Con buttons: X->A, A->B, Y->X, B->Y, SL->L, SR->R, R->ZL, ZR->ZR, Plus->PLUS, RS->LS, Home->home
    // Upright Right Joy-Con npad buttons (dm_joy_set): native A/B/X/Y, RSL/RSR, R/ZR, PLUS, RS
    rep[3] = 0x02; CHECK(joycon_decode_0x30(&jr, rep, sizeof rep) && jr.buttons == DM_BTN_A && jr.joy_buttons == DM_BTN_X);
    rep[3] = 0x08; CHECK(joycon_decode_0x30(&jr, rep, sizeof rep) && jr.buttons == DM_BTN_B && jr.joy_buttons == DM_BTN_A);
    rep[3] = 0x01; CHECK(joycon_decode_0x30(&jr, rep, sizeof rep) && jr.buttons == DM_BTN_X && jr.joy_buttons == DM_BTN_Y);
    rep[3] = 0x04; CHECK(joycon_decode_0x30(&jr, rep, sizeof rep) && jr.buttons == DM_BTN_Y && jr.joy_buttons == DM_BTN_B);
    rep[3] = 0x20 | 0x10; CHECK(joycon_decode_0x30(&jr, rep, sizeof rep) && jr.buttons == (DM_BTN_L | DM_BTN_R) && jr.joy_buttons == (DM_BTN_RSL | DM_BTN_RSR));
    rep[3] = 0x40 | 0x80; CHECK(joycon_decode_0x30(&jr, rep, sizeof rep) && jr.buttons == (DM_BTN_ZL | DM_BTN_ZR) && jr.joy_buttons == (DM_BTN_R | DM_BTN_ZR));
    rep[3] = 0; rep[4] = 0x02 | 0x04 | 0x10;
    CHECK(joycon_decode_0x30(&jr, rep, sizeof rep) && jr.buttons == (DM_BTN_PLUS | DM_BTN_LS) && jr.joy_buttons == (DM_BTN_PLUS | DM_BTN_RS) && jr.home == 1);
    rep[4] = 0;

    // Sideways Right Joy-Con stick rotation (90 deg CW): physical left (-X) is sideways up (+Y), physical up (+Y) is sideways right (+X)
    pack_stick(rep + 9, 2067 - 1400, 2415);
    CHECK(joycon_decode_0x30(&jr, rep, sizeof rep) && jr.sx == 0.0f && jr.sy > 0.99f && jr.joy_sx < -0.99f && jr.joy_sy == 0.0f);
    pack_stick(rep + 9, 2067, 2415 + 1400);
    CHECK(joycon_decode_0x30(&jr, rep, sizeof rep) && jr.sx > 0.99f && jr.sy == 0.0f && jr.joy_sx == 0.0f && jr.joy_sy > 0.99f);

    // Sideways and upright 6-axis IMU motion for Left and Right Joy-Con
    memset(rep + 13, 0, 36);
    rep[1] = 7;
    // Sample 0: raw_ax = 4096 (1g toward upright top -> uay = -1), raw_az = 4096 (1g face-up support on Left, inverted on Right)
    int16_t raw_ax = 4096, raw_az_l = 4096, raw_az_r = -4096;
    memcpy(rep + 13, &raw_ax, 2); memcpy(rep + 17, &raw_az_l, 2);
    pro_motion ml = {0}, mr = {0}; pro_motion_sample msl[3] = {0}, msr[3] = {0};
    float uacc[3], urot[3];
    CHECK(joycon_motion_decode(&ml, JOYCON_PID_L, rep, sizeof rep, 50000000ULL, msl) == 3);
    // Upright (+raw_ax) gives uay = -1; Left sideways (top to right, s2_map_left_alone) gives sideways acc_x = uay = -1, acc_z = -1
    CHECK(fabsf(msl[0].acc[0] + 1.0f) < 1e-4f && fabsf(msl[0].acc[1]) < 1e-4f && fabsf(msl[0].acc[2] + 1.0f) < 1e-4f);
    joycon_motion_upright(JOYCON_PID_L, &msl[0], uacc, urot);
    CHECK(fabsf(uacc[0]) < 1e-4f && fabsf(uacc[1] + 1.0f) < 1e-4f && fabsf(uacc[2] + 1.0f) < 1e-4f && fabsf(urot[0]) < 1e-4f);
    memcpy(rep + 17, &raw_az_r, 2);
    CHECK(joycon_motion_decode(&mr, JOYCON_PID_R, rep, sizeof rep, 50000000ULL, msr) == 3);
    // Right Joy-Con sideways (top to left, s2_map_right_alone) with inverted raw Z: sideways acc_x = -uay = +1, acc_z = -1
    CHECK(fabsf(msr[0].acc[0] - 1.0f) < 1e-4f && fabsf(msr[0].acc[1]) < 1e-4f && fabsf(msr[0].acc[2] + 1.0f) < 1e-4f);
    joycon_motion_upright(JOYCON_PID_R, &msr[0], uacc, urot);
    CHECK(fabsf(uacc[0]) < 1e-4f && fabsf(uacc[1] + 1.0f) < 1e-4f && fabsf(uacc[2] + 1.0f) < 1e-4f && fabsf(urot[0]) < 1e-4f);

    // Gyro rest bias learning (~1 s of still samples removes small zero-rate drift)
    joycon_rest rest = {0};
    for (int i = 0; i < JOYCON_REST_N; i++) {
        pro_motion_sample still = {.acc = {0.0f, 0.0f, -1.0f}, .rot = {0.03f, -0.02f, 0.01f}};
        joycon_rest_apply(&rest, &still);
        if (i == JOYCON_REST_N - 1) {
            CHECK(rest.have && fabsf(still.rot[0]) < 1e-5f && fabsf(still.rot[1]) < 1e-5f && fabsf(still.rot[2]) < 1e-5f);
        }
    }

    // Hold gestures: SL+SR splits a paired half after 3 s; L/ZL (left) or R/ZR (right) joins an unpaired half after 3 s
    jl.joy_buttons = DM_BTN_LSL | DM_BTN_LSR;
    CHECK(joycon_gesture(&jl, 1) == JOYCON_GESTURE_SPLIT && joycon_gesture(&jl, 0) == JOYCON_GESTURE_NONE);
    jl.joy_buttons = DM_BTN_L;
    CHECK(joycon_gesture(&jl, 0) == JOYCON_GESTURE_JOIN && joycon_gesture(&jl, 1) == JOYCON_GESTURE_NONE);
    jl.joy_buttons = DM_BTN_ZL;
    CHECK(joycon_gesture(&jl, 0) == JOYCON_GESTURE_JOIN);
    jl.joy_buttons = DM_BTN_L | DM_BTN_LSL;
    CHECK(joycon_gesture(&jl, 0) == JOYCON_GESTURE_NONE);
    jr.joy_buttons = DM_BTN_R;
    CHECK(joycon_gesture(&jr, 0) == JOYCON_GESTURE_JOIN);
    jr.joy_buttons = DM_BTN_ZR;
    CHECK(joycon_gesture(&jr, 0) == JOYCON_GESTURE_JOIN);
    joycon_hold hold = {0};
    CHECK(!joycon_hold_update(&hold, JOYCON_GESTURE_SPLIT, 1000) && hold.kind == JOYCON_GESTURE_SPLIT);
    CHECK(!joycon_hold_update(&hold, JOYCON_GESTURE_SPLIT, 1000 + JOYCON_GESTURE_NS - 1));
    CHECK(joycon_hold_update(&hold, JOYCON_GESTURE_SPLIT, 1000 + JOYCON_GESTURE_NS));
    CHECK(!joycon_hold_update(&hold, JOYCON_GESTURE_NONE, 2000 + JOYCON_GESTURE_NS) && hold.kind == JOYCON_GESTURE_NONE);
}

int main(void) {
    pad_hid h; int32_t s[4];
    pad_hid_init(&h, NULL, PAD_HID_DEFAULT);
    CHECK(pad_hid_buttons(&h) == 0);
    h.buttons = 1u << 1; CHECK(pad_hid_buttons(&h) == DM_BTN_A);             // usage 2 (right) is A
    h.buttons = 1u << 0; CHECK(pad_hid_buttons(&h) == DM_BTN_B);             // usage 1 (bottom) is B
    h.buttons = 1u << 11 | 1u << 9; CHECK(pad_hid_buttons(&h) == (DM_BTN_PLUS | DM_BTN_ZR));
    pad_hid_init(&h, "a=1,B=2,bogus=3,ZR=99,X=,MINUS=13", PAD_HID_DEFAULT);
    h.buttons = 1u << 0; CHECK(pad_hid_buttons(&h) == DM_BTN_A);
    h.buttons = 1u << 12; CHECK(pad_hid_buttons(&h) == DM_BTN_MINUS);
    h.buttons = 1u << 9; CHECK(pad_hid_buttons(&h) == DM_BTN_ZR);           // 99 skipped: the default stays
    h.buttons = 1u << 4; CHECK(pad_hid_buttons(&h) == 0);                    // X= maps X to nothing
    pad_hid_init(&h, NULL, PAD_HID_NINTENDO);                               // Nintendo's report 0x3F: B A Y X L R ZL ZR - + LS RS
    { static const uint64_t want[12] = {DM_BTN_B, DM_BTN_A, DM_BTN_Y, DM_BTN_X, DM_BTN_L, DM_BTN_R, DM_BTN_ZL, DM_BTN_ZR, DM_BTN_MINUS, DM_BTN_PLUS, DM_BTN_LS, DM_BTN_RS};
      for (int b = 0; b < 12; b++) { h.buttons = 1u << b; CHECK(pad_hid_buttons(&h) == want[b]); } }
    h.buttons = 1u << 12 | 1u << 13; CHECK(pad_hid_buttons(&h) == 0);        // Home and Capture are not Npad buttons here
    pad_hid_init(&h, "X=13", PAD_HID_NINTENDO); h.buttons = 1u << 12; CHECK(pad_hid_buttons(&h) == DM_BTN_X);   // DM_HID_MAP still replaces entries
    // The same physical buttons keep their mapping when report 0x3F changes to 0x30, including Home/Capture overrides and the hat.
    pad_hid_init(&h, NULL, PAD_HID_NINTENDO);
    for (int b = 0; b < 12; b++) CHECK(pad_hid_nin_buttons(&h, 1ull << b, 0) == (1ull << b));
    pad_hid_init(&h, "A=1,B=2,X=13,Y=14,L=0,RIGHT=12", PAD_HID_NINTENDO);
    h.buttons = 1u << 1 | 1u << 4 | 1u << 11 | 1u << 12 | 1u << 13; h.hat = 0;
    CHECK(pad_hid_buttons(&h) == (DM_BTN_B | DM_BTN_RS | DM_BTN_X | DM_BTN_Y | DM_BTN_RIGHT | DM_BTN_UP));
    CHECK(pad_hid_nin_buttons(&h, DM_BTN_A | DM_BTN_L | DM_BTN_RS | DM_BTN_UP, 0x30) == pad_hid_buttons(&h));
    h.hat = 4; h.has[PH_ACCEL] = 1; h.axis[PH_ACCEL] = 1;
    CHECK(pad_hid_nin_buttons(&h, 0, 0) == 0);   // no stale simple-report hat or analog trigger in full mode
    pad_hid_init(&h, NULL, PAD_HID_NINTENDO); CHECK(h.layout == PAD_HID_NINTENDO);   // a raw stick, as the NANO's: rests at -0.08, reaches 0.78 either way
    CHECK(fabsf(pad_hid_raw_axis(&h, PH_X, -0.08f)) < 1e-6f);
    CHECK(fabsf(pad_hid_raw_axis(&h, PH_X, 0.27f) - 0.5f) < 1e-5f);          // half of the first reach
    CHECK(fabsf(pad_hid_raw_axis(&h, PH_X, 0.70f) - 1) < 1e-5f && fabsf(pad_hid_raw_axis(&h, PH_X, 0.31f) - 0.5f) < 1e-5f);   // past it the reach grows
    CHECK(fabsf(pad_hid_raw_axis(&h, PH_X, -0.78f) + 1) < 1e-5f);            // full on both sides, though the rest is off centre
    CHECK(fabsf(pad_hid_raw_axis(&h, PH_X, -0.08f)) < 1e-6f);
    CHECK(pad_hid_raw_axis(&h, PH_Y, 0.9f) == 1 && h.rest[PH_Y] == 0);       // held while connecting: not a rest
    pad_hid_init(&h, NULL, PAD_HID_DEFAULT); CHECK(h.layout == PAD_HID_DEFAULT);
    // Nintendo's descriptor, by its reports: buttons in 0x3F, the replies 0x21, the full report 0x30 and the subcommand output 0x01 make the protocol; 0x10 is the rumble
    { int bits = pad_hid_nin_bit(0, 0x3F, 9) | pad_hid_nin_bit(0, 0x21, 0xFF00) | pad_hid_nin_bit(0, 0x30, 0xFF00) | pad_hid_nin_bit(1, 0x01, 0xFF00);
      CHECK(pad_hid_nin_protocol(bits) && !(bits & PAD_NIN_RUMBLE) && pad_hid_nin_bit(1, 0x10, 0xFF00) == PAD_NIN_RUMBLE);
      CHECK(!pad_hid_nin_protocol(bits & ~PAD_NIN_FULL) && !pad_hid_nin_protocol(bits & ~PAD_NIN_SUBCMD) && !pad_hid_nin_protocol(bits & ~PAD_NIN_SIMPLE));
      CHECK(pad_hid_nin_lights(bits) && pad_hid_nin_lights(bits & ~PAD_NIN_FULL));
      CHECK(!pad_hid_nin_lights(bits & ~PAD_NIN_SUBCMD) && !pad_hid_nin_lights(PAD_NIN_SIMPLE));
      CHECK(pad_hid_nin_bit(0, 0x3F, 1) == 0 && pad_hid_nin_bit(0, 1, 9) == 0 && pad_hid_nin_bit(1, 0x30, 0xFF00) == 0 && pad_hid_nin_bit(0, 0x01, 9) == 0);   // an 8BitDo's buttons in report 1
    }
    pad_hid_init(&h, NULL, PAD_HID_DEFAULT);
    CHECK(pad_hid_hat(1, 1, 8) == 0 && pad_hid_hat(0, 1, 8) == -1 && pad_hid_hat(8, 0, 7) == -1 && pad_hid_hat(15, 0, 15) == -1);
    { static const uint64_t dir[8] = {DM_BTN_UP, DM_BTN_UP | DM_BTN_RIGHT, DM_BTN_RIGHT, DM_BTN_RIGHT | DM_BTN_DOWN,   // the hat's eight values, clockwise from up
                                      DM_BTN_DOWN, DM_BTN_DOWN | DM_BTN_LEFT, DM_BTN_LEFT, DM_BTN_LEFT | DM_BTN_UP};
      for (int v = 0; v < 8; v++) { h.hat = v; CHECK(pad_hid_buttons(&h) == dir[v]); } }
    h.hat = pad_hid_hat(4, 1, 8); CHECK(pad_hid_buttons(&h) == (DM_BTN_DOWN | DM_BTN_RIGHT));
    CHECK(pad_hid_axis_of(1, 0x30) == PH_X && pad_hid_axis_of(1, 0x35) == PH_RZ && pad_hid_axis_of(2, 0xC5) == PH_BRAKE && pad_hid_axis_of(1, 0x39) == -1);
    CHECK(pad_hid_norm(0, 0, 65535) == -1 && pad_hid_norm(65535, 0, 65535) == 1 && pad_hid_norm(5, 3, 3) == 0);
    h.has[PH_X] = h.has[PH_Y] = h.has[PH_Z] = h.has[PH_RZ] = 1;
    h.axis[PH_X] = 1; h.axis[PH_Y] = -1; h.axis[PH_Z] = 0.05f; h.axis[PH_RZ] = 0.04f;
    pad_hid_sticks(&h, s);
    CHECK(s[0] == DM_STICK_MAX && s[1] == DM_STICK_MAX);                     // Y up; a square-gated corner reaches full x and y
    CHECK(s[2] == 0 && s[3] == 0);                                           // inside the round dead zone
    h.axis[PH_RZ] = 0.5f; pad_hid_sticks(&h, s);
    CHECK(s[2] > 0 && s[3] < 0 && s[3] > -DM_STICK_MAX / 2);                 // past it: the small x stays, the deflection is scaled back
    h.axis[PH_X] = 0.13f; h.axis[PH_Y] = 0; pad_hid_sticks(&h, s);
    CHECK(s[0] > 0 && s[0] < DM_STICK_MAX / 50 && s[1] == 0);                // just past the edge: near 0, no jump
    h.has[PH_Z] = 0; h.has[PH_RX] = 1; h.axis[PH_RX] = -1; pad_hid_sticks(&h, s); CHECK(s[2] == -DM_STICK_MAX && s[3] == 0);   // Rx / Ry without Z
    h.has[PH_ACCEL] = 1; h.axis[PH_ACCEL] = -1; CHECK(!(pad_hid_buttons(&h) & DM_BTN_ZR));
    h.axis[PH_ACCEL] = pad_hid_norm(200, 0, 255); CHECK(pad_hid_buttons(&h) & DM_BTN_ZR);
    // The Xbox 360 layout (a virtual 045e:028e pad read as HID, Steam Link's GamePad-N, issue #2465): one-at-a-time presses of a GameSir G8 through Steam Link as macOS
    // delivered them: bottom, right, top, left, back, start, LB, RB, then the d-pad up, right, down, left
    uint8_t has[PH_AXES] = {[PH_X] = 1, [PH_Y] = 1, [PH_Z] = 1, [PH_RX] = 1, [PH_RY] = 1, [PH_RZ] = 1};
    CHECK(pad_hid_layout_for(0, 0x045e, 0x028e, has) == PAD_HID_X360);
    CHECK(pad_hid_layout_for(0, 0x045e, 0x02ea, has) == PAD_HID_DEFAULT);
    CHECK(pad_hid_layout_for(0, 0x054c, 0x028e, has) == PAD_HID_DEFAULT);
    CHECK(pad_hid_layout_for(PAD_NIN_SIMPLE, 0x045e, 0x028e, has) == PAD_HID_NINTENDO);
    has[PH_RX] = 0; CHECK(pad_hid_layout_for(0, 0x045e, 0x028e, has) == PAD_HID_DEFAULT);
    has[PH_RX] = 1; has[PH_ACCEL] = 1; CHECK(pad_hid_layout_for(0, 0x045e, 0x028e, has) == PAD_HID_DEFAULT);
    pad_hid_init(&h, NULL, PAD_HID_X360);
    { static const unsigned usage[] = {1, 2, 4, 3, 10, 9, 5, 6, 12, 15, 13, 14};
      static const uint64_t want[] = {DM_BTN_B, DM_BTN_A, DM_BTN_X, DM_BTN_Y, DM_BTN_MINUS, DM_BTN_PLUS, DM_BTN_L, DM_BTN_R, DM_BTN_UP, DM_BTN_RIGHT, DM_BTN_DOWN, DM_BTN_LEFT};
      for (unsigned i = 0; i < sizeof usage / sizeof *usage; i++) { h.buttons = 1u << (usage[i] - 1); CHECK(pad_hid_buttons(&h) == want[i]); } }
    h.buttons = 1u << 6 | 1u << 7; CHECK(pad_hid_buttons(&h) == (DM_BTN_LS | DM_BTN_RS));
    h.buttons = 0;
    CHECK(pad_hid_axis_for(PAD_HID_X360, PH_Z) == PH_BRAKE && pad_hid_axis_for(PAD_HID_X360, PH_RZ) == PH_ACCEL);
    CHECK(pad_hid_axis_for(PAD_HID_X360, PH_RX) == PH_RX && pad_hid_axis_for(PAD_HID_X360, PH_X) == PH_X);
    CHECK(pad_hid_axis_for(PAD_HID_DEFAULT, PH_Z) == PH_Z && pad_hid_axis_for(PAD_HID_DEFAULT, PH_RZ) == PH_RZ);
    h.has[PH_X] = h.has[PH_Y] = h.has[PH_RX] = h.has[PH_RY] = h.has[PH_BRAKE] = h.has[PH_ACCEL] = 1;   // the axes hidpad_found sees on it: no Z
    h.axis[PH_X] = pad_hid_norm(16384, -32768, 32767); h.axis[PH_Y] = pad_hid_norm(-32768, -32768, 32767);
    h.axis[PH_RX] = pad_hid_norm(-32768, -32768, 32767); h.axis[PH_RY] = pad_hid_norm(0, -32768, 32767);
    h.axis[PH_BRAKE] = pad_hid_norm(255, 0, 255); h.axis[PH_ACCEL] = pad_hid_norm(0, 0, 255);
    pad_hid_sticks(&h, s);
    CHECK(s[0] > DM_STICK_MAX / 3 && s[0] < DM_STICK_MAX * 2 / 3 && s[1] == DM_STICK_MAX);   // a half push stays a half push
    CHECK(s[2] == -DM_STICK_MAX && abs(s[3]) < 2);                                          // the right stick from Rx / Ry
    CHECK(pad_hid_buttons(&h) == DM_BTN_ZL);                                                // left trigger down, right one up
    pad_hid_init(&h, "A=1,B=2", PAD_HID_X360); h.buttons = 1u << 0; CHECK(pad_hid_buttons(&h) == DM_BTN_A);   // DM_HID_MAP still replaces entries
    // The Taiko Drum map needs both halves of its USB ID. Nintendo report 0x3F takes precedence.
    uint8_t taiko[PH_AXES] = {[PH_X] = 1, [PH_Y] = 1, [PH_Z] = 1, [PH_RZ] = 1};
    CHECK(pad_hid_layout_for(0, 0x0f0d, 0x00f0, taiko) == PAD_HID_TAIKO);
    CHECK(pad_hid_layout_for(0, 0x0f0d, 0x011c, taiko) == PAD_HID_DEFAULT);
    CHECK(pad_hid_layout_for(0, 0x2dc8, 0x00f0, taiko) == PAD_HID_DEFAULT);
    CHECK(pad_hid_layout_for(PAD_NIN_SIMPLE, 0x0f0d, 0x00f0, taiko) == PAD_HID_NINTENDO);
    pad_hid_init(&h, NULL, PAD_HID_TAIKO);
    { static const uint64_t want[] = {DM_BTN_Y, DM_BTN_B, DM_BTN_A, DM_BTN_X, DM_BTN_L, DM_BTN_R, DM_BTN_ZL, DM_BTN_ZR, DM_BTN_MINUS, DM_BTN_PLUS, DM_BTN_LS, DM_BTN_RS, 0, 0};
      for (unsigned i = 0; i < sizeof want / sizeof *want; i++) { h.buttons = 1u << i; CHECK(pad_hid_buttons(&h) == want[i]); } }
    pad_hid_init(&h, "A=1,Y=3", PAD_HID_TAIKO); h.buttons = 1u << 0; CHECK(pad_hid_buttons(&h) == DM_BTN_A);   // DM_HID_MAP still replaces entries
    // identical pads: a model is read here only with two or more pads and more than GameController lists, after the wait, and stops at once
    CHECK(pad_dupes_want(1, 0, 0, 1) == 0); CHECK(pad_dupes_want(2, 2, 1, 0) == 0); CHECK(pad_dupes_want(3, 3, 0, 1) == 0);
    CHECK(pad_dupes_want(2, 1, 0, 0) == -1); CHECK(pad_dupes_want(2, 1, 0, 1) == 1); CHECK(pad_dupes_want(2, 0, 0, 1) == 1);
    CHECK(pad_dupes_want(3, 1, 1, 0) == 1);   // a third pad of a model read already joins it without a wait
    CHECK(pad_dupes_want(1, 1, 1, 0) == 0);   // one unplugged: back to GameController
    test_joycon_split();
    printf("t_pad_hid: %d checks, %d failed\n", checks, fails);
    return fails != 0;
}

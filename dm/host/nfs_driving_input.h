// NFS Hot Pursuit Remastered 1.0.3: read-only exact-build control groups.
// GameLogicState::IsControlGroupEnabled (main+1c4a30) reads the four bytes
// at owner+141448: NONE, CAR, MENU, DEBUG (enum at main+d84e78).
// Its registration (1c0c38..48) obtains the wrapper from globals+13ae0;
// GOT df6918 points at globals ed95f0. The wrapper's +10 holds the owner.
// Fail closed during boot, loading, menus, photo mode, and unreadable objects.
#pragma once
#include <stdint.h>
#include <string.h>
#include "dm_input.h"
typedef int (*dm_nfs_read)(uintptr_t, void *, size_t);
static inline int dm_nfs_driving(uintptr_t base, const char *build, dm_nfs_read read) {
    if (!base || base>UINTPTR_MAX-0xeed0d8 || !build || strcmp(build, "799d1061182c1302e08e706b84ce76e5")) return 0;
    static const struct { uintptr_t off; uint32_t word; } code[] = {
        {0x1c0ae0, 0xd00061b7}, {0x1c0ae4, 0xf9448ef7},
        {0x1c4ab4, 0x52828909}, {0x1c4ab8, 0x72a00289}, {0x1c4abc, 0x38696908}
    };
    for (unsigned i=0;i<sizeof code/sizeof *code;i++) {
        uint32_t word;
        if (!read(base+code[i].off,&word,sizeof word) || word!=code[i].word) return 0;
    }
    uintptr_t wrapper, owner; uint8_t groups[4];
    if (!read(base+0xeed0d0,&wrapper,sizeof wrapper) || wrapper<0x1000 || wrapper>UINTPTR_MAX-0x10 ||
        !read(wrapper+0x10,&owner,sizeof owner) || owner<0x1000 || owner>UINTPTR_MAX-0x14144c ||
        !read(owner+0x141448,groups,sizeof groups)) return 0;
    for (unsigned i=0;i<4;i++) if (groups[i]>1) return 0;
    return groups[1]==1 && groups[2]==0 && groups[3]==0;
}
static inline uint64_t dm_nfs_driving_buttons(uint64_t buttons, int driving) {
    if (!driving) return buttons;
    return (buttons & ~(uint64_t)(DM_BTN_X|DM_BTN_Y)) |
        ((buttons & DM_BTN_X)<<1) | ((buttons & DM_BTN_Y)>>1);
}

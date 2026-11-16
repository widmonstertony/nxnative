#pragma once
#include <stdint.h>
#include <string.h>
// entry.S saves x0..x30 at 0, Q0..Q31 at 256, then NZCV/FPSR/FPCR at 768.
// A display observation may change one scalar lane without altering the other
// SIMD lanes, general registers or saved flags. Call only with a gate frame.
static inline void dm_gate_scale_s(uint64_t *frame, unsigned reg, float factor) {
    if (reg >= 32) return;
    uint8_t *lane = (uint8_t *)frame + 256 + 16 * reg;
    float value;
    memcpy(&value, lane, sizeof value);
    value *= factor;
    memcpy(lane, &value, sizeof value);
}

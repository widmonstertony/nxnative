// SPDX-License-Identifier: MIT
#pragma once
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// A data-only, build-checked stopgap for games whose own dynamic-resolution
// choices exceed the mobile GPU budget. Keep maximum target sizes unchanged:
// shrinking those independently of the game's allocations breaks its UVs.
// All addresses and original values belong in the game's contract, not here.
typedef struct {
    unsigned width, height, changed;
    const char *reason;
} dm_resolution_result;

static int dm_resolution_inside(uint64_t off, size_t len, size_t size,
                                uint64_t first, uint64_t end) {
    return off >= first && off <= end && end <= size && len <= end - off;
}

// Returns 1 when applied, 0 for another build / original, -1 for an invalid
// contract or image. Validate everything before writing even a single byte.
static int dm_resolution_levels(FILE *file, const char *build, uint8_t *image,
        size_t size, uint64_t writable_first, uint64_t writable_end,
        const char *request, dm_resolution_result *result) {
    struct { uint64_t off; unsigned n; uint8_t bytes[32]; } lists[12];
    uint32_t widths[64], heights[64];
    unsigned nl = 0, n = 0, schema = 0, cw = 0, ch = 0;
    uint64_t table = 0;
    int have_build = 0, have_table = 0, have_default = 0;
    char line[512], expected_build[65] = {0};
    *result = (dm_resolution_result){0, 0, 0, "invalid contract"};
    while (fgets(line, sizeof line, file)) {
        if (!strchr(line, '\n') && !feof(file)) return -1;
        if (line[0] == '#' || line[0] == '\n') continue;
        unsigned a, b, c; unsigned long long off; char tail, hex[65];
        if (sscanf(line, "schema\t%u %c", &a, &tail) == 1) {
            if (schema || a != 1) return -1;
            schema = a;
        } else if (sscanf(line, "build\t%64s %c", hex, &tail) == 1) {
            if (have_build++ || strlen(hex) != 32 || strspn(hex, "0123456789abcdef") != 32) return -1;
            memcpy(expected_build, hex, 33);
        } else if (sscanf(line, "default\t%ux%u %c", &a, &b, &tail) == 2) {
            if (have_default++ || !a || !b) return -1;
            cw = a; ch = b;
        } else if (sscanf(line, "table\t%llx %c", &off, &tail) == 1) {
            if (have_table++ || (off & 3)) return -1;
            table = off;
        } else if (sscanf(line, "level\t%u\t%u\t%u %c", &a, &b, &c, &tail) == 3) {
            if (a != n || n == 64 || !b || !c || (n && (b < widths[n-1] || c < heights[n-1]))) return -1;
            widths[n] = b; heights[n++] = c;
        } else if (sscanf(line, "list\t%llx\t%64s %c", &off, hex, &tail) == 2) {
            size_t len = strlen(hex);
            if (nl == 12 || !len || (len & 1) || strspn(hex, "0123456789abcdef") != len) return -1;
            lists[nl].off = off; lists[nl].n = (unsigned)len / 2;
            for (unsigned i = 0; i < lists[nl].n; i++) {
                char byte[] = {hex[2*i], hex[2*i+1], 0};
                lists[nl].bytes[i] = (uint8_t)strtoul(byte, NULL, 16);
            }
            nl++;
        } else return -1;
    }
    if (ferror(file) || schema != 1 || !have_build || !have_table || !have_default || !n || !nl) return -1;
    if (strcmp(build, expected_build)) { result->reason = "different build"; return 0; }
    if (request && !strcmp(request, "original")) { result->reason = "original requested"; return 0; }
    if (request && *request) {
        char tail;
        if (sscanf(request, "%ux%u%c", &cw, &ch, &tail) != 2 || !cw || !ch || cw > 16384 || ch > 16384) {
            result->reason = "invalid requested size"; return -1;
        }
    }
    if (!dm_resolution_inside(table, n * 8, size, writable_first, writable_end)) return -1;
    for (unsigned i = 0; i < n; i++) {
        uint32_t w, h;
        memcpy(&w, image + table + 4*i, 4);
        memcpy(&h, image + table + 4*(n+i), 4);
        if (w != widths[i] || h != heights[i]) { result->reason = "size table differs"; return -1; }
    }
    for (unsigned k = 0; k < nl; k++) {
        if (!dm_resolution_inside(lists[k].off, lists[k].n, size, writable_first, writable_end)) return -1;
        if (lists[k].off < table + n*8 && table < lists[k].off + lists[k].n) return -1;
        for (unsigned j = 0; j < k; j++)
            if (lists[k].off < lists[j].off + lists[j].n && lists[j].off < lists[k].off + lists[k].n) return -1;
        for (unsigned i = 0; i < lists[k].n; i++) if (lists[k].bytes[i] >= n) return -1;
        if (memcmp(image + lists[k].off, lists[k].bytes, lists[k].n)) { result->reason = "level list differs"; return -1; }
    }
    int top = -1;
    for (unsigned i = 0; i < n; i++) if (widths[i] <= cw && heights[i] <= ch) top = (int)i;
    if (top < 0) { result->reason = "requested size below minimum"; return -1; }
    for (unsigned k = 0; k < nl; k++) {
        int changed = 0;
        for (unsigned i = 0; i < lists[k].n; i++) {
            // Preserve choices already below the cap and their ordering.
            unsigned value = lists[k].bytes[i] < top ? lists[k].bytes[i] : (unsigned)top;
            if (value != lists[k].bytes[i]) { image[lists[k].off+i] = (uint8_t)value; changed = 1; }
        }
        result->changed += changed;
    }
    result->width = widths[top]; result->height = heights[top]; result->reason = "applied";
    return 1;
}

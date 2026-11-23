// Submit-thread per-encoder resource declarations. Dedup is optional; preserving
// the union of access flags is mandatory, including collisions and overflow.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#ifndef NVN_RESOURCE_USAGE_REALLOC
#define NVN_RESOURCE_USAGE_REALLOC realloc
#define NVN_RESOURCE_USAGE_LOCAL_REALLOC 1
#endif

enum { NVN_RESOURCE_USAGE_INLINE_CAPACITY = 512 };
typedef struct { uintptr_t resource; uint64_t usage, epoch; } nvn_resource_usage_entry;
typedef struct {
    nvn_resource_usage_entry fast[NVN_RESOURCE_USAGE_INLINE_CAPACITY];
    nvn_resource_usage_entry *overflow;
    size_t count, capacity;
    uint64_t epoch;
} nvn_resource_usage_set;

static inline void nvn_resource_usage_begin(nvn_resource_usage_set *s) {
    if (!++s->epoch) {
        memset(s->fast, 0, sizeof s->fast);
        if (s->overflow) memset(s->overflow, 0, s->capacity * sizeof *s->overflow);
        s->epoch = 1;
    }
    s->count = 0;
}

static inline void nvn_resource_usage_dispose(nvn_resource_usage_set *s) {
    free(s->overflow);
    memset(s, 0, sizeof *s);
}

static inline nvn_resource_usage_entry *nvn_resource_usage_slot(nvn_resource_usage_entry *entries,
        size_t cap, uintptr_t resource, uint64_t epoch) {
    // Take the high bits after multiplication. Metal resource objects can
    // share low address bits across allocation slabs.
    uint64_t hash = (uint64_t)(resource >> 4) * UINT64_C(0x9e3779b97f4a7c15);
    size_t at = (size_t)(hash >> 32) & (cap - 1);
    while (entries[at].epoch == epoch && entries[at].resource != resource)
        at = (at + 1) & (cap - 1);
    return &entries[at];
}

static inline int nvn_resource_usage_add(nvn_resource_usage_set *s, uintptr_t resource,
        uint64_t requested, int dedup, uint64_t *combined, int *skip) {
    nvn_resource_usage_entry *entries = s->overflow ? s->overflow : s->fast;
    size_t cap = s->overflow ? s->capacity : NVN_RESOURCE_USAGE_INLINE_CAPACITY;
    nvn_resource_usage_entry *entry = nvn_resource_usage_slot(entries, cap, resource, s->epoch);
    if (entry->epoch != s->epoch) {
        if (s->count >= cap - cap / 4) {
            if (cap > SIZE_MAX / (2 * sizeof *entries)) return 0;
            size_t new_cap = cap * 2;
            nvn_resource_usage_entry *grown = NVN_RESOURCE_USAGE_REALLOC(NULL, new_cap * sizeof *grown);
            if (!grown) return 0;
            memset(grown, 0, new_cap * sizeof *grown);
            for (size_t i = 0; i < cap; i++) {
                if (entries[i].epoch == s->epoch)
                    *nvn_resource_usage_slot(grown, new_cap, entries[i].resource, s->epoch) = entries[i];
            }
            free(s->overflow);
            s->overflow = grown;
            s->capacity = new_cap;
            entry = nvn_resource_usage_slot(grown, new_cap, resource, s->epoch);
        }
        *entry = (nvn_resource_usage_entry){.resource = resource, .epoch = s->epoch};
        s->count++;
    }
    uint64_t previous = entry->usage;
    entry->usage |= requested;
    *combined = entry->usage;
    *skip = dedup && previous == entry->usage && previous != 0;
    return 1;
}
#ifdef NVN_RESOURCE_USAGE_LOCAL_REALLOC
#undef NVN_RESOURCE_USAGE_REALLOC
#undef NVN_RESOURCE_USAGE_LOCAL_REALLOC
#endif

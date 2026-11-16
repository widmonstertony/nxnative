#pragma once
#include <strings.h>
// NFS queues a small number of FMOD blocks. At 44.1-kHz hardware the former
// 5-ms request became 278/279 guest frames per callback. Ask for <=128 device
// frames so a callback need not exhaust multiple small guest blocks at once.
// The actual route may choose another duration; always log the accepted value.
static inline double dm_audio_buffer_seconds(const char *title) {
    return title && !strcasecmp(title,"010029B0118E8000") ? 0.0025 : 0.005;
}

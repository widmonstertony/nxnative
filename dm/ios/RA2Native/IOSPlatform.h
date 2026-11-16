#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Native RA2 port helpers. No game assets, executable code, or Wine prefix. */
/* The returned font path is thread-local, valid until the next call on this
 * thread. NULL means no readable system font file was provided by CoreText. */
const char *ra2_ios_font_file(const char *face, int bold, int italic);

/* Call before entering the engine. Settings must live in the app's writable
 * container, not alongside the signed executable. Returns zero on failure. */
int ra2_ios_set_user_directory(const char *directory, char *error, size_t capacity);
int ra2_ios_settings_executable_path(char *out, size_t capacity);

/* Guarded native entry bridge. The host must bind the matching game framework
 * and configure UserData first. This function can enter the actual game. */
int TonTonRedAlertMain(int argc, char **argv);

#ifdef __cplusplus
}
#endif

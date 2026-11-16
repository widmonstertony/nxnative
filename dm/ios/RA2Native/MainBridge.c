#include <pthread.h>
#include <stdio.h>
#include <string.h>
#ifndef SDL_MAIN_HANDLED
#define SDL_MAIN_HANDLED
#endif
#include <SDL.h>
#include "IOSPlatform.h"

/* The reviewed desktop host is compiled with -Dmain=ra2_desktop_main. Its
 * process-exit behavior and game save paths still need application integration. */
extern int ra2_desktop_main(int argc, char **argv);

int TonTonRedAlertMain(int argc, char **argv) {
    if (!pthread_main_np()) {
        fprintf(stderr, "[ra2-ios] Native video must start on the UIKit main thread\n");
        return 70;
    }
    if (argc < 1 || argc > 32 || !argv) return 64;
    for (int i = 0; i < argc; i++) {
        if (!argv[i]) return 64;
        /* The desktop host expands --args files before parsing --record.
         * Reject indirection here so it cannot bypass the subprocess guard. */
        if (!strcmp(argv[i], "--record") || !strncmp(argv[i], "--record=", 9) ||
            !strcmp(argv[i], "--args") || !strncmp(argv[i], "--args=", 7)) {
            fprintf(stderr, "[ra2-ios] Desktop recording and argument files are unavailable on iOS\n");
            return 64;
        }
    }
    char settings[4096];
    if (!ra2_ios_settings_executable_path(settings, sizeof settings)) {
        fprintf(stderr, "[ra2-ios] Configure this game's writable UserData before entry\n");
        return 78;
    }
    SDL_SetMainReady();
    return ra2_desktop_main(argc, argv);
}

"""Exercise the production iOS entry guard without any game code or assets."""

import pathlib
import platform
import subprocess
import tempfile
import unittest


BRIDGE = pathlib.Path(__file__).resolve().parents[2] / "ios/RA2Native/MainBridge.c"

HARNESS = r'''
#include <assert.h>
#include <pthread.h>
#include <stddef.h>
#include <string.h>
#include "IOSPlatform.h"

static int configured = 1, path_calls, stage, desktop_calls;
static int expected_argc;
static char **expected_argv;

int ra2_ios_settings_executable_path(char *out, size_t capacity) {
    assert(stage == 0);
    path_calls++;
    if (!configured) return 0;
    assert(capacity > 20);
    strcpy(out, "/UserData/settings");
    return 1;
}
void SDL_SetMainReady(void) {
    assert(stage == 0 && path_calls == 1);
    stage = 1;
}
int ra2_desktop_main(int argc, char **argv) {
    assert(stage == 1 && argc == expected_argc && argv == expected_argv);
    desktop_calls++;
    stage = 2;
    return 23;
}
static void reset(void) {
    path_calls = stage = desktop_calls = 0;
}
static void rejected(int argc, char **argv, int code) {
    reset();
    assert(TonTonRedAlertMain(argc, argv) == code);
    assert(stage == 0 && desktop_calls == 0 && path_calls == 0);
}
static void *worker(void *unused) {
    (void)unused;
    char *args[] = {"redalert", NULL};
    rejected(1, args, 70);
    return NULL;
}
int main(void) {
    char *normal[] = {"redalert", "--game", "yr", "--mute", NULL};
    rejected(0, normal, 64);
    rejected(-1, normal, 64);
    rejected(33, normal, 64);
    rejected(1, NULL, 64);
    char *missing[] = {"redalert", NULL};
    rejected(2, missing, 64);
    const char *blocked[] = {"--record", "--record=movie", "--args", "--args=options.txt"};
    for (size_t i = 0; i < sizeof(blocked) / sizeof(blocked[0]); i++) {
        char *args[] = {"redalert", (char *)blocked[i], "options.txt", NULL};
        rejected(3, args, 64);
        /* Validate the whole argument vector before initializing SDL. */
        char *late[] = {"redalert", "--mute", (char *)blocked[i], NULL};
        rejected(3, late, 64);
    }
    reset();
    configured = 0;
    assert(TonTonRedAlertMain(4, normal) == 78);
    assert(path_calls == 1 && stage == 0 && desktop_calls == 0);
    configured = 1;
    pthread_t thread;
    assert(pthread_create(&thread, NULL, worker, NULL) == 0);
    assert(pthread_join(thread, NULL) == 0);
    reset();
    expected_argc = 4;
    expected_argv = normal;
    assert(TonTonRedAlertMain(4, normal) == 23);
    assert(stage == 2 && desktop_calls == 1 && path_calls == 1);
    return 0;
}
'''


@unittest.skipUnless(platform.system() == "Darwin", "Uses Darwin's real main-thread check")
class NativeBridgeTests(unittest.TestCase):
    def test_entry_guards_and_forwarding(self):
        with tempfile.TemporaryDirectory(prefix="ra2-bridge-") as directory:
            root = pathlib.Path(directory)
            (root / "SDL.h").write_text("void SDL_SetMainReady(void);\n")
            (root / "harness.c").write_text(HARNESS)
            output = root / "bridge-test"
            subprocess.run([
                "clang", "-std=c11", "-Wall", "-Wextra", "-Werror", "-pthread",
                "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
                "-I", str(root), "-I", str(BRIDGE.parent),
                str(BRIDGE), str(root / "harness.c"), "-o", str(output),
            ], check=True, capture_output=True, text=True)
            subprocess.run([str(output)], check=True, capture_output=True, text=True)


if __name__ == "__main__":
    unittest.main()

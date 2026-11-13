// Route C shell (LNPANDY/NX2Apple#451): compiled into each game's DmGame<title ID>.framework (project-framework.yml DmShellGame)
// alongside dm/host, front_ios.m and Gen/embed.S. ShellMain.m sets the environment, dlopens the chosen game's framework and calls
// dm_glue_start_game and dm_glue_present_game through dlsym.
// This file also provides the symbols front_ios.m takes from main.m and Launcher.swift in the one-game app, so the framework
// compiles front_ios.m, DmGamepad.m and GameMenu.swift unchanged.
#import <UIKit/UIKit.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "front.h"
#include "IndependentGameHost.h"
#include "dmsh_chain.h"
#define DM_GLUE_VERSION TONTON_GAME_HOST_VERSION

int dm_main(int argc, char **argv);   // dm/host/main.c compiled in with -Dmain=dm_main
UIViewController *front_ios_root(void);
void front_ios_focus_event(int ev);

__attribute__((used, visibility("default"))) const int dm_glue_version = DM_GLUE_VERSION;

static char **g_argv __attribute__((section("__DATA,__dm_keep")));
static int g_argc __attribute__((section("__DATA,__dm_keep")));
static int g_boot_ok;

__attribute__((used, visibility("default")))
const char *dm_glue_start_game(const char *const *argv, int argc, const void *game_image) {
    if (argc != 2 || !getenv("DM_LIBRARY_GAME_ID") || strcasecmp(getenv("DM_LIBRARY_GAME_ID"), DM_INDEPENDENT_GAME_TITLE) || !game_image) return "The game's start arguments are incomplete.";
    front_hud_env();   // before the early loading below can make a device (main.m's order)
    dm_set_game_image_header(game_image);
    for (int i = 0; i < g_argc; i++) free(g_argv[i]);
    free(g_argv);
    g_argc = argc; g_argv = calloc((size_t)argc + 1, sizeof(char *));
    for (int i = 0; i < argc; i++) g_argv[i] = strdup(argv[i]);
    dm_host_preload_start(g_argc, g_argv);   // module tables, relocation and take-over in the background while the game view comes up
    g_boot_ok = 1;
    return NULL;
}

__attribute__((used, visibility("default")))
void dm_glue_present_game(void *win) {
    UIWindow *window = (__bridge UIWindow *)win;
    if (!window) { fprintf(stderr, "[RED] shell: no window for the game view\n"); return; }
    UIViewController *game = front_ios_root();   // DmRootVC: landscape, its viewDidAppear starts the game (no settings screen: dm_show_launcher)
    window.rootViewController = game;
    [game setNeedsUpdateOfSupportedInterfaceOrientations];
    [window.windowScene requestGeometryUpdateWithPreferences:[[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscape]
                                                errorHandler:^(NSError *e) { fprintf(stderr, "shell: landscape request: %s\n", e.localizedDescription.UTF8String); }];
}

__attribute__((used, visibility("default")))
void dm_glue_focus_event(int ev) {
    front_ios_focus_event(ev);
}

// ---- what front_ios.m takes from main.m and Launcher.swift ----
static void *boot_thread(void *p) {
    (void)p;
    void crash_thread_init(void); crash_thread_init();   // crash printing must work on the host thread too (freed on pthread_exit)
    int rc = dm_main(g_argc, g_argv);
    fprintf(stderr, "boot: dm_main returned %d\n", rc);
    return NULL;
}
void front_ios_boot(void) {   // front_ios.m, once the game view exists
    static int once; if (once++ || !g_boot_ok) return;
    void front_ios_audio_session(void); front_ios_audio_session();
    pthread_attr_t a; pthread_attr_init(&a); pthread_attr_setstacksize(&a, 64u << 20);
    pthread_t t; pthread_create(&t, &a, boot_thread, NULL); pthread_detach(t);
}
int front_ios_boot_ok(void) { return g_boot_ok; }
const char *front_ios_boot_message(void) { return NULL; }
const char *front_ios_device_check(void) { return NULL; }   // main.m checks the GPU for the games (no BC textures, seedds#704) when Play is pressed, the shell does its own device handling: NULL = supported
// The shell found the data before Play (DataLocator, EngineLaunchPlan): DM_ROMFS is set and the game view only checks it is still there
int dm_locate_game_data(void) {
    const char *r = getenv("DM_ROMFS"); struct stat st;
    if (r && !stat(r, &st)) return 1;
    fprintf(stderr, "[RED] shell: the game data at %s is gone\n", r ?: "(not set)");
    return 0;
}
// The shell showed its own settings before Play: the game view starts the game at once
bool dm_show_launcher(void *view_controller, void (*done)(void)) { (void)view_controller; (void)done; return false; }

// The optional lifecycle contract is separate from the stable shader/host ABI.
// Compile this file only with NX2Apple's complete dm_host_teardown_for_shell.
__attribute__((used,visibility("default"))) const int dm_glue_shell_lifecycle = 1;
__attribute__((used,visibility("default"))) const char *dm_glue_shader_chain(void) { return "b-" DMSH_CHAIN; }
static void (*tonton_returned)(void *);
static void *tonton_return_context;
__attribute__((used,visibility("default")))
void dm_glue_set_return(void (*returned)(void *), void *context) {
    tonton_returned = returned; tonton_return_context = context;
}
static void tonton_finish_return(void) { if (tonton_returned) tonton_returned(tonton_return_context); }
void (*dm_tonton_shell_return_handler(void))(void) { return tonton_returned ? tonton_finish_return : NULL; }
static void *(*tonton_catalog)(void *);
__attribute__((used,visibility("default"))) void dm_glue_set_catalog(void *(*catalog)(void *)) { tonton_catalog = catalog; }
UIViewController *TonTonInGameCatalogController(dispatch_block_t returned) {
    return tonton_catalog ? (__bridge_transfer UIViewController *)tonton_catalog((__bridge void *)returned) : nil;
}
#include "DmGameMenu.h"
void *dm_quit_menu(void);
void *dm_game_menu(void) {
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    NSMutableArray<UIAction *> *layouts = [NSMutableArray array];
    NSArray<NSString *> *names = @[@"2D", @"3D", @"\xe8\xa7\xa6\xe5\xb1\x8f"];
    for (int i = 0; i < 3; i++) {
        if (!dm_pad_layout_offered(i)) continue;
        UIAction *action = [UIAction actionWithTitle:names[i] image:nil identifier:nil handler:^(__kindof UIAction *sender) { (void)sender; dm_pad_layout_set(i); }];
        action.state = dm_pad_layout() == i ? UIMenuElementStateOn : UIMenuElementStateOff;
        [layouts addObject:action];
    }
    [items addObject:[UIMenu menuWithTitle:@"\xe6\x89\x8b\xe6\x9f\x84\xe5\xb8\x83\xe5\xb1\x80" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:layouts]];
    if (dm_pad_toggle_offered()) {
        const int controls[] = {1,2,3,4,8,10,7,9,11,12,13,14};
        NSArray<NSString *> *names = @[@"A",@"B",@"X",@"Y",@"L",@"R",@"ZL",@"ZR",@"L3",@"R3",@"-",@"+"];
        NSMutableArray<UIAction *> *toggles = [NSMutableArray array];
        for (unsigned i = 0; i < sizeof controls / sizeof *controls; i++) {
            const int control = controls[i];
            UIAction *action = [UIAction actionWithTitle:names[i] image:nil identifier:nil handler:^(__kindof UIAction *sender) { (void)sender; dm_pad_toggle_set(control, !dm_pad_toggles(control)); }];
            action.state = dm_pad_toggles(control) ? UIMenuElementStateOn : UIMenuElementStateOff;
            [toggles addObject:action];
        }
        [items addObject:[UIMenu menuWithTitle:@"\xe5\x88\x87\xe6\x8d\xa2\xe5\xbc\x8f\xe6\x8c\x89\xe9\x94\xae" children:toggles]];
    }
    [items addObject:(__bridge_transfer UIMenu *)dm_quit_menu()];
    return (__bridge_retained void *)[UIMenu menuWithTitle:@"" children:items];
}
__attribute__((used,visibility("default"))) const unsigned char dm_game_image_marker = 1;

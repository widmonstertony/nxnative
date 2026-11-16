// Link only into a self-hosted game framework, never the shared launcher.
#import <UIKit/UIKit.h>
#include <pthread.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>
#include "IndependentGameHost.h"
#include "dmsh_chain.h"
#include "front.h"
#include "loader_image.h"
#ifdef DM_MULTI_GAME
#include "game_profile_runtime.h"
#endif

#define DM_EXPORT __attribute__((used, visibility("default")))
DM_EXPORT const int dm_glue_version = TONTON_GAME_HOST_VERSION;
#ifndef DM_INDEPENDENT_SHADER_CHAIN
#define DM_INDEPENDENT_SHADER_CHAIN DMSH_CHAIN
#endif
DM_EXPORT const char *dm_glue_shader_chain(void) { return "b-" DM_INDEPENDENT_SHADER_CHAIN; }

int dm_main(int argc, char **argv);
UIViewController *front_ios_root(void);
void front_ios_audio_session(void);
void front_ios_focus_event(int event);
static char *game_argv[3];
static BOOL prepared;
static void *(*game_catalog)(void *returnBlock);

#if defined(DM_CLASSIC_SHELF_LIFECYCLE)
DM_EXPORT const int dm_glue_shell_lifecycle = 1;
static void (*shelf_returned)(void *);
static void *shelf_context;
static pthread_t shelf_game_thread;
static BOOL shelf_started;
enum { SHELF_IDLE, SHELF_RETIRING, SHELF_COMMITTED };
static int shelf_state;

int dm_host_classic_can_return(void);
int dm_host_classic_retire_guest(int budget_ms);
int dm_host_classic_fence_for_shell(int budget_ms);
int dm_host_classic_release_for_shell(void);
int front_ios_classic_close_admission(void);
int front_ios_classic_wait_save_tasks(uint64_t timeout_ns);
void front_ios_classic_release_views(void);

DM_EXPORT void dm_glue_set_return(void (*returned)(void *), void *context) {
    shelf_returned = returned;
    shelf_context = context;
}

BOOL front_ios_classic_can_request_return(void) {
    return shelf_returned && dm_host_classic_can_return();
}

// Main only. A refusal before retirement leaves the running game intact.
// Once committed, hold the shelf closed unless every owner has acknowledged.
void front_ios_classic_request_return(void (^status)(NSString *, BOOL)) {
    if (!NSThread.isMainThread || !shelf_started || !front_ios_classic_can_request_return() ||
        shelf_state != SHELF_IDLE) {
        status(@"\u6E38\u620F\u6682\u65F6\u65E0\u6CD5\u5B89\u5168\u9000\u51FA\u3002", YES);
        return;
    }
    shelf_state = SHELF_RETIRING;
    status(@"\u6B63\u5728\u8FD4\u56DE\u6E38\u620F\u5323\u2026", NO);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int retired = dm_host_classic_retire_guest(5000);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!retired) {
                shelf_state = SHELF_IDLE;
                status(@"\u65E0\u6CD5\u5B89\u5168\u6682\u505C\u6E38\u620F\uFF0C\u8BF7\u7A0D\u540E\u518D\u8BD5\u3002", YES);
                return;
            }
            shelf_state = SHELF_COMMITTED;
            BOOL closed = front_ios_classic_close_admission();
            if (retired < 0 || !closed) {
                status(@"\u6E38\u620F\u672A\u5B8C\u6210\u9000\u51FA\uFF0C\u6682\u4E0D\u80FD\u5207\u6362\u3002", NO);
                return;
            }
            pthread_t thread = shelf_game_thread;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                int stopped = !pthread_join(thread, NULL) &&
                    front_ios_classic_wait_save_tasks(25ull * NSEC_PER_SEC) &&
                    dm_host_classic_fence_for_shell(25000) && dm_host_classic_release_for_shell();
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!stopped) {
                        status(@"\u6E38\u620F\u672A\u5B8C\u6210\u9000\u51FA\uFF0C\u6682\u4E0D\u80FD\u5207\u6362\u3002", NO);
                        return;
                    }
                    front_ios_classic_release_views();
                    free(game_argv[0]); free(game_argv[1]);
                    game_argv[0] = game_argv[1] = NULL;
                    void (*returned)(void *) = shelf_returned;
                    void *context = shelf_context;
                    shelf_returned = NULL; shelf_context = NULL;
                    fprintf(stderr, "boot: classic guest, services and GPU released (pid %d)\n", getpid());
                    returned(context);
                });
            });
        });
    });
}
#endif

DM_EXPORT void dm_glue_set_catalog(void *(*catalog)(void *returnBlock)) {
    game_catalog = catalog;
}

UIViewController *TonTonInGameCatalogController(dispatch_block_t returned) {
    return game_catalog ? (__bridge_transfer UIViewController *)game_catalog((__bridge void *)returned) : nil;
}

#ifdef DM_TONTON_MODERN_GAME
#include "DmGameMenu.h"
// The standalone app provides this hook in Swift. An independent engine
// can change its own control layout, but can't promise to tear itself down.
void *dm_game_menu(void) {
    NSMutableArray<UIAction *> *items = [NSMutableArray array];
    NSArray<NSString *> *names = @[@"2D", @"3D", @"\u89E6\u5C4F"];
    for (int i = 0; i < 3; i++) {
        if (!dm_pad_layout_offered(i)) continue;
        UIAction *action = [UIAction actionWithTitle:names[i] image:nil identifier:nil handler:^(__kindof UIAction *sender) {
            (void)sender;
            dm_pad_layout_set(i);
        }];
        action.state = dm_pad_layout() == i ? UIMenuElementStateOn : UIMenuElementStateOff;
        [items addObject:action];
    }
    return (__bridge_retained void *)[UIMenu menuWithTitle:@"\u624B\u67C4\u5E03\u5C40" children:items];
}
#endif

DM_EXPORT const char *dm_glue_start_game(const char *const *argv, int argc, const void *image) {
    if (prepared || argc != 2 || !argv || !argv[0] || !argv[1] || !image)
        return "Invalid or repeated game start.";
#ifdef DM_INDEPENDENT_GAME_TITLE
    const char *title = getenv("DM_LIBRARY_GAME_ID");
    if (!title || strcasecmp(title, DM_INDEPENDENT_GAME_TITLE))
        return "The selected game is not the one embedded in this engine.";
#ifdef DM_MULTI_GAME
    if (!dm_profile_select(DM_INDEPENDENT_GAME_TITLE)) return "The game's engine profile is missing.";
#endif
#endif
    game_argv[0] = strdup(argv[0]);
    game_argv[1] = strdup(argv[1]);
    if (!game_argv[0] || !game_argv[1] || !dm_set_game_image_header(image)) {
        free(game_argv[0]); free(game_argv[1]);
        game_argv[0] = game_argv[1] = NULL;
        return "Cannot initialize the game's signed module image.";
    }
    front_hud_env();
#if defined(DM_CLASSIC_SHELF_LIFECYCLE)
    void dm_host_classic_set_shelf_owner(void);
    dm_host_classic_set_shelf_owner();
#endif
    dm_host_preload_start(2, game_argv);
    prepared = YES;
    return NULL;
}

DM_EXPORT void dm_glue_present_game(void *window) {
    if (!prepared || !window) return;
    UIWindow *target = (__bridge UIWindow *)window;
    UIViewController *game = front_ios_root();
    target.rootViewController = game;
    if (@available(iOS 16.0, *)) {
        [game setNeedsUpdateOfSupportedInterfaceOrientations];
        [target.windowScene requestGeometryUpdateWithPreferences:
            [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscape]
            errorHandler:^(NSError *error) {
                fprintf(stderr, "boot: independent game landscape request: %s\n", error.localizedDescription.UTF8String);
            }];
    }
}

DM_EXPORT void dm_glue_focus_event(int event) {
    if (prepared) front_ios_focus_event(event);
}

static void *game_thread(void *arg) {
    (void)arg;
    static char alternate[65536];
    stack_t stack = {.ss_sp = alternate, .ss_size = sizeof alternate};
    sigaltstack(&stack, NULL);
    int status = dm_main(2, game_argv);
    fprintf(stderr, "boot: independent game returned %d\n", status);
    return NULL;
}

void front_ios_boot(void) {
    static BOOL started;
    if (!prepared || started) return;
    front_ios_audio_session();
    pthread_attr_t attr;
    if (pthread_attr_init(&attr)) return;
    pthread_t thread;
    int error = pthread_attr_setstacksize(&attr, 64u << 20);
    if (!error) error = pthread_create(&thread, &attr, game_thread, NULL);
    pthread_attr_destroy(&attr);
    if (error) {
        fprintf(stderr, "[RED] boot: independent game thread: %s\n", strerror(error));
        return;
    }
    started = YES;
#if defined(DM_CLASSIC_SHELF_LIFECYCLE)
    if (front_ios_classic_can_request_return()) {
        shelf_game_thread = thread;
        shelf_started = YES;
        return;
    }
#endif
    pthread_detach(thread);
}

int front_ios_boot_ok(void) { return prepared; }
const char *front_ios_boot_message(void) { return NULL; }
const char *front_ios_device_check(void) { return NULL; }
int dm_locate_game_data(void) {
    const char *romfs = getenv("DM_ROMFS");
    struct stat st;
    return romfs && !stat(romfs, &st);
}
bool dm_show_launcher(void *controller, void (*done)(void)) {
    (void)controller; (void)done;
    return false;
}

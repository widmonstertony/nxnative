// tvOS entry point. The bundled game is immutable; writable cache and saves
// use Caches. tvOS local storage can be purged by the system.
#import <UIKit/UIKit.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <limits.h>
#include <os/log.h>
#include <os/proc.h>
#include <mach/mach.h>
#include "game_profile.h"
#include "dm.h"
#include "front.h"
#include "save_sync.h"
#import "romfs_patch.h"
#import "tv_gamebox.h"
#import "tv_runner.h"
#ifdef DM_TV_RUNNER
#include "romfs_identity.h"
#endif
#include <dlfcn.h>

UIViewController *front_tv_root(void);
UIViewController *front_tv_library_root(NSString *game, NSString *titleID, NSArray *previews, void (^flush)(void (^)(BOOL)));
BOOL front_tv_game_visible(void);
void front_tv_focus(int active);
void front_tv_resources_ready(NSString *failure);
BOOL tv_unpack_shaders(NSString *writable, NSString *expectedSHA256, NSString **failure);
int dm_main(int argc, char **argv);
static char *host_argv[3];
static int boot_ready;
static int resources_pending;
static int shaders_pending;
static int preparation_started;
static int host_started;
static NSString *boot_writable;
static NSString *boot_romfs;
static NSString *boot_patch_bundle;
static NSString *boot_msl;
static NSBundle *boot_bundle;
static NSDictionary<NSString *, NSString *> *boot_options;
static BOOL environment_active;
#ifdef DM_TV_QA
static BOOL runner_probe;
#endif
static void activate_environment(void);
NSString *front_tv_save_path(void) {
#ifdef DM_TV_QA
    if (runner_probe) return [boot_writable stringByAppendingPathComponent:@"qa-save"];
#endif
    return [boot_writable stringByAppendingPathComponent:@"save"];
}
void front_tv_play_selected(void);
void front_tv_show_runtime(NSString *title, NSString *titleID, UIViewController *presenter);
BOOL front_tv_runtime_blocked(void);
void front_tv_return_handler(void (^returned)(void));
static int early_boot_diag_enabled(void) {
    const char *enabled = getenv("DM_TV_EARLY_BOOT_DIAG");
    return enabled && !strcmp(enabled, "1");
}
// Opt-in process-limit diagnostics also run while the render thread is loading.
// Metal allocation totals alone do not identify the process's dirty-memory cap.
static void memory_diag_sample(const char *reason) {
    task_vm_info_data_t vm = {0};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), TASK_VM_INFO,
        (task_info_t)&vm, &count);
    size_t available = os_proc_available_memory();
    fprintf(stderr, "tvOS memory: reason=%s pid=%d task_info=%d footprint=%llu resident=%llu virtual=%llu available=%zu footprint_plus_available=%llu\n",
        reason, getpid(), result, (unsigned long long)vm.phys_footprint,
        (unsigned long long)vm.resident_size, (unsigned long long)vm.virtual_size,
        available, (unsigned long long)vm.phys_footprint + available);
}
static void *memory_diag_loop(void *unused) {
    (void)unused;
    for (;;) { memory_diag_sample("sample"); usleep(250000); }
    return NULL;
}
static void memory_diag_start(void) {
    const char *enabled = getenv("DM_TV_MEMORY_DIAG");
    if (!enabled || strcmp(enabled, "1")) return;
    pthread_t thread;
    if (!pthread_create(&thread, NULL, memory_diag_loop, NULL)) pthread_detach(thread);
}
static void *prepare_resources(void *unused) {
    @autoreleasepool {
        NSString *failure = nil;
        BOOL ok = !shaders_pending || tv_unpack_shaders(boot_writable,
            [boot_bundle objectForInfoDictionaryKey:@"DMShaderArchiveSHA256"], &failure);
        NSString *overlay = nil;
        if (ok && boot_patch_bundle) {
            NSString *game = [NSString stringWithFormat:@"%016llX",
                (unsigned long long)DM_GAME_PROGRAM_ID];
            ok = tv_materialize_romfs_patch(boot_romfs, boot_writable,
                boot_patch_bundle, game, &overlay, &failure);
        }
        if (ok) {
            if (shaders_pending)
                setenv("DM_MSL_DIR", [boot_writable stringByAppendingPathComponent:@"msl"].fileSystemRepresentation, 1);
            if (overlay) {
                setenv("DM_ROMFS_OVERLAY", overlay.fileSystemRepresentation, 1);
                NSString *redirects = [overlay stringByAppendingPathComponent:@"redirects.tsv"];
                setenv("DM_ROMFS_REDIRECTS", redirects.fileSystemRepresentation, 1);
            }
            boot_ready = 1; resources_pending = 0;
            dm_host_preload_start(2, host_argv);
        }
        if (!ok && !failure) failure = @"Game files could not be prepared.";
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) preparation_started = 0; // a later foreground/start event may retry
            front_tv_resources_ready(ok ? nil : failure);
        });
    }
    return NULL;
}
int front_tv_ready(void) { return boot_ready; }
int front_tv_preparing(void) { return resources_pending; }

static void *validate_loader(void *unused) {
    (void)unused;
    void crash_install(void); crash_install();
    g_t0_ns = now_ns();
    static const char *modules[] = DM_GAME_MODULES;
    load_modules(host_argv[1], modules, DM_GAME_NMOD);
    int (*compare)(const void *, const void *, size_t) = guest_sym("memcmp");
    if (!compare || !module_of((const void *)compare) ||
        compare("same", "same", 4) || compare("a", "b", 1) >= 0 || compare("b", "a", 1) <= 0)
        die("tvOS loader validation: original guest memcmp execution failed");
    fprintf(stderr, "tvOS loader validation PASS: signed guest execution, static RW data, key pages and relocation\n");
    NSLog(@"tvOS loader validation PASS: signed guest execution, static RW data, key pages and relocation");
    return NULL;
}

static void *run_host(void *unused) {
    (void)unused;
    dm_main(2, host_argv);
    return NULL;
}
void front_tv_start(void) {
    if (!boot_ready && !resources_pending) return;
    activate_environment();
    if (resources_pending) {
        if (!preparation_started) {
            pthread_attr_t attr;
            int result = pthread_attr_init(&attr);
            int attrInitialized = result == 0;
            if (!result) result = pthread_attr_setstacksize(&attr, 8u << 20);
            pthread_t thread;
            if (!result) result = pthread_create(&thread, &attr, prepare_resources, NULL);
            if (attrInitialized) {
                int destroyResult = pthread_attr_destroy(&attr);
                if (destroyResult) fprintf(stderr, "[RED] tvOS resource thread attributes could not be destroyed: %d\n", destroyResult);
            }
            if (!result) {
                preparation_started = 1;
                pthread_detach(thread);
            } else {
                fprintf(stderr, "[RED] tvOS resource preparation thread creation failed: %d\n", result);
                preparation_started = 0;
                front_tv_resources_ready(@"Could not start game-file preparation. Reopen the app to retry.");
            }
        }
        return;
    }
    if (!boot_ready || host_started) return;
    if ([NSBundle.mainBundle objectForInfoDictionaryKey:@"DMGameboxTV"]) {
        NSString *title = [NSString stringWithFormat:@"%016llX", (unsigned long long)DM_GAME_PROGRAM_ID];
        if ([NSUserDefaults.standardUserDefaults boolForKey:TVGamePreference(title,@"CloudDisabled")])
            setenv("DM_SAVE_SYNC", "0", 1);
    }
    pthread_attr_t attr; int result = pthread_attr_init(&attr);
    int attrInitialized = result == 0;
    if (!result) result = pthread_attr_setstacksize(&attr, 64u << 20);
    pthread_t thread;
    if (!result) result = pthread_create(&thread, &attr, run_host, NULL);
    if (attrInitialized) {
        int destroyResult = pthread_attr_destroy(&attr);
        if (destroyResult) fprintf(stderr, "[RED] tvOS host thread attributes could not be destroyed: %d\n", destroyResult);
    }
    if (!result) {
        host_started = 1;
        pthread_detach(thread);
    } else {
        fprintf(stderr, "[RED] tvOS host thread creation failed: %d\n", result);
        host_started = 0;
        front_tv_resources_ready(@"Could not start the game. Reopen the app to retry.");
    }
}

static void boot(NSBundle *bundle, BOOL separate) {
    boot_bundle = bundle;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *res = bundle.resourcePath;
    NSString *titleID = [NSString stringWithFormat:@"%016llX", (unsigned long long)DM_GAME_PROGRAM_ID];
    NSString *foundation = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
        NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"nxnative"];
    NSString *staged = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/nxnative"];
    NSString *cache = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
        NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"nxnative"];
    // Use the platform's writable cache directory. Accept already staged
    // support resources only when the application can actually read them.
    BOOL stagedGame = [fm fileExistsAtPath:[[staged stringByAppendingPathComponent:@"romfs"]
        stringByAppendingPathComponent:@DM_GAME_ROMFS_MARKER]];
    BOOL cacheGame = [fm fileExistsAtPath:[[cache stringByAppendingPathComponent:@"romfs"]
        stringByAppendingPathComponent:@DM_GAME_ROMFS_MARKER]];
    NSString *writable = separate ? TVGameResourceRoot(titleID) : (cacheGame || !stagedGame ? cache : staged);
    if (!separate && early_boot_diag_enabled()) {
        NSString *early = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp/tv-early-boot.txt"];
        int diagnostic = open(early.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (diagnostic >= 0) {
            NSString *marker = [[staged stringByAppendingPathComponent:@"romfs"] stringByAppendingPathComponent:@DM_GAME_ROMFS_MARKER];
            int source = open(marker.fileSystemRepresentation, O_RDONLY);
            int sourceError = source >= 0 ? 0 : errno;
            if (source >= 0) close(source);
            dprintf(diagnostic, "Foundation support=%s home=%s staged_marker=%d support_open_errno=%d cache=%s cache_marker=%d selected=%s uid=%u executable=%s\n",
                foundation.fileSystemRepresentation ?: "(nil)", NSHomeDirectory().fileSystemRepresentation,
                stagedGame, sourceError, cache.fileSystemRepresentation, cacheGame, writable.fileSystemRepresentation,
                getuid(), NSBundle.mainBundle.executablePath.fileSystemRepresentation);
            close(diagnostic);
        }
    }
    boot_writable = writable;
    NSMutableDictionary<NSString *, NSString *> *options = [NSMutableDictionary dictionary];
    for (NSString *ef in @[[writable stringByAppendingPathComponent:@"env.txt"],
                          [res stringByAppendingPathComponent:@"dm/env.txt"]]) {
        NSString *txt = [NSString stringWithContentsOfFile:ef encoding:NSUTF8StringEncoding error:nil];
        for (NSString *line in [txt componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            NSString *s = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSRange eq = [s rangeOfString:@"="];
            if (!s.length || [s hasPrefix:@"#"] || eq.location == NSNotFound || !eq.location) continue;
            NSString *key = [s substringToIndex:eq.location];
            if (!options[key]) options[key] = [s substringFromIndex:eq.location + 1];
        }
    }
    NSString *romfs = [res stringByAppendingPathComponent:@"romfs"];
    NSString *external = [writable stringByAppendingPathComponent:@"romfs"];
    if ([fm fileExistsAtPath:[external stringByAppendingPathComponent:@DM_GAME_ROMFS_MARKER]]) romfs = external;
    boot_options = options;
    boot_ready = [fm fileExistsAtPath:[romfs stringByAppendingPathComponent:@DM_GAME_ROMFS_MARKER]];
#ifdef DM_TV_RUNNER
    NSString *packed = [writable stringByAppendingPathComponent:@"RomFS.img"];
    NSString *identity = [res stringByAppendingPathComponent:@"dm/romfs.id"];
    romfs_id want, got;
    boot_ready = romfs_id_check(identity.fileSystemRepresentation, packed.fileSystemRepresentation, &want, &got)
        == ROMFS_ID_OK && !strcasecmp(want.title, titleID.UTF8String);
    romfs = packed;
#endif
    boot_romfs = romfs;
    NSString *externalMSL = [writable stringByAppendingPathComponent:@"msl"];
    NSString *bundledMSL = [res stringByAppendingPathComponent:@"msl"];
    NSString *archiveSHA = [boot_bundle objectForInfoDictionaryKey:@"DMShaderArchiveSHA256"];
    NSString *importedSHA = [[NSString stringWithContentsOfFile:[externalMSL stringByAppendingPathComponent:@".archive-sha256"]
        encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL externalDirectory = NO, bundledDirectory = NO;
    [fm fileExistsAtPath:externalMSL isDirectory:&externalDirectory];
    [fm fileExistsAtPath:bundledMSL isDirectory:&bundledDirectory];
    BOOL imported = externalDirectory && archiveSHA.length == 64 && [importedSHA isEqualToString:archiveSHA];
    BOOL archiveAvailable = [fm fileExistsAtPath:[writable stringByAppendingPathComponent:@"msl.tar.gz"]];
    // Prefer a verified external import.  Otherwise an available transfer must
    // be imported before boot; with no transfer, only immutable bundled shaders
    // are trusted.  A stale writable directory is never selected by existence.
    if (separate && !imported && !archiveAvailable && !bundledDirectory) boot_ready = 0;
    shaders_pending = boot_ready && !imported && (archiveAvailable || !bundledDirectory);
    const char *patchOverride = getenv("DM_ROMFS_PATCH");
    NSString *specified = patchOverride ? @(patchOverride) : options[@"DM_ROMFS_PATCH"];
    if (specified.length && !separate) {
        boot_patch_bundle = specified.isAbsolutePath ? specified :
            [writable stringByAppendingPathComponent:specified];
        fprintf(stderr, "tvOS RomFS patch: explicitly enabled from %s\n",
            boot_patch_bundle.fileSystemRepresentation);
    }
    resources_pending = boot_ready && (shaders_pending || boot_patch_bundle != nil);
    if (imported) fprintf(stderr, "tvOS resources: verified external import marker matches archive\n");
    else if (archiveAvailable) fprintf(stderr, "tvOS resources: shader archive is pending verified import\n");
    else if (bundledDirectory) fprintf(stderr, "tvOS resources: using immutable bundled shaders\n");
    else if (boot_ready) fprintf(stderr, "[RED] tvOS resources: no verified external, transfer, or bundled shaders\n");
    boot_msl = imported ? externalMSL : bundledMSL;
    if (resources_pending) boot_ready = 0;
}

static void activate_environment(void) {
    if (environment_active) return;
    environment_active = YES;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *res = boot_bundle.resourcePath, *writable = boot_writable;
    [fm createDirectoryAtPath:writable withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *log = [writable stringByAppendingPathComponent:@"log.txt"];
    freopen(log.fileSystemRepresentation, "w", stderr);
    setvbuf(stderr, NULL, _IOLBF, 0);
    fprintf(stderr, "tvOS boot: writable=%s\n", writable.fileSystemRepresentation);
    for (NSString *path in @[front_tv_save_path(), [writable stringByAppendingPathComponent:@"temp"]])
        [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    [boot_options enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        setenv(key.UTF8String, value.UTF8String, 0);
    }];
    setenv("DM_ROMFS", boot_romfs.fileSystemRepresentation, 0);
    setenv("DM_SAVE", front_tv_save_path().fileSystemRepresentation, 0);
    setenv("DM_TEMP", [writable stringByAppendingPathComponent:@"temp"].fileSystemRepresentation, 0);
    setenv("DM_MSL_DIR", boot_msl.fileSystemRepresentation, 0);
    setenv("DM_NVN_SHMAP", [res stringByAppendingPathComponent:@"dm/shader_map.tsv"].fileSystemRepresentation, 0);
    setenv("DM_FONT_DIR", [res stringByAppendingPathComponent:@"dm/font"].fileSystemRepresentation, 0);
    setenv("DM_LANG", "zh-CN", 0); setenv("DM_PRESENT_INTERVAL", "game", 0);
    setenv("DM_PIPELINE_CACHE", "off", 0); setenv("DM_NVN_MIN_REDUCTION", "1", 0);
    setenv("DM_NVN_CPU_DECODE_CACHE", "0", 0); setenv("DM_SHOW_FPS", "0", 0);
    chdir(writable.fileSystemRepresentation);
    memory_diag_start();
    host_argv[0] = strdup("dmhost"); host_argv[1] = strdup([res stringByAppendingPathComponent:@"dm"].fileSystemRepresentation);
}

static UIViewController *open_library(NSString *displayName, NSString *title, NSArray *previews) {
    return front_tv_library_root(displayName, title, previews, ^(void (^completed)(BOOL)) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
            BOOL synchronized = !host_started || save_sync_flush(5000);
            dispatch_async(dispatch_get_main_queue(), ^{ completed(synchronized); });
        });
    });
}

#ifdef DM_TV_RUNNER
BOOL front_tv_runtime_blocked(void) { return NO; }
void front_tv_show_runtime(NSString *title, NSString *titleID, UIViewController *presenter) {
    (void)title; (void)titleID; (void)presenter;
}
static UIViewController *runner_open(NSString *title, void (^returnToShelf)(void)) {
    static UIViewController *root;
    if (root) return root;
    Dl_info info = {0};
    if (!dladdr((const void *)runner_open, &info) || !info.dli_fname) return nil;
    NSString *path = [@(info.dli_fname) stringByDeletingLastPathComponent];
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    if (!bundle) return nil;
    boot(bundle, YES);
#ifdef DM_TV_QA
    runner_probe = getenv("DM_TV_QA_PLAY_RUNNER") != NULL;
    if (runner_probe) setenv("DM_SAVE_SYNC", "0", 1);
#endif
    front_tv_return_handler(returnToShelf);
    NSString *titleID = [NSString stringWithFormat:@"%016llX", (unsigned long long)DM_GAME_PROGRAM_ID];
    root = open_library(title, titleID, nil);
    return root;
}
static void runner_focus(BOOL active) { front_tv_focus(active && front_tv_game_visible()); }
static BOOL runner_started(void) { return environment_active; }
static void runner_flush(unsigned timeout) { if (host_started) save_sync_flush(timeout); }
__attribute__((visibility("default"))) const TVRunner *TonTonTVRunner(void) {
    static const TVRunner api = {
        TV_RUNNER_ABI, DM_TV_RUNNER_TITLE, runner_open, runner_focus,
        runner_started, runner_flush, front_tv_play_selected
    };
    return &api;
}
#else
static const TVRunner *active_runner;
static UIViewController *runner_view;
static BOOL runner_presented;

BOOL front_tv_runtime_blocked(void) {
    return active_runner && active_runner->started();
}

void front_tv_show_runtime(NSString *title, NSString *titleID, UIViewController *presenter) {
    if (runner_presented) return;
    if (environment_active) {
        TVShowSwitchRequired(presenter);
        return;
    }
    if (!runner_view) {
        NSString *name = [NSString stringWithFormat:@"DmTVGame%@.framework/DmTVGame%@", titleID, titleID];
        NSString *path = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:name];
        void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        TVRunnerEntry entry = handle ? (TVRunnerEntry)dlsym(handle, "TonTonTVRunner") : NULL;
        const TVRunner *api = entry ? entry() : NULL;
        NSString *digest = [NSBundle.mainBundle objectForInfoDictionaryKey:@"DMGameboxRunners"][titleID];
        NSBundle *runtime = [NSBundle bundleWithPath:path.stringByDeletingLastPathComponent];
        if (digest.length == 64 && [digest isEqual:[runtime objectForInfoDictionaryKey:@"DMShaderArchiveSHA256"]] &&
            api && api->abi == TV_RUNNER_ABI && api->titleID && strcasecmp(api->titleID, titleID.UTF8String) == 0) {
            runner_view = api->open(title, ^{
                [runner_view dismissViewControllerAnimated:YES completion:^{ runner_presented = NO; }];
            });
            if (runner_view) active_runner = api;
        }
        if (!runner_view) {
            const char *error = dlerror();
            NSLog(@"TonTon tvOS: runtime %@ not available: %s", titleID, error ?: "incompatible entry");
            UIAlertController *dialog = [UIAlertController alertControllerWithTitle:title
                message:@"这款游戏的运行组件缺失或不匹配。" preferredStyle:UIAlertControllerStyleAlert];
            [dialog addAction:[UIAlertAction actionWithTitle:@"返回游戏库" style:UIAlertActionStyleCancel handler:nil]];
            [presenter presentViewController:dialog animated:YES completion:nil];
            return;
        }
    } else if (strcasecmp(active_runner->titleID, titleID.UTF8String) != 0) {
        TVShowSwitchRequired(presenter);
        return;
    }
    runner_presented = YES;
    runner_view.modalPresentationStyle = UIModalPresentationFullScreen;
    [presenter presentViewController:runner_view animated:YES completion:^{
#ifdef DM_TV_QA
        if (getenv("DM_TV_QA_PLAY_RUNNER")) active_runner->play();
#endif
    }];
}

static void boot_primary(void) {
    boot(NSBundle.mainBundle, NO);
    if (getenv("DM_TV_VALIDATE_LOADER")) {
        activate_environment();
        boot_ready = 0; resources_pending = 0;
        pthread_t thread;
        int result = pthread_create(&thread, NULL, validate_loader, NULL);
        if (!result) pthread_detach(thread);
        else fprintf(stderr, "[RED] tvOS loader validation thread creation failed: %d\n", result);
    }
    else if (boot_ready && ![NSBundle.mainBundle objectForInfoDictionaryKey:@"DMGameboxRunners"]) {
        activate_environment();
        dm_host_preload_start(2, host_argv);
    }
}

@interface TVSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(strong, nonatomic) UIWindow *window;
@end
@implementation TVSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    if ([NSBundle.mainBundle objectForInfoDictionaryKey:@"DMGameboxTV"]) {
        NSString *title = [NSString stringWithFormat:@"%016llX", (unsigned long long)DM_GAME_PROGRAM_ID];
        NSString *displayName = [NSBundle.mainBundle objectForInfoDictionaryKey:@"DMGameboxTitle"] ?: @DM_GAME_NAME;
        NSArray *previews=[NSBundle.mainBundle objectForInfoDictionaryKey:@"DMGameboxPreviews"];
        self.window.rootViewController = open_library(displayName, title, previews);
    } else self.window.rootViewController = front_tv_root();
    [self.window makeKeyAndVisible];
#ifdef DM_TV_QA
    const char *probe = getenv("DM_TV_QA_PLAY_RUNNER");
    if (probe && [self.window.rootViewController isKindOfClass:UINavigationController.class]) {
        NSString *key = @(probe);
        for (NSDictionary *row in [NSBundle.mainBundle objectForInfoDictionaryKey:@"DMGameboxPreviews"]) {
            if ([row[@"id"] caseInsensitiveCompare:key] != NSOrderedSame) continue;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                front_tv_show_runtime(row[@"title"], key.lowercaseString, [(UINavigationController *)self.window.rootViewController topViewController]);
            });
            break;
        }
    }
#endif
}
- (void)sceneWillResignActive:(UIScene *)scene { if (runner_presented) active_runner->focus(NO); else front_tv_focus(0); }
- (void)sceneDidEnterBackground:(UIScene *)scene {
    const TVRunner *runner = active_runner;
    if (!host_started && (!runner || !runner->started())) return;
    UIApplication *app = UIApplication.sharedApplication;
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    void (^end)(void) = ^{
        if (task != UIBackgroundTaskInvalid) {
            [app endBackgroundTask:task];
            task = UIBackgroundTaskInvalid;
        }
    };
    task = [app beginBackgroundTaskWithName:@"cloud save" expirationHandler:end];
    if (task == UIBackgroundTaskInvalid) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (runner && runner->started()) runner->flush(20000);
        else save_sync_flush(20000);
        dispatch_async(dispatch_get_main_queue(), end);
    });
}
- (void)sceneDidBecomeActive:(UIScene *)scene { if (runner_presented) active_runner->focus(YES); else if (front_tv_game_visible()) front_tv_focus(1); }
@end
@interface TVApp : UIResponder <UIApplicationDelegate>
@end
@implementation TVApp
- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    const char *enabled = getenv("DM_TV_MEMORY_DIAG");
    if (enabled && !strcmp(enabled, "1")) memory_diag_sample("UIKit-warning");
}
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *c = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
    c.delegateClass = TVSceneDelegate.class; return c;
}
@end
int main(int argc, char **argv) {
    // Leave a libc-only marker before autorelease pools, Foundation path lookup,
    // directory creation and UIKit. This separates startup from log-path faults.
    if (early_boot_diag_enabled()) {
        const char *home = getenv("HOME");
        dprintf(STDERR_FILENO, "tvOS main: before Foundation, pid=%d HOME=%s\n", getpid(), home ?: "(unset)");
        os_log(OS_LOG_DEFAULT, "DmTV main entered before Foundation");
        if (home) {
            char path[PATH_MAX]; snprintf(path, sizeof path, "%s/tmp/tv-early-boot.txt", home);
            int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
            if (fd >= 0) { dprintf(fd, "before Foundation pid=%d HOME=%s\n", getpid(), home); close(fd); }
        }
    }
    @autoreleasepool { boot_primary(); return UIApplicationMain(argc, argv, nil, NSStringFromClass(TVApp.class)); }
}

#endif

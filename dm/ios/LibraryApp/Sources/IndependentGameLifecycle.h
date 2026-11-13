// Framework-local restart state, adapted from NX2Apple Route C (issue #451).
// A capability gate keeps older shared or independent hosts out of this path.
#pragma once
#import <UIKit/UIKit.h>
#import "IndependentGameHost.h"
#include "FrameworkSegments.h"

typedef struct {
    const void *image;
    DmSegSnap segments[2];
} TonTonFrameworkSnapshot;
static TonTonFrameworkSnapshot tonton_snapshots[64];
static unsigned tonton_snapshot_count;
static TonTonFrameworkSnapshot *tonton_active_snapshot;
static UIWindow *__weak tonton_return_window;
static UIViewController *tonton_return_library;
static dispatch_block_t tonton_did_return;

extern char **environ;
static NSDictionary<NSString *, NSString *> *TonTonGameEnvironment(void) {
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (char **entry = environ; entry && *entry; entry++) {
        const char *eq = strchr(*entry, '=');
        if (!eq || (strncmp(*entry, "DM_", 3) && strncmp(*entry, "MTL_HUD_ENABLED=", 16))) continue;
        NSString *key = [[NSString alloc] initWithBytes:*entry length:eq - *entry encoding:NSUTF8StringEncoding];
        NSString *value = [NSString stringWithUTF8String:eq + 1];
        if (key && value) saved[key] = value;
    }
    return saved;
}
static void TonTonRestoreGameEnvironment(NSDictionary<NSString *, NSString *> *saved) {
    for (NSString *key in TonTonGameEnvironment()) unsetenv(key.UTF8String);
    for (NSString *key in saved) setenv(key.UTF8String, saved[key].UTF8String, 1);
}

static TonTonFrameworkSnapshot *TonTonCaptureFramework(const void *image) {
    if (!image) return NULL;
    for (unsigned i = 0; i < tonton_snapshot_count; i++)
        if (tonton_snapshots[i].image == image) return &tonton_snapshots[i];
    if (tonton_snapshot_count == 64) return NULL;
    TonTonFrameworkSnapshot *snapshot = &tonton_snapshots[tonton_snapshot_count];
    dm_seg_snap_save(image, "__DATA", &snapshot->segments[0]);
    dm_seg_snap_save(image, "__DATA_DIRTY", &snapshot->segments[1]);
    for (unsigned i = 0; i < 2; i++) {
        DmSegSnap *s = &snapshot->segments[i];
        if (!s->complete) {
            dm_seg_snap_free(&snapshot->segments[0]);
            dm_seg_snap_free(&snapshot->segments[1]);
            return NULL;
        }
    }
    snapshot->image = image;
    tonton_snapshot_count++;
    return snapshot;
}

// The engine calls this only after save flush and complete teardown, on main.
// Never suspend/restore a running guest or unload its Objective-C classes.
static void TonTonIndependentReturned(void *context) {
    (void)context;
    dispatch_block_t finished = ^{
        TonTonFrameworkSnapshot *snapshot = tonton_active_snapshot;
        if (!snapshot) return;
        tonton_active_snapshot = NULL;
        for (unsigned i = 0; i < 2; i++) dm_seg_snap_restore(&snapshot->segments[i]);
        UIWindow *window = tonton_return_window;
        UIViewController *library = tonton_return_library;
        dispatch_block_t returned = tonton_did_return;
        tonton_return_window = nil;
        tonton_return_library = nil;
        tonton_did_return = nil;
        if (window && library) {
            window.rootViewController = library;
            [library setNeedsUpdateOfSupportedInterfaceOrientations];
            if (@available(iOS 16.0, *))
                [window.windowScene requestGeometryUpdateWithPreferences:
                    [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskAllButUpsideDown]
                    errorHandler:nil];
            [window makeKeyAndVisible];
        }
        if (returned) returned();
        fprintf(stderr, "boot: independent game teardown completed; returned to library\n");
    };
    if (NSThread.isMainThread) finished();
    else dispatch_async(dispatch_get_main_queue(), finished);
}

static BOOL TonTonPrepareIndependentReturn(TonTonGameHost host, const void *image,
                                           UIWindow *window, dispatch_block_t returned) {
    if (!host.setReturn) return YES; // v1 hosts retain their established lifecycle.
    if (tonton_active_snapshot || !window.rootViewController) return NO;
    TonTonFrameworkSnapshot *snapshot = TonTonCaptureFramework(image);
    if (!snapshot) return NO;
    tonton_active_snapshot = snapshot;
    tonton_return_window = window;
    tonton_return_library = window.rootViewController;
    tonton_did_return = [returned copy];
    host.setReturn(TonTonIndependentReturned, NULL);
    return YES;
}

static void TonTonAbandonIndependentReturn(void) {
    tonton_active_snapshot = NULL;
    tonton_return_window = nil;
    tonton_return_library = nil;
    tonton_did_return = nil;
}

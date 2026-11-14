#pragma once

#import <UIKit/UIKit.h>

#define TV_RUNNER_ABI 1

// Only entry point exported by a signed, bundled game framework. Resource
// paths, guest code, and renderer state belong to that runtime.
typedef struct {
    unsigned abi;
    const char *titleID;
    UIViewController *(*open)(NSString *title, void (^returnToShelf)(void));
    void (*focus)(BOOL active);
    BOOL (*started)(void);
    void (*flush)(unsigned ms);
    void (*play)(void);
} TVRunner;

typedef const TVRunner *(*TVRunnerEntry)(void);

#import <UIKit/UIKit.h>
#include <stdint.h>
#include <stdio.h>
#include "save_sync.h"
UIViewController *front_tv_root(void);
UIViewController *front_tv_library_root(NSString *, NSString *, NSArray *, void (^)(void (^)(BOOL)));
void front_tv_focus(int active);
static UILabel *stateLabel, *historyLabel;
static NSMutableArray *history;
void dm_pad_set(uint64_t b,int32_t lx,int32_t ly,int32_t rx,int32_t ry) {
    stateLabel.text=[NSString stringWithFormat:@"%llu,%d,%d,%d,%d",b,lx,ly,rx,ry];
    if (b||lx||ly||rx||ry) { if (!history)history=[NSMutableArray new];
        [history addObject:stateLabel.text?:@""];historyLabel.text=[history componentsJoinedByString:@";"]; }
}
void dm_input_set(uint64_t b,int32_t lx,int32_t ly,int32_t rx,int32_t ry) {}
void dm_focus_set(int a) {}
void guest_clock_freeze_for(int r,int a) {}
void dm_gfx_suspend(int a) {}
void front_tv_start(void) {}
NSString *front_tv_save_path(void) { return @"/test/save"; }
BOOL front_tv_runtime_blocked(void) { return NO; }
void front_tv_show_runtime(NSString *title, NSString *titleID, UIViewController *presenter) {}
int front_tv_ready(void) { return 1; }
int front_tv_preparing(void) { return 0; }
int front_cloudkit_configured(void) { return getenv("TV_MOCK_SAVE") != NULL; }
int front_cloudkit_account(char scope[33]) { return front_cloudkit_configured(); }
int save_sync_report(const char *save, const char *title, const char *folder, int timeout, char *out, size_t size) {
    snprintf(out, size, "conflict=1 chash=%0*d", SS_HASH, 0);
    return 0;
}
@interface QAScene : UIResponder <UIWindowSceneDelegate>
@property(strong,nonatomic) UIWindow *window;
@end
@implementation QAScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"-ton-ton-shelf"]) {
        setenv("DM_SAVE", "/fake-save-path", 1);
        NSArray *previews = getenv("TV_MOCK_PREVIEW") ? @[@{@"id":@"01001f5010dfa000",@"title":@"宝可梦传说：阿尔宙斯"}] : nil;
        self.window.rootViewController=front_tv_library_root(@"宝可梦传说 Z-A", @"0100F43008C44000", previews, ^(void (^complete)(BOOL)) { complete(YES); });
        [self.window makeKeyAndVisible];
        return;
    }
    self.window.rootViewController=front_tv_root();[self.window makeKeyAndVisible];
    stateLabel=[[UILabel alloc] initWithFrame:CGRectMake(100,100,1600,100)];stateLabel.textColor=UIColor.whiteColor;
    stateLabel.accessibilityIdentifier=@"qa-pad-state";stateLabel.text=@"0,0,0,0,0";
    historyLabel=[[UILabel alloc] initWithFrame:CGRectMake(100,220,1600,100)];historyLabel.textColor=UIColor.whiteColor;
    historyLabel.accessibilityIdentifier=@"qa-pad-history";historyLabel.text=@"none";
    [self.window.rootViewController.view addSubview:stateLabel];[self.window.rootViewController.view addSubview:historyLabel];
}
- (void)sceneWillResignActive:(UIScene *)scene { front_tv_focus(0); }
- (void)sceneDidBecomeActive:(UIScene *)scene { front_tv_focus(1); }
@end
@interface QAApp : UIResponder <UIApplicationDelegate>
@end
@implementation QAApp
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *c=[[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
    c.delegateClass=QAScene.class; return c;
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,@"QAApp"); } }

// Apple TV front end: Metal, physical gamepads and UIKit Remote input.
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <GameController/GameController.h>
#import <AVFAudio/AVFAudio.h>
#include "dm.h"
#include "front.h"
#include "dm_input.h"
#include "hle.h"
#include "tv_remote.h"
#include "save_sync.h"
#import "tv_gamebox.h"
#include <math.h>
#if defined(DM_TV_QA) && defined(DM_TV_RUNNER)
#include <notify.h>
#endif

void front_tv_start(void);
NSString *front_tv_save_path(void);
BOOL front_tv_runtime_blocked(void);
void front_tv_show_runtime(NSString *title, NSString *titleID, UIViewController *presenter);
#ifdef DM_TV_RUNNER
#define TVMetalView TVRunnerMetalView
#define TVRootVC TVRunnerRootVC
#define TVLibraryVC TVRunnerLibraryVC
#define TVShelfCard TVRunnerShelfCard
#endif
int front_tv_ready(void);
int front_tv_preparing(void);
static CAMetalLayer *tv_layer;
static UIViewController *tv_root;
static UINavigationController *tv_library;
static UIViewController *tv_library_home;
static UIViewController *tv_gallery_home;
static UIButton *tv_play;
static UIButton *tv_settings;
static UILabel *tv_cloud_status;
static NSString *tv_title_id;
static NSUInteger tv_cloud_check;
static BOOL tv_swap_face;
static BOOL tv_options_down;
static BOOL tv_controls_visible;
static BOOL tv_checking_saves;
static NSUInteger tv_options_serial;
static BOOL tv_game_visible;
static BOOL tv_game_opened;
static BOOL tv_exit_pending;
static void (^tv_flush_game)(void (^completed)(BOOL));
static void tv_return_to_library(void);
static void (^tv_return_to_shelf)(void);
void front_tv_return_handler(void (^returned)(void)) { tv_return_to_shelf = [returned copy]; }
static BOOL tv_active = YES;
static void tv_held_options(void);
static TVRemoteState remote_state;
static TVRemoteOutput physical_state;
static void input_publish(void) {
    TVRemoteOutput r = tv_remote_output(&remote_state), p = tv_controls_visible ? (TVRemoteOutput){0} : physical_state;
    if (!tv_active) { dm_pad_set(0, 0, 0, 0, 0); return; }
    dm_pad_set(p.buttons | r.buttons, r.lx ?: p.lx, r.ly ?: p.ly, r.rx ?: p.rx, r.ry ?: p.ry);
}
static void controller_read(GCExtendedGamepad *p) {
    if (!tv_active) { dm_pad_set(0, 0, 0, 0, 0); return; }
    BOOL optionsDown = p.buttonOptions.pressed;
    if (optionsDown != tv_options_down) {
        tv_options_down = optionsDown;
        NSUInteger serial = ++tv_options_serial;
        if (optionsDown && tv_library && tv_game_visible)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                if (serial == tv_options_serial && p.buttonOptions.pressed && tv_active && tv_game_visible) tv_held_options();
            });
    }
    uint64_t b = 0;
    // Nintendo's letters follow the physical positions used by the host's
    // existing controllers: bottom B, right A, left Y, top X.
    if (p.buttonA.pressed) b |= tv_swap_face ? DM_BTN_A : DM_BTN_B;
    if (p.buttonB.pressed) b |= tv_swap_face ? DM_BTN_B : DM_BTN_A;
    if (p.buttonX.pressed) b |= tv_swap_face ? DM_BTN_X : DM_BTN_Y;
    if (p.buttonY.pressed) b |= tv_swap_face ? DM_BTN_Y : DM_BTN_X;
    if (p.leftShoulder.pressed) b |= DM_BTN_L;
    if (p.rightShoulder.pressed) b |= DM_BTN_R;
    if (p.leftTrigger.pressed) b |= DM_BTN_ZL;
    if (p.rightTrigger.pressed) b |= DM_BTN_ZR;
    if (p.leftThumbstickButton.pressed) b |= DM_BTN_LS;
    if (p.rightThumbstickButton.pressed) b |= DM_BTN_RS;
    if (p.buttonMenu.pressed) b |= DM_BTN_PLUS;
    if (p.buttonOptions.pressed) b |= DM_BTN_MINUS;
    if (p.dpad.left.pressed) b |= DM_BTN_LEFT;
    if (p.dpad.right.pressed) b |= DM_BTN_RIGHT;
    if (p.dpad.up.pressed) b |= DM_BTN_UP;
    if (p.dpad.down.pressed) b |= DM_BTN_DOWN;
    physical_state = (TVRemoteOutput){ b, p.leftThumbstick.xAxis.value * 32767, p.leftThumbstick.yAxis.value * 32767,
        p.rightThumbstick.xAxis.value * 32767, p.rightThumbstick.yAxis.value * 32767 };
    input_publish();
}
static void controllers_update(void) {
    tv_options_down = NO; tv_options_serial++;
    physical_state = (TVRemoteOutput){0}; input_publish();
    for (GCController *c in GCController.controllers) {
        if (!c.extendedGamepad) continue;
        c.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *p, GCControllerElement *element) {
            dispatch_async(dispatch_get_main_queue(), ^{ controller_read(p); });
        };
        controller_read(c.extendedGamepad); break;
    }
}
void front_tv_focus(int active) {
    tv_active = !!active; tv_remote_cancel(&remote_state, 1);
    tv_options_down = NO; tv_options_serial++;
    physical_state = (TVRemoteOutput){0}; input_publish(); dm_input_set(0, 0, 0, 0, 0);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"TVRemoteReset" object:nil];
    if (tv_layer) { dm_focus_set(active ? 1 : 3); guest_clock_freeze_for(1, !active); dm_gfx_suspend(!active); }
    NSError *error = nil;
    [AVAudioSession.sharedInstance setActive:!!active error:&error];
    if (active) controllers_update();
}
@interface TVMetalView : UIView
@end
@implementation TVMetalView
+ (Class)layerClass { return CAMetalLayer.class; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        CAMetalLayer *l = (CAMetalLayer *)self.layer;
        l.device = MTLCreateSystemDefaultDevice(); l.pixelFormat = MTLPixelFormatBGRA8Unorm;
        l.framebufferOnly = NO; l.opaque = YES;
        l.drawableSize = CGSizeMake(1920, 1080);
    } return self;
}
@end
@interface TVRootVC : UIViewController
@property(strong, nonatomic) UILabel *preparationLabel;
@property(strong, nonatomic) UILabel *remoteHint;
@property(strong, nonatomic) UIView *remotePanel;
@property(strong, nonatomic) UIPanGestureRecognizer *remotePan;
@property(strong, nonatomic) NSMutableArray<UIButton *> *remoteButtons;
@property(nonatomic) NSUInteger pulseSerial;
@property(nonatomic) NSUInteger hintSerial;
- (void)updateRemoteHint;
- (void)showRemotePanel;
- (void)createGame;
- (void)pulseRemoteButton:(uint64_t)bit;
@end
@implementation TVRootVC
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = UIColor.blackColor;
    if (!front_tv_ready()) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 70, 70)];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        label.numberOfLines = 0; label.textColor = UIColor.whiteColor; label.textAlignment = NSTextAlignmentCenter;
        label.text = front_tv_preparing() ? @"Preparing game files…" : @"Game resources have not been staged for Apple TV yet.";
        self.preparationLabel = label; [self.view addSubview:label]; return;
    }
    [self createGame];
}
- (void)createGame {
    [self.preparationLabel removeFromSuperview]; self.preparationLabel = nil;
    TVMetalView *view = [[TVMetalView alloc] initWithFrame:self.view.bounds];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:view]; tv_layer = (CAMetalLayer *)view.layer;
    NSError *error = nil; AVAudioSession *audio = AVAudioSession.sharedInstance;
    [audio setCategory:AVAudioSessionCategoryPlayback error:&error];
    [audio setPreferredSampleRate:48000 error:&error];
    [audio setPreferredIOBufferDuration:0.005 error:&error];
    [audio setActive:YES error:&error];
    [NSNotificationCenter.defaultCenter addObserverForName:GCControllerDidConnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { controllers_update(); }];
    [NSNotificationCenter.defaultCenter addObserverForName:GCControllerDidDisconnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { controllers_update(); }];
    controllers_update(); UIApplication.sharedApplication.idleTimerDisabled = YES;
    NSString *modeKey = tv_title_id ? TVGamePreference(tv_title_id, @"RemoteMode") : @"TVRemoteMode";
    NSNumber *mode = [NSUserDefaults.standardUserDefaults objectForKey:modeKey] ?:
        [NSUserDefaults.standardUserDefaults objectForKey:@"TVRemoteMode"];
    remote_state.mode = mode.intValue;
    if (remote_state.mode < TV_REMOTE_MOVE || remote_state.mode > TV_REMOTE_DPAD) remote_state.mode = TV_REMOTE_MOVE;
    self.remotePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(remotePanned:)];
    [self.view addGestureRecognizer:self.remotePan];
    self.remoteHint = [[UILabel alloc] initWithFrame:CGRectMake(50, self.view.bounds.size.height - 66, self.view.bounds.size.width - 100, 42)];
    self.remoteHint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.remoteHint.font = [UIFont systemFontOfSize:23 weight:UIFontWeightSemibold];
    self.remoteHint.textColor = UIColor.whiteColor;
    self.remoteHint.backgroundColor = [UIColor colorWithWhite:0 alpha:0.70];
    self.remoteHint.textAlignment = NSTextAlignmentCenter;
    self.remoteHint.accessibilityIdentifier = @"remote-hint";
    [self.view addSubview:self.remoteHint]; [self updateRemoteHint];
    [NSNotificationCenter.defaultCenter addObserverForName:@"TVRemoteReset" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        self.pulseSerial++; [self updateRemoteHint];
    }];
#if defined(DM_TV_QA) && defined(DM_TV_RUNNER)
    if (getenv("DM_TV_QA_PLAY_RUNNER")) {
        int token = 0;
        notify_register_dispatch("com.tonytan.gamebox.qa.press-a", &token, dispatch_get_main_queue(), ^(int registered) {
            if (tv_game_visible && tv_active) [self pulseRemoteButton:DM_BTN_A];
        });
    }
#endif
    [self becomeFirstResponder];
}
- (BOOL)canBecomeFirstResponder { return YES; }
- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    return self.remotePanel && self.remoteButtons.count ? @[self.remoteButtons.firstObject] : @[];
}
- (void)updateRemoteHint {
    NSArray *modes = @[@"MOVE", @"CAMERA", @"D-PAD"];
    NSMutableArray *held = [NSMutableArray array];
    for (NSArray *entry in @[@[@"L", @(DM_BTN_L)], @[@"R", @(DM_BTN_R)], @[@"ZL", @(DM_BTN_ZL)], @[@"ZR", @(DM_BTN_ZR)]])
        if (remote_state.held & [entry[1] unsignedLongLongValue]) [held addObject:entry[0]];
    self.remoteHint.text = [NSString stringWithFormat:@"%@  |  Click: A    Back: B    Play/Pause: all controls%@", modes[remote_state.mode],
        held.count ? [@"  |  Holding: " stringByAppendingString:[held componentsJoinedByString:@" + "]] : @""];
    self.remoteHint.hidden = NO;
    NSUInteger serial = ++self.hintSerial;
    if (!tv_library || self.remotePanel || held.count || [NSUserDefaults.standardUserDefaults boolForKey:TVGamePreference(tv_title_id,@"KeepHints")]) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if (serial == self.hintSerial) self.remoteHint.hidden=YES;
    });
}
- (void)remotePanned:(UIPanGestureRecognizer *)pan {
    if (self.remotePanel || self.presentedViewController || !tv_active) return;
    CGPoint d = [pan translationInView:self.view];
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed)
        remote_state.x = remote_state.y = 0;
    else {
        remote_state.x = lrint(fmax(-1, fmin(1, d.x / 120.0)) * 32767);
        remote_state.y = lrint(fmax(-1, fmin(1, -d.y / 120.0)) * 32767);
    }
    input_publish();
}
- (void)hideRemotePanel {
    [self.remotePanel removeFromSuperview]; self.remotePanel = nil;
    tv_controls_visible = NO; physical_state = (TVRemoteOutput){0};
    self.remoteButtons = nil; self.remotePan.enabled = YES;
    tv_remote_cancel(&remote_state, 0); self.pulseSerial++; input_publish();
    [self updateRemoteHint]; [self becomeFirstResponder]; [self setNeedsFocusUpdate];
}
- (void)showRemotePanel {
    if (self.remotePanel) { [self hideRemotePanel]; return; }
    tv_controls_visible = YES;
    tv_remote_cancel(&remote_state, 0); self.pulseSerial++; input_publish();
    self.remotePan.enabled = NO;
    UIView *panel = [[UIView alloc] initWithFrame:CGRectInset(self.view.bounds, 80, 70)];
    panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    panel.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.96]; panel.layer.cornerRadius = 28;
    panel.accessibilityIdentifier = @"remote-controls"; self.remotePanel = panel;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(30, 20, panel.bounds.size.width - 60, 100)];
    title.numberOfLines = 2; title.textAlignment = NSTextAlignmentCenter; title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:28 weight:UIFontWeightSemibold];
    title.text = tv_library ? @"游戏控制面板\n切换摇杆模式或按游戏键。再次选择长按键即可松开。" :
        @"Remote controls\nChoose a stick mode or press a game button. Hold switches stay on until released.";
    [panel addSubview:title]; self.remoteButtons = [NSMutableArray array];
    NSArray *labels = @[@"Resume / Move", @"Camera stick", @"D-pad", @"Release held buttons",
        @"A", @"B", @"X", @"Y", @"L", @"R", @"ZL", @"ZR", @"+", @"−", @"L stick click", @"R stick click",
        @"Hold L", @"Hold R", @"Hold ZL", @"Hold ZR"];
    if (tv_library) labels = [labels arrayByAddingObject:@"存档并返回游戏匣"];
    NSUInteger rows = (labels.count + 3) / 4;
    CGFloat width = (panel.bounds.size.width - 180) / 4;
    for (NSUInteger i = 0; i < labels.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(35 + (i % 4) * (width + 35), 150 + (i / 4) * ((panel.bounds.size.height - 175) / rows), width, (panel.bounds.size.height - 175) / rows - 23);
        b.tag = i; [b setTitle:labels[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:26 weight:UIFontWeightSemibold];
        b.accessibilityIdentifier = [@"remote-" stringByAppendingString:labels[i]];
        [b addTarget:self action:@selector(remoteAction:) forControlEvents:UIControlEventPrimaryActionTriggered];
        [panel addSubview:b]; [self.remoteButtons addObject:b];
    }
    [self.view addSubview:panel]; [self setNeedsFocusUpdate]; [self updateFocusIfNeeded];
    fprintf(stderr, "tvOS Remote: controls opened\n");
}
- (void)remoteAction:(UIButton *)button {
    NSInteger i = button.tag;
    if (i == 20 && tv_library) {
        if (tv_exit_pending) return;
        UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"返回游戏匣？"
            message:@"请先在游戏内存档。返回后本局暂停，可以继续玩。"
            preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"继续玩" style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"保存并返回" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            [self hideRemotePanel];
            tv_return_to_library();
        }]];
        [self presentViewController:confirm animated:YES completion:nil];
        return;
    }
    if (i < 3) {
        tv_remote_mode(&remote_state, (int)i);
        [NSUserDefaults.standardUserDefaults setInteger:i forKey:(tv_title_id ? TVGamePreference(tv_title_id, @"RemoteMode") : @"TVRemoteMode")];
        fprintf(stderr, "tvOS Remote: mode=%ld\n", (long)i); [self hideRemotePanel]; return;
    }
    if (i == 3) { tv_remote_cancel(&remote_state, 1); input_publish(); [self updateRemoteHint]; return; }
    static const uint64_t buttons[] = { DM_BTN_A, DM_BTN_B, DM_BTN_X, DM_BTN_Y, DM_BTN_L, DM_BTN_R, DM_BTN_ZL, DM_BTN_ZR,
        DM_BTN_PLUS, DM_BTN_MINUS, DM_BTN_LS, DM_BTN_RS, DM_BTN_L, DM_BTN_R, DM_BTN_ZL, DM_BTN_ZR };
    uint64_t bit = buttons[i - 4];
    if (i >= 16) {
        remote_state.held ^= bit; input_publish(); [self updateRemoteHint];
        [button setTitle:[NSString stringWithFormat:@"%@ %@", remote_state.held & bit ? @"Release" : @"Hold", @[@"L", @"R", @"ZL", @"ZR"][i-16]] forState:UIControlStateNormal];
        return;
    }
    [self pulseRemoteButton:bit];
}
- (void)pulseRemoteButton:(uint64_t)bit {
    // The focused button produces one bounded pulse, never an accidental hold.
    remote_state.pulse = bit; input_publish(); NSUInteger serial = ++self.pulseSerial;
    fprintf(stderr, "tvOS Remote: pulse=0x%llx\n", (unsigned long long)bit);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (self.pulseSerial != serial) return;
        remote_state.pulse = 0; input_publish();
    });
}
- (BOOL)remotePress:(UIPress *)press down:(BOOL)down {
    if (!tv_active || self.presentedViewController || !self.remoteHint) return NO;
    if (press.type == UIPressTypePlayPause) { if (down) [self showRemotePanel]; return YES; }
    if (self.remotePanel) {
        if (press.type == UIPressTypeMenu) { if (down) [self hideRemotePanel]; return YES; }
        return NO;
    }
    uint64_t button = press.type == UIPressTypeSelect ? DM_BTN_A : press.type == UIPressTypeMenu ? DM_BTN_B : 0;
    int direction = press.type == UIPressTypeLeftArrow ? TV_REMOTE_LEFT : press.type == UIPressTypeRightArrow ? TV_REMOTE_RIGHT :
        press.type == UIPressTypeUpArrow ? TV_REMOTE_UP : press.type == UIPressTypeDownArrow ? TV_REMOTE_DOWN : 0;
    if (!button && !direction) return NO;
    if (down) { remote_state.pressed |= button; remote_state.directions |= direction; }
    else { remote_state.pressed &= ~button; remote_state.directions &= ~direction; }
    input_publish(); return YES;
}
- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    NSMutableSet *unhandled = [NSMutableSet set];
    for (UIPress *p in presses) if (![self remotePress:p down:YES]) [unhandled addObject:p];
    if (unhandled.count) [super pressesBegan:unhandled withEvent:event];
}
- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    NSMutableSet *unhandled = [NSMutableSet set];
    for (UIPress *p in presses) if (![self remotePress:p down:NO]) [unhandled addObject:p];
    if (unhandled.count) [super pressesEnded:unhandled withEvent:event];
}
- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    tv_remote_cancel(&remote_state, 0); input_publish();
    [super pressesCancelled:presses withEvent:event];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; [self becomeFirstResponder];
    if (self.remoteHint) [self updateRemoteHint];
    front_tv_start();
}
@end
UIViewController *front_tv_root(void) { tv_root = [TVRootVC new]; return tv_root; }
static UILabel *libraryLabel(NSString *text, CGFloat size, UIFontWeight weight) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.numberOfLines = 0;
    label.textColor = UIColor.whiteColor;
    return label;
}

static void tv_held_options(void) {
    TVRootVC *root = (TVRootVC *)tv_root;
    if (!root.remoteHint || root.remotePanel || root.presentedViewController) return;
    [root showRemotePanel];
}

@interface TVLibraryVC : UIViewController
@end
@implementation TVLibraryVC
- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    if (tv_play.enabled) return @[tv_play];
    return tv_settings ? @[tv_settings] : [super preferredFocusEnvironments];
}
@end

static void tv_refresh_cloud_status(void) {
    NSUInteger check=++tv_cloud_check;
    if (!front_cloudkit_configured()) {tv_cloud_status.text=@"本机存档 · 此版本未获 iCloud 权限";return;}
    if ([NSUserDefaults.standardUserDefaults boolForKey:TVGamePreference(tv_title_id,@"CloudDisabled")]) {
        tv_cloud_status.text=@"本机存档 · 自动同步已关闭";return;
    }
    tv_cloud_status.text=@"正在检查 iCloud…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        char scope[33]={0};BOOL available=front_cloudkit_account(scope);
        fprintf(stderr,"tvOS shelf: shared CloudKit account %s\n", available ? "available" : "unavailable");
        dispatch_async(dispatch_get_main_queue(),^{
            if(check==tv_cloud_check)tv_cloud_status.text=available?@"iCloud 自动存档已连接":@"iCloud 当前无法连接 · 使用本机存档";
        });
    });
}

static void tv_present_options(void) {
    if (tv_checking_saves) return;
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    NSString *hintKey=TVGamePreference(tv_title_id,@"KeepHints"), *cloudKey=TVGamePreference(tv_title_id,@"CloudDisabled");
    NSString *faceKey=TVGamePreference(tv_title_id,@"SwapFace");
    BOOL hints=[prefs boolForKey:hintKey], cloudOff=[prefs boolForKey:cloudKey];
    UIAlertController *settings=[UIAlertController alertControllerWithTitle:@"本游戏设置"
        message:tv_game_opened?@"手柄提示下次返回游戏时生效。自动存档设置在重新打开应用后生效。":@"使用遥控器或手柄导航。iCloud 会自动同步已提交的存档。"
        preferredStyle:UIAlertControllerStyleAlert];
    [settings addAction:[UIAlertAction actionWithTitle:hints?@"自动隐藏手柄提示":@"始终显示手柄提示" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
        [prefs setBool:!hints forKey:hintKey];
    }]];
    [settings addAction:[UIAlertAction actionWithTitle:tv_swap_face?@"ABXY：改为任天堂位置":@"ABXY：改为按字母映射" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
        tv_swap_face = !tv_swap_face;
        [prefs setBool:tv_swap_face forKey:faceKey];
    }]];
    if(front_cloudkit_configured())[settings addAction:[UIAlertAction actionWithTitle:cloudOff?@"开启自动存档同步":@"关闭自动存档同步" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
        [prefs setBool:!cloudOff forKey:cloudKey];
        if(!tv_game_opened)tv_refresh_cloud_status();
    }]];
    [settings addAction:[UIAlertAction actionWithTitle:@"返回" style:UIAlertActionStyleCancel handler:nil]];
    [tv_library_home presentViewController:settings animated:YES completion:nil];
}

static void tv_return_to_library(void) {
    if (!tv_library || !tv_game_visible || tv_exit_pending) return;
    tv_exit_pending = YES;
    front_tv_focus(0);
    void (^done)(BOOL) = ^(BOOL synchronized) {
        tv_exit_pending = NO;
        tv_game_visible = NO;
        UIApplication.sharedApplication.idleTimerDisabled = NO;
        UIViewController *shelf = tv_gallery_home ?: tv_library_home;
        [tv_library setViewControllers:@[shelf] animated:YES];
        UIButtonConfiguration *cfg = tv_play.configuration;
        cfg.title = @"继续游戏"; tv_play.configuration = cfg;
        tv_refresh_cloud_status();
        if (synchronized && tv_return_to_shelf) tv_return_to_shelf();
        if (!synchronized) {
            UIAlertController *notice = [UIAlertController alertControllerWithTitle:@"云存档还在同步"
              message:@"本机进度已保留。可以先继续游戏，或稍后再检查同步。" preferredStyle:UIAlertControllerStyleAlert];
            [notice addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
                if (!tv_game_visible) [shelf presentViewController:notice animated:YES completion:nil];
            });
        }
    };
    if (tv_flush_game) tv_flush_game(done); else done(YES);
}

BOOL front_tv_game_visible(void) { return !tv_library || tv_game_visible; }

static void tv_open_game(void) {
    if (tv_game_visible) return;
    tv_game_visible = YES;
    UIViewController *gameView = tv_game_opened ? tv_root : front_tv_root();
    tv_game_opened = YES;
    [tv_library pushViewController:gameView animated:NO];
    front_tv_focus(1);
    UIApplication.sharedApplication.idleTimerDisabled = YES;
}

void front_tv_play_selected(void) {
    if (tv_game_visible || !tv_play.enabled) return;
    if (front_tv_runtime_blocked()) { TVShowSwitchRequired(tv_library.topViewController); return; }
    const char *sync = getenv("DM_SAVE_SYNC");
    if (tv_game_opened || (sync && !strcmp(sync, "0")) || !front_cloudkit_configured() ||
        [NSUserDefaults.standardUserDefaults boolForKey:TVGamePreference(tv_title_id,@"CloudDisabled")]) {
        tv_open_game(); return;
    }
    NSString *savePath = front_tv_save_path(), *titleID = tv_title_id;
    if (!savePath.length) { tv_open_game(); return; }
    tv_checking_saves = YES;
    tv_play.enabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        char report[1024] = {0};
        int result = save_sync_report(savePath.fileSystemRepresentation, titleID.UTF8String, NULL, 6000, report, sizeof report);
        NSMutableDictionary *fields = [NSMutableDictionary dictionary];
        if (!result) for (NSString *part in [@(report) componentsSeparatedByString:@" "]) {
            NSArray<NSString *> *pieces = [part componentsSeparatedByString:@"="];
            if (pieces.count == 2) fields[pieces[0]] = pieces[1];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            tv_checking_saves = NO;
            tv_play.enabled = YES;
            NSString *hash = fields[@"chash"];
            BOOL conflict = [fields[@"conflict"] isEqual:@"1"] && hash.length == SS_HASH &&
                [hash rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location == NSNotFound;
            if (!conflict) { tv_open_game(); return; }
            UIAlertController *dialog = [UIAlertController alertControllerWithTitle:@"发现两份游戏存档"
                message:@"这台电视和 iCloud 都有不同的进度。选择要继续的存档；选择离线游玩时不会覆盖云端。" preferredStyle:UIAlertControllerStyleAlert];
            for (NSArray<NSString *> *option in @[@[@"保留本机进度",[@"local:" stringByAppendingString:hash]],
                  @[@"使用 iCloud 进度",[@"cloud:" stringByAppendingString:hash]],@[@"离线游玩",@"offline"]])
                [dialog addAction:[UIAlertAction actionWithTitle:option[0] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
                    setenv("DM_SAVE_SYNC_CHOICE",option[1].UTF8String,1);
                    tv_open_game();
                }]];
            [dialog addAction:[UIAlertAction actionWithTitle:@"返回" style:UIAlertActionStyleCancel handler:nil]];
            [tv_library_home presentViewController:dialog animated:YES completion:nil];
        });
    });
}

@interface TVShelfCard : UIButton
@property(nonatomic,strong) CAGradientLayer *shade;
@end
@implementation TVShelfCard
- (void)layoutSubviews {
    [super layoutSubviews];
    self.shade.frame=self.bounds;
}
- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    [coordinator addCoordinatedAnimations:^{
        self.layer.borderWidth=self.isFocused?5:0;
        self.transform=self.isFocused?CGAffineTransformMakeScale(1.045,1.045):CGAffineTransformIdentity;
    } completion:nil];
}
@end

static TVShelfCard *tv_gallery_card(NSString *title, NSString *titleID, BOOL primary, BOOL ready) {
    TVShelfCard *card=[TVShelfCard buttonWithType:UIButtonTypeCustom];
    card.translatesAutoresizingMaskIntoConstraints=NO;
    card.layer.cornerRadius=28;
    card.layer.borderColor=UIColor.whiteColor.CGColor;
    card.clipsToBounds=YES;
    card.backgroundColor=[UIColor colorWithRed:.16 green:.21 blue:.29 alpha:1];
    UIImageView *art=[[UIImageView alloc] initWithImage:TVGameArtwork(titleID,primary)];
    art.translatesAutoresizingMaskIntoConstraints=NO;
    art.contentMode=UIViewContentModeScaleAspectFill;
    [card addSubview:art];
    card.shade=[CAGradientLayer layer];
    card.shade.colors=@[(id)UIColor.clearColor.CGColor,(id)[UIColor colorWithWhite:0 alpha:.84].CGColor];
    card.shade.locations=@[@.18,@1];
    [card.layer addSublayer:card.shade];
    NSString *status=primary?(ready?@"可打开":@"资源未就绪"):@"仅供预览";
    UILabel *name=libraryLabel(title,34,UIFontWeightBold);
    UILabel *state=libraryLabel(status,24,UIFontWeightSemibold);
    state.textColor=primary&&ready?[UIColor colorWithRed:.59 green:1 blue:.79 alpha:1]:[UIColor colorWithWhite:1 alpha:.78];
    UIStackView *labels=[[UIStackView alloc] initWithArrangedSubviews:@[name,state]];
    labels.axis=UILayoutConstraintAxisVertical; labels.spacing=6;
    labels.translatesAutoresizingMaskIntoConstraints=NO;
    labels.userInteractionEnabled=NO;
    [card addSubview:labels];
    [NSLayoutConstraint activateConstraints:@[
        [card.widthAnchor constraintEqualToConstant:560], [card.heightAnchor constraintEqualToConstant:315],
        [art.leadingAnchor constraintEqualToAnchor:card.leadingAnchor], [art.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [art.topAnchor constraintEqualToAnchor:card.topAnchor], [art.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [labels.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:26],
        [labels.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-26],
        [labels.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-25]
    ]];
    card.isAccessibilityElement=YES; card.accessibilityTraits=UIAccessibilityTraitButton;
    card.accessibilityIdentifier=[@"shelf-card-" stringByAppendingString:titleID];
    card.accessibilityLabel=title; card.accessibilityValue=status;
    return card;
}

static UIViewController *tv_build_gallery(NSString *game, NSString *titleID, NSArray *previews, BOOL ready) {
    if (![previews isKindOfClass:NSArray.class] || !previews.count) return nil;
    NSMutableSet *seen=[NSMutableSet setWithObject:titleID.lowercaseString];
    NSMutableArray<UIButton *> *cards=[NSMutableArray array];
    NSDictionary *runners = [NSBundle.mainBundle objectForInfoDictionaryKey:@"DMGameboxRunners"];
    NSUInteger playable = ready ? 1 : 0;
    TVShelfCard *first=tv_gallery_card(game,titleID,YES,ready);
    [first addAction:[UIAction actionWithHandler:^(__unused UIAction *action){
        [tv_library pushViewController:tv_library_home animated:YES];
    }] forControlEvents:UIControlEventPrimaryActionTriggered];
    [cards addObject:first];
    for (id row in previews) {
        if (![row isKindOfClass:NSDictionary.class]) continue;
        NSString *key=row[@"id"], *title=row[@"title"];
        if (![key isKindOfClass:NSString.class] || key.length!=16 ||
            ![title isKindOfClass:NSString.class] || !title.length) continue;
        key=key.lowercaseString;
        if ([seen containsObject:key] || [key rangeOfCharacterFromSet:
            [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location!=NSNotFound) continue;
        [seen addObject:key];
        NSString *root = TVGameResourceRoot(key);
        BOOL bundled = [runners[key] isKindOfClass:NSString.class];
        BOOL available = bundled &&
            [NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:@"RomFS.img"]] &&
            ([NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:@"msl.tar.gz"]] ||
             [NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:@"msl/.archive-sha256"]]);
        if (available) playable++;
        TVShelfCard *card=tv_gallery_card(title,key,bundled,available);
        [card addAction:[UIAction actionWithHandler:^(__unused UIAction *action){
            if (bundled) { front_tv_show_runtime(title, key, tv_gallery_home); return; }
            UIAlertController *dialog=[UIAlertController alertControllerWithTitle:title
                message:@"这是游戏库预览。这款游戏的 Apple TV 运行组件尚未安装。"
                preferredStyle:UIAlertControllerStyleAlert];
            [dialog addAction:[UIAlertAction actionWithTitle:@"返回游戏库" style:UIAlertActionStyleCancel handler:nil]];
            [tv_gallery_home presentViewController:dialog animated:YES completion:nil];
        }] forControlEvents:UIControlEventPrimaryActionTriggered];
        [cards addObject:card];
    }
    if (cards.count==1) return nil;

    UIViewController *controller=[UIViewController new];
    UIView *view=controller.view;
    view.backgroundColor=[UIColor colorWithRed:.055 green:.075 blue:.11 alpha:1];
    UILabel *brand=libraryLabel(@"TonTon 游戏匣",36,UIFontWeightSemibold);
    brand.textColor=[UIColor colorWithWhite:1 alpha:.70];
    UILabel *heading=libraryLabel(@"游戏库",76,UIFontWeightHeavy);
    UILabel *summary=libraryLabel([NSString stringWithFormat:@"%lu 款游戏  ·  %lu 款可打开",(unsigned long)cards.count,(unsigned long)playable],27,UIFontWeightMedium);
    summary.textColor=[UIColor colorWithWhite:1 alpha:.68];
    UILabel *all=libraryLabel(@"所有游戏",32,UIFontWeightBold);
    UIStackView *tiles=[[UIStackView alloc] initWithArrangedSubviews:cards];
    tiles.axis=UILayoutConstraintAxisHorizontal; tiles.spacing=40;
    tiles.translatesAutoresizingMaskIntoConstraints=NO;
    UIScrollView *scroll=[UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints=NO; scroll.clipsToBounds=NO;
    scroll.showsHorizontalScrollIndicator=NO; scroll.showsVerticalScrollIndicator=NO;
    [scroll addSubview:tiles];
    UIStackView *body=[[UIStackView alloc] initWithArrangedSubviews:@[brand,heading,summary,all,scroll]];
    body.axis=UILayoutConstraintAxisVertical; body.spacing=17;
    [body setCustomSpacing:75 afterView:summary]; [body setCustomSpacing:25 afterView:all];
    body.translatesAutoresizingMaskIntoConstraints=NO;
    [view addSubview:body];
    UILayoutGuide *safe=view.safeAreaLayoutGuide, *content=scroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [body.topAnchor constraintEqualToAnchor:safe.topAnchor constant:75],
        [body.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:52],
        [body.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-50],
        [scroll.heightAnchor constraintEqualToConstant:345],
        [tiles.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:5],
        [tiles.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-25],
        [tiles.topAnchor constraintEqualToAnchor:content.topAnchor constant:10],
        [tiles.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20]
    ]];
    return controller;
}

UIViewController *front_tv_library_root(NSString *game, NSString *titleID, NSArray *previews, void (^flush)(void (^)(BOOL))) {
    tv_flush_game = [flush copy];
    tv_title_id = [titleID copy];
    tv_swap_face = [NSUserDefaults.standardUserDefaults boolForKey:TVGamePreference(tv_title_id,@"SwapFace")];
    tv_library_home = [TVLibraryVC new];
    UIView *view = tv_library_home.view;
    view.backgroundColor = [UIColor colorWithRed:.06 green:.07 blue:.10 alpha:1];
    UILabel *brand = libraryLabel(@"TonTon 游戏匣", 45, UIFontWeightBold);
    UIImageView *art = [[UIImageView alloc] initWithImage:TVGameArtwork(titleID, YES)];
    art.translatesAutoresizingMaskIntoConstraints = NO;
    art.contentMode = UIViewContentModeScaleAspectFill;
    art.clipsToBounds = YES;
    art.layer.cornerRadius = 32;
    art.backgroundColor = [UIColor colorWithWhite:.12 alpha:1];
    if (!art.image) {
        art.image = [UIImage systemImageNamed:@"gamecontroller.fill"];
        art.tintColor = [UIColor colorWithWhite:1 alpha:.75];
        art.contentMode = UIViewContentModeCenter;
    }
    UIVisualEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    if (@available(tvOS 26.0,*)) effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
    UIVisualEffectView *panel = [[UIVisualEffectView alloc] initWithEffect:effect];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.layer.cornerRadius = 32; panel.clipsToBounds = YES;
    UILabel *title = libraryLabel(game, 46, UIFontWeightBold);
    UILabel *device = libraryLabel(@"APPLE TV  ·  游戏库", 23, UIFontWeightSemibold);
    device.textColor = [UIColor colorWithWhite:1 alpha:.75];
    tv_cloud_status = libraryLabel(nil, 23, UIFontWeightMedium);
    tv_cloud_status.textColor = [UIColor colorWithWhite:1 alpha:.76];
    BOOL canOpen = front_tv_ready() || front_tv_preparing();
    UILabel *hint = libraryLabel(canOpen
        ? @"游戏中按遥控器的播放／暂停，或长按手柄的选项键，打开控制面板。"
        : @"这台 Apple TV 缺少此游戏的本地文件。恢复游戏文件后，重新打开游戏匣即可。", 24, UIFontWeightRegular);
    hint.textColor = [UIColor colorWithWhite:1 alpha:.74];
    UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
    if (@available(tvOS 26.0,*)) configuration = [UIButtonConfiguration prominentGlassButtonConfiguration];
    configuration.title = canOpen ? @"开始游戏" : @"游戏文件未就绪";
    configuration.image = [UIImage systemImageNamed:canOpen ? @"play.fill" : @"externaldrive.badge.exclamationmark"];
    configuration.imagePadding = 14;
    tv_play = [UIButton buttonWithConfiguration:configuration primaryAction:[UIAction actionWithHandler:^(__unused UIAction *action){front_tv_play_selected();}]];
    tv_play.enabled = canOpen;
    tv_play.accessibilityIdentifier = @"gamebox-play";
    UIButtonConfiguration *settingStyle = [UIButtonConfiguration grayButtonConfiguration];
    if (@available(tvOS 26.0,*)) settingStyle = [UIButtonConfiguration glassButtonConfiguration];
    settingStyle.title = @"本游戏设置";
    settingStyle.image = [UIImage systemImageNamed:@"slider.horizontal.3"];
    settingStyle.imagePadding = 12;
    tv_settings = [UIButton buttonWithConfiguration:settingStyle primaryAction:[UIAction actionWithHandler:^(__unused UIAction *action){tv_present_options();}]];
    tv_settings.accessibilityIdentifier = @"gamebox-settings";
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[device,title,tv_cloud_status,tv_play,tv_settings,hint]];
    if (tv_return_to_shelf) {
        UIButton *back = [UIButton buttonWithConfiguration:[UIButtonConfiguration grayButtonConfiguration]
            primaryAction:[UIAction actionWithHandler:^(__unused UIAction *action){ tv_return_to_shelf(); }]];
        [back setTitle:@"返回游戏库" forState:UIControlStateNormal];
        [actions addArrangedSubview:back];
    }
    actions.axis = UILayoutConstraintAxisVertical; actions.spacing = 22;
    actions.alignment = UIStackViewAlignmentLeading;
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    [panel.contentView addSubview:actions];
    UIStackView *hero = [[UIStackView alloc] initWithArrangedSubviews:@[art,panel]];
    hero.axis = UILayoutConstraintAxisHorizontal; hero.spacing = 52;
    UIStackView *layout = [[UIStackView alloc] initWithArrangedSubviews:@[brand,hero]];
    layout.axis = UILayoutConstraintAxisVertical; layout.spacing = 42;
    layout.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:layout];
    UILayoutGuide *safe = view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [layout.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [layout.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:48],
        [layout.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-48],
        [art.widthAnchor constraintEqualToAnchor:hero.widthAnchor multiplier:.58],
        [art.heightAnchor constraintEqualToAnchor:safe.heightAnchor multiplier:.69],
        [actions.centerYAnchor constraintEqualToAnchor:panel.contentView.centerYAnchor],
        [actions.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor constant:42],
        [actions.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor constant:-42]
    ]];
    tv_gallery_home = tv_build_gallery(game, titleID, previews, canOpen);
    tv_library = [[UINavigationController alloc] initWithRootViewController:tv_gallery_home ?: tv_library_home];
    [tv_library setNavigationBarHidden:YES animated:NO];
    tv_refresh_cloud_status();
    return tv_library;
}
void front_tv_resources_ready(NSString *failure) {
    TVRootVC *root = (TVRootVC *)tv_root;
    if (failure) {
        if (!root.preparationLabel) {
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(root.view.bounds, 70, 70)];
            label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            label.numberOfLines = 0; label.textColor = UIColor.whiteColor;
            label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.82];
            label.textAlignment = NSTextAlignmentCenter;
            root.preparationLabel = label; [root.view addSubview:label];
        }
        root.preparationLabel.text = failure; return;
    }
    [root createGame]; front_tv_start();
}
void *front_metal_layer(void) { return (__bridge void *)tv_layer; }
int front_screen_max_fps(void) { return 60; }
void front_screen_match(int fps) { (void)fps; }
void front_run(void (*guest)(void)) { guest(); }
int dm_thermal_now(void) { return (int)NSProcessInfo.processInfo.thermalState; }
int dm_low_power_now(void) { return 0; }
double dm_brightness_now(void) { return -1; }
void front_save_failed(int err) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save failed"
            message:[NSString stringWithFormat:@"Progress was not saved (error %d).", err] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [tv_root presentViewController:alert animated:YES completion:nil];
    });
}
int front_text_input(const char *title, const char *sub, const char *guide, const char *initial, int max_chars, char *out, int out_cap) {
    __block int accepted = 0; __block NSString *text = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@(title ?: "")
            message:@(sub ?: "") preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = @(initial ?: ""); f.placeholder = @(guide ?: ""); }];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { text = alert.textFields.firstObject.text; accepted = 1; dispatch_semaphore_signal(done); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) { dispatch_semaphore_signal(done); }]];
        [tv_root presentViewController:alert animated:YES completion:nil];
    });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    if (accepted) snprintf(out, out_cap, "%s", text.UTF8String ?: "");
    return accepted;
}

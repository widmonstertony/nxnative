#import <XCTest/XCTest.h>
@interface RemoteUITests:XCTestCase
@end
@implementation RemoteUITests
- (void)testGameboxSettingsAndOfflineSaveChoice {
    self.continueAfterFailure=NO;
    XCUIApplication *app=[[XCUIApplication alloc] initWithBundleIdentifier:@"org.nxnative.tvremote-harness"];
    app.launchArguments=@[@"-ton-ton-shelf"];
    app.launchEnvironment=@{@"TV_MOCK_SAVE":@"1"};
    [app launch];
    XCTAssertTrue([app.staticTexts[@"宝可梦传说 Z-A"] waitForExistenceWithTimeout:10]);
    XCTAssertTrue([app.staticTexts[@"iCloud 自动存档已连接"] waitForExistenceWithTimeout:5]);
    if (!app.buttons[@"gamebox-settings"].hasFocus) [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonDown];
    XCTAssertTrue(app.buttons[@"gamebox-settings"].hasFocus);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonSelect];
    XCTAssertTrue([app.buttons[@"始终显示手柄提示"] waitForExistenceWithTimeout:5] || app.buttons[@"自动隐藏手柄提示"].exists);
    XCTAssertTrue(app.buttons[@"ABXY：改为按字母映射"].exists || app.buttons[@"ABXY：改为任天堂位置"].exists);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonMenu];
    if (!app.buttons[@"gamebox-play"].hasFocus) [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonUp];
    XCTAssertTrue(app.buttons[@"gamebox-play"].hasFocus);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonSelect];
    XCTAssertTrue([app.buttons[@"离线游玩"] waitForExistenceWithTimeout:8]);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonMenu];
    XCTAssertTrue(app.buttons[@"gamebox-play"].exists);
}

- (void)testGameboxReturnAndResumeWithoutRestarting {
    self.continueAfterFailure=NO;
    XCUIApplication *app=[[XCUIApplication alloc] initWithBundleIdentifier:@"org.nxnative.tvremote-harness"];
    app.launchArguments=@[@"-ton-ton-shelf"];
    [app launch];
    XCTAssertTrue([app.buttons[@"gamebox-play"] waitForExistenceWithTimeout:10]);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonSelect];
    XCTAssertTrue([app.staticTexts[@"remote-hint"] waitForExistenceWithTimeout:5]);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonPlayPause];
    XCTAssertTrue([app.otherElements[@"remote-controls"] waitForExistenceWithTimeout:5]);
    for(int row=0;row<5;row++) [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonDown];
    XCTAssertTrue(app.buttons[@"remote-存档并返回游戏匣"].hasFocus);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonSelect];
    XCTAssertTrue([app.buttons[@"保存并返回"] waitForExistenceWithTimeout:5]);
    if (!app.buttons[@"保存并返回"].hasFocus) [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonRight];
    if (!app.buttons[@"保存并返回"].hasFocus) [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonDown];
    XCTAssertTrue(app.buttons[@"保存并返回"].hasFocus);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonSelect];
    XCTAssertTrue([app.buttons[@"gamebox-play"] waitForExistenceWithTimeout:5]);
    XCTAssertEqualObjects(app.buttons[@"gamebox-play"].label,@"继续游戏");
    XCTAssertTrue(app.buttons[@"gamebox-play"].hasFocus);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonSelect];
    XCTAssertTrue([app.staticTexts[@"remote-hint"] waitForExistenceWithTimeout:5]);
}

- (void)testProductionRemoteUI {
    self.continueAfterFailure=NO;
    XCUIApplication *app=[[XCUIApplication alloc] initWithBundleIdentifier:@"org.nxnative.tvremote-harness"];
    [app launch];
    XCTAssertTrue([app.staticTexts[@"remote-hint"] waitForExistenceWithTimeout:10]);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonPlayPause];
    XCTAssertTrue([app.otherElements[@"remote-controls"] waitForExistenceWithTimeout:5]);
    XCTAssertTrue(app.buttons[@"remote-Resume / Move"].hasFocus);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonRight];
    XCTAssertTrue(app.buttons[@"remote-Camera stick"].hasFocus);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonSelect];
    XCTAssertFalse(app.otherElements[@"remote-controls"].exists);
    XCTAssertTrue([app.staticTexts[@"remote-hint"].label containsString:@"CAMERA"]);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonRight];
    XCTAssertTrue([app.staticTexts[@"qa-pad-history"].label containsString:@"0,0,0,32767,0"]);
    XCTAssertEqualObjects(app.staticTexts[@"qa-pad-state"].label,@"0,0,0,0,0");
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonSelect];
    XCTAssertTrue([app.staticTexts[@"qa-pad-history"].label containsString:@"1,0,0,0,0"]);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonMenu];
    XCTAssertTrue([app.staticTexts[@"qa-pad-history"].label containsString:@"2,0,0,0,0"]);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonPlayPause];
    XCTAssertTrue([app.otherElements[@"remote-controls"] waitForExistenceWithTimeout:5]);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonSelect];
    XCTAssertTrue([app.staticTexts[@"remote-hint"].label containsString:@"MOVE"]);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonPlayPause];
    for(int i=0;i<4;i++) [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonDown];
    XCTAssertTrue(app.buttons[@"remote-Hold L"].hasFocus);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonSelect];
    XCTAssertTrue([app.staticTexts[@"remote-hint"].label containsString:@"Holding: L"]);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonMenu];
    XCTAssertFalse(app.otherElements[@"remote-controls"].exists);
    XCTAssertEqualObjects(app.staticTexts[@"qa-pad-state"].label,@"64,0,0,0,0");
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonPlayPause];
    for(int i=0;i<3;i++) [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonRight];
    XCTAssertTrue(app.buttons[@"remote-Release held buttons"].hasFocus);
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonSelect];
    XCTAssertEqualObjects(app.staticTexts[@"qa-pad-state"].label,@"0,0,0,0,0");
    XCTAttachment *a=[XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];a.lifetime=XCTAttachmentLifetimeKeepAlways;[self addAttachment:a];
    [XCUIRemote.sharedRemote pressButton:XCUIRemoteButtonMenu];
    XCTAssertFalse(app.otherElements[@"remote-controls"].exists);
}
@end

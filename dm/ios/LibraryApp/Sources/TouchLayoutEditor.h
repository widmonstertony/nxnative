#pragma once
#import <UIKit/UIKit.h>
#import "../../Sources/DmPadGeometry.h"

static NSString *const TTPadLayoutPreference = @"tonton.touch-layout.v2";
static NSString *TTPadLayoutKey(NSString *titleID) {
    return [TTPadLayoutPreference stringByAppendingFormat:@".%@", titleID.lowercaseString];
}
static NSString *TTReadTouchLayout(NSString *titleID) {
    if (titleID.length != 16) return nil;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *value = [defaults stringForKey:TTPadLayoutKey(titleID)];
    // The prior global layout was the player's Need for Speed layout. Keep
    // that customization there without inheriting it in any other title.
    if (!value && [titleID caseInsensitiveCompare:@"010029B0118E8000"] == NSOrderedSame)
        value = [defaults stringForKey:TTPadLayoutPreference];
    return value;
}
static NSString *TTPadLayoutEncode(DmPadLayout value) {
    NSMutableString *out=[NSMutableString stringWithString:@"2"];
    for(int mode=0;mode<DM_PAD_SET_N;mode++){
        BOOL section=NO;
        for(int c=0;c<DM_PAD_C_N;c++) if(value.dx[mode][c]||value.dy[mode][c]){
            if(!section){[out appendFormat:@";%s",dm_pad_set_names[mode]];section=YES;}
            [out appendFormat:@"/%s:%d,%d",dm_pad_control_names[c],value.dx[mode][c],value.dy[mode][c]];
        }
    }
    return out;
}
static void TTApplyTouchLayout(NSString *titleID) {
    NSString *value=TTReadTouchLayout(titleID);
    DmPadLayout parsed;
    if(value.length && dm_pad_layout_parse(value.UTF8String,&parsed) && dm_pad_layout_count(&parsed))setenv("DM_TOUCH_LAYOUT",value.UTF8String,1);
    else unsetenv("DM_TOUCH_LAYOUT");
}

@interface TTPadLayoutEditor : UIViewController
- (instancetype)initWithTitleID:(NSString *)titleID;
@end
@implementation TTPadLayoutEditor {
    NSString *_titleID;
    DmPadLayout _layout;
    DmPadGeo _geometry;
    UISegmentedControl *_mode;
    UISwitch *_linked;
    UIView *_canvas;
    NSArray<UIButton *> *_buttons;
    UILabel *_status;
    int _selected;
    short _dragX,_dragY;
    CGFloat _scale;
}
- (instancetype)initWithTitleID:(NSString *)titleID {
    if (titleID.length != 16) return nil;
    if ((self = [super initWithNibName:nil bundle:nil])) _titleID = [titleID copy];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"\u865A\u62DF\u624B\u67C4\u5E03\u5C40";
    self.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    dm_pad_layout_parse(TTReadTouchLayout(_titleID).UTF8String,&_layout);
    _layout.precision=2;_selected=DM_PAD_C_A;
    _mode=[[UISegmentedControl alloc]initWithItems:@[@"2D",@"3D"]];
    _mode.selectedSegmentIndex=0;
    [_mode addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    _linked=[UISwitch new];
    _linked.accessibilityLabel=@"ABXY \u8054\u52A8";
    [_linked addTarget:self action:@selector(linkChanged) forControlEvents:UIControlEventValueChanged];
    UILabel *linkLabel=[UILabel new];linkLabel.text=@"ABXY \u8054\u52A8";
    UIStackView *link=[[UIStackView alloc]initWithArrangedSubviews:@[linkLabel,_linked]];link.spacing=12;link.alignment=UIStackViewAlignmentCenter;
    _canvas=[UIView new];_canvas.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    _canvas.layer.cornerRadius=14;_canvas.clipsToBounds=YES;
    NSMutableArray *buttons=[NSMutableArray new];
    // Upstream slots are right/bottom/top/left; the normal game labels are B/A/Y/X.
    NSArray *labels=@[@"ABXY",@"B",@"A",@"Y",@"X",@"\u6447\u6746",@"\u5341\u5B57",@"ZL",@"L",@"ZR",@"R",@"L3",@"R3",@"\u2212",@"+"];
    for(int c=0;c<DM_PAD_C_N;c++){
        UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.tag=c;
        [b setTitle:labels[c] forState:UIControlStateNormal];
        b.titleLabel.adjustsFontSizeToFitWidth=YES;
        [b addTarget:self action:@selector(selectControl:) forControlEvents:UIControlEventTouchUpInside];
        [b addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(drag:)]];
        b.hidden=YES;b.layer.borderWidth=1;[_canvas addSubview:b];[buttons addObject:b];
    }
    _buttons=buttons;
    _status=[UILabel new];_status.numberOfLines=0;_status.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _status.textColor=UIColor.secondaryLabelColor;
    UIStackView *arrows=[UIStackView new];arrows.distribution=UIStackViewDistributionFillEqually;arrows.spacing=8;
    NSArray *names=@[@"\u2190",@"\u2191",@"\u2193",@"\u2192"];
    for(int i=0;i<4;i++){UIButton *button=[self control:names[i] action:@selector(nudge:)];button.tag=i;[arrows addArrangedSubview:button];}
    UIStackView *reset=[[UIStackView alloc]initWithArrangedSubviews:@[
        [self control:@"\u91CD\u7F6E\u9009\u4E2D" action:@selector(resetSelected)],[self control:@"\u91CD\u7F6E\u5F53\u524D\u5E03\u5C40" action:@selector(resetMode)],
        [self control:@"\u5168\u90E8\u91CD\u7F6E" action:@selector(resetAll)]]];
    reset.distribution=UIStackViewDistributionFillEqually;reset.spacing=4;
    UIStackView *column=[[UIStackView alloc]initWithArrangedSubviews:@[_mode,link,_canvas,arrows,reset,_status]];
    column.axis=UILayoutConstraintAxisVertical;column.spacing=10;column.translatesAutoresizingMaskIntoConstraints=NO;
    UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:scroll];[scroll addSubview:column];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide,*content=scroll.contentLayoutGuide,*frame=scroll.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [column.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],[column.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
        [column.topAnchor constraintEqualToAnchor:content.topAnchor constant:12],[column.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14],
        [column.widthAnchor constraintEqualToAnchor:frame.widthAnchor constant:-28],[_canvas.heightAnchor constraintEqualToAnchor:_canvas.widthAnchor multiplier:0.54],
        [arrows.heightAnchor constraintGreaterThanOrEqualToConstant:44],[reset.heightAnchor constraintGreaterThanOrEqualToConstant:44]]];
}
- (UIButton *)control:(NSString *)label action:(SEL)action {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:label forState:UIControlStateNormal];[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return b;
}
- (int)mode { return _mode.selectedSegmentIndex==1?DM_PAD_SET_3D:DM_PAD_SET_2D; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews];[self renderControls]; }
- (DmPadGeo)geometryFor:(const DmPadLayout *)value {
    CGSize device=self.view.window.windowScene.screen.bounds.size;
    CGFloat w=MAX(device.width,device.height),h=MIN(device.width,device.height);
    if(h<1){w=844;h=390;}
    CGRect bounds=CGRectMake(0,0,w,h);
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    DmPadOptions options={
        dm_pad_size_scale([prefs stringForKey:@"tonton.global.DM_TOUCH_SIZE"].UTF8String),
        dm_pad_stick_place([prefs stringForKey:@"tonton.global.DM_TOUCH_STICK"].UTF8String),value};
    return dm_pad_geo(bounds,UIEdgeInsetsZero,(DmLayout){.controls=bounds},self.mode==DM_PAD_SET_3D,options);
}
- (void)renderControls {
    _geometry=[self geometryFor:&_layout];
    if(CGRectIsEmpty(_canvas.bounds)||CGRectIsEmpty(_geometry.corner))return;
    CGFloat w=_geometry.corner.size.width,h=_geometry.corner.size.height;
    _scale=MIN(_canvas.bounds.size.width/w,_canvas.bounds.size.height/h);
    CGFloat x0=(_canvas.bounds.size.width-w*_scale)/2,y0=(_canvas.bounds.size.height-h*_scale)/2;
    DmPadShape shapes[20];
    int count=dm_pad_shapes(&_geometry,self.mode==DM_PAD_SET_3D,shapes);
    for(int c=DM_PAD_C_A;c<DM_PAD_C_N;c++){
        BOOL found=NO;
        for(int i=0;i<count;i++)if(dm_pad_is_shape_of(shapes[i].id,c)){
            CGRect b=dm_pad_shape_box(&shapes[i]);
            UIButton *button=_buttons[c];
            button.frame=CGRectMake(x0+b.origin.x*_scale,y0+b.origin.y*_scale,b.size.width*_scale,b.size.height*_scale);
            BOOL selected=_selected==c||(_selected==DM_PAD_C_FACE&&c>=DM_PAD_C_A&&c<=DM_PAD_C_Y);
            button.backgroundColor=selected?UIColor.systemBlueColor:UIColor.tertiarySystemGroupedBackgroundColor;
            [button setTitleColor:selected?UIColor.whiteColor:UIColor.labelColor forState:UIControlStateNormal];
            button.layer.borderColor=UIColor.separatorColor.CGColor;
            button.layer.cornerRadius=MIN(button.bounds.size.height,button.bounds.size.width)/2;
            found=YES;break;
        }
        _buttons[c].hidden=!found;
    }
    _status.text=@"\u62D6\u52A8\u6309\u952E\uFF0C\u6216\u7528\u7BAD\u5934\u5FAE\u8C03\u30022D \u548C 3D \u5206\u5F00\u4FDD\u5B58\uFF0C\u4E0B\u6B21\u5F00\u6E38\u620F\u751F\u6548\u3002";
}
- (void)persist {
    [NSUserDefaults.standardUserDefaults setObject:TTPadLayoutEncode(_layout) forKey:TTPadLayoutKey(_titleID)];
    [self renderControls];
}
- (void)modeChanged { _selected=_linked.on?DM_PAD_C_FACE:DM_PAD_C_A;[self renderControls]; }
- (void)linkChanged {
    if(_linked.on&&_selected>=DM_PAD_C_A&&_selected<=DM_PAD_C_Y)_selected=DM_PAD_C_FACE;
    else if(!_linked.on&&_selected==DM_PAD_C_FACE)_selected=DM_PAD_C_A;
    [self renderControls];
}
- (void)selectControl:(UIButton *)sender {
    int c=(int)sender.tag;_selected=_linked.on&&c>=DM_PAD_C_A&&c<=DM_PAD_C_Y?DM_PAD_C_FACE:c;
    [self renderControls];
}
- (void)moveX:(int)x y:(int)y {
    int m=self.mode,c=_selected;
    DmPadLayout proposed=_layout;
    proposed.dx[m][c]=(short)MAX(-DM_PAD_FINE_STEP_MAX,MIN(DM_PAD_FINE_STEP_MAX,x));
    proposed.dy[m][c]=(short)MAX(-DM_PAD_FINE_STEP_MAX,MIN(DM_PAD_FINE_STEP_MAX,y));
    DmPadGeo geo=[self geometryFor:&proposed];
    if(geo.dropped & ~_geometry.dropped || geo.dropped & (1u<<c)){
        _status.text=@"\u8FD9\u4E2A\u4F4D\u7F6E\u4F1A\u6321\u4F4F\u5176\u4ED6\u6309\u952E\u3002";return;
    }
    _layout=proposed;[self persist];
}
- (void)drag:(UIPanGestureRecognizer *)pan {
    if(pan.state==UIGestureRecognizerStateBegan){
        [self selectControl:(UIButton *)pan.view];_dragX=_layout.dx[self.mode][_selected];_dragY=_layout.dy[self.mode][_selected];
    }
    if(pan.state==UIGestureRecognizerStateChanged||pan.state==UIGestureRecognizerStateEnded){
        CGFloat step=dm_pad_layout_step(&_geometry,&_layout)*_scale;if(step<=0)return;
        CGPoint p=[pan translationInView:_canvas];
        [self moveX:_dragX+(int)lround(p.x/step) y:_dragY+(int)lround(p.y/step)];
    }
}
- (void)nudge:(UIButton *)b {
    static const int dx[]={-1,0,0,1},dy[]={0,-1,1,0};
    [self moveX:_layout.dx[self.mode][_selected]+dx[b.tag] y:_layout.dy[self.mode][_selected]+dy[b.tag]];
}
- (void)resetSelected { _layout.dx[self.mode][_selected]=_layout.dy[self.mode][_selected]=0;[self persist]; }
- (void)resetMode {
    memset(_layout.dx[self.mode],0,sizeof _layout.dx[0]);memset(_layout.dy[self.mode],0,sizeof _layout.dy[0]);[self persist];
}
- (void)resetAll { memset(&_layout,0,sizeof _layout);_layout.precision=2;[self persist]; }
@end

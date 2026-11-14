// TonTon's iOS 16.1 presentation backport of NX2Apple's adaptive library.
// Keep the existing host's catalogue, readiness, settings, imports and launch callback.
// No engine, game path or save location is changed by this presentation layer.
#import <UIKit/UIKit.h>

static UIUserInterfaceStyle TTLibraryStyle16(void) {
    NSInteger value=[NSUserDefaults.standardUserDefaults integerForKey:@"TonTonLibraryAppearance"];
    return value==1?UIUserInterfaceStyleLight:value==2?UIUserInterfaceStyleDark:UIUserInterfaceStyleUnspecified;
}
static UIColor *TTLibraryAccent16(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle==UIUserInterfaceStyleDark?C(237,223,255):C(72,49,133);
    }];
}

@interface TTBannerCard16 : CoverCard
@property(nonatomic,strong) UIImageView *backdrop;
@end
@implementation TTBannerCard16
- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame]))return nil;
    for(UIView *view in self.contentView.subviews.copy)[view removeFromSuperview];
    self.caseView=[UIView new];self.caseView.layer.cornerRadius=16;self.caseView.clipsToBounds=YES;
    self.caseView.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    self.backdrop=[UIImageView new];self.backdrop.contentMode=UIViewContentModeScaleAspectFill;self.backdrop.clipsToBounds=YES;
    UIVisualEffectView *blur=[[UIVisualEffectView alloc]initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial]];
    self.art=[UIImageView new];self.art.contentMode=UIViewContentModeScaleAspectFit;
    self.placeholder=[UILabel new];self.placeholder.textColor=UIColor.labelColor;self.placeholder.numberOfLines=3;
    self.placeholder.textAlignment=NSTextAlignmentCenter;self.placeholder.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.title=[UILabel new];self.title.textColor=UIColor.labelColor;self.title.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];self.title.numberOfLines=2;
    self.sizeLabel=[UILabel new];self.sizeLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];self.sizeLabel.textColor=UIColor.secondaryLabelColor;
    self.badge=[UILabel new];self.badge.textAlignment=NSTextAlignmentCenter;self.badge.font=[UIFont boldSystemFontOfSize:15];self.badge.layer.cornerRadius=14;self.badge.clipsToBounds=YES;
    for(UIView *v in @[self.caseView,self.title,self.sizeLabel]){v.translatesAutoresizingMaskIntoConstraints=NO;[self.contentView addSubview:v];}
    for(UIView *v in @[self.backdrop,blur,self.art,self.placeholder,self.badge]){v.translatesAutoresizingMaskIntoConstraints=NO;[self.caseView addSubview:v];}
    NSMutableArray *constraints=[NSMutableArray array];
    for(UIView *v in @[self.backdrop,blur,self.art]) [constraints addObjectsFromArray:@[[v.topAnchor constraintEqualToAnchor:self.caseView.topAnchor],[v.bottomAnchor constraintEqualToAnchor:self.caseView.bottomAnchor],[v.leadingAnchor constraintEqualToAnchor:self.caseView.leadingAnchor],[v.trailingAnchor constraintEqualToAnchor:self.caseView.trailingAnchor]]];
    [constraints addObjectsFromArray:@[[self.caseView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],[self.caseView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],[self.caseView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],[self.caseView.heightAnchor constraintEqualToAnchor:self.caseView.widthAnchor multiplier:9.0/16.0],
        [self.title.topAnchor constraintEqualToAnchor:self.caseView.bottomAnchor constant:10],[self.title.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],[self.title.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.sizeLabel.topAnchor constraintEqualToAnchor:self.title.bottomAnchor constant:4],[self.sizeLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],[self.sizeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.placeholder.centerYAnchor constraintEqualToAnchor:self.caseView.centerYAnchor],[self.placeholder.leadingAnchor constraintEqualToAnchor:self.caseView.leadingAnchor constant:12],[self.placeholder.trailingAnchor constraintEqualToAnchor:self.caseView.trailingAnchor constant:-12],
        [self.badge.trailingAnchor constraintEqualToAnchor:self.caseView.trailingAnchor constant:-10],[self.badge.bottomAnchor constraintEqualToAnchor:self.caseView.bottomAnchor constant:-10],[self.badge.widthAnchor constraintEqualToConstant:28],[self.badge.heightAnchor constraintEqualToConstant:28]]];
    [NSLayoutConstraint activateConstraints:constraints];return self;
}
- (void)layoutSubviews { [super layoutSubviews];self.backdrop.image=self.art.image; }
- (void)setControllerFocused:(BOOL)focused {
    [super setControllerFocused:focused];
    self.title.textColor=focused?TTLibraryAccent16():UIColor.labelColor;
    self.layer.borderWidth=0;self.caseView.layer.borderWidth=focused?3:0;
    self.caseView.layer.borderColor=TTLibraryAccent16().CGColor;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous];[self setControllerFocused:self.controllerFocused]; }
@end

@interface TTLibrary16 : LibraryView
@property(nonatomic,strong) UILabel *brand,*heroTitle,*heroVersion;
@property(nonatomic,strong) UIImageView *hero;
@property(nonatomic,strong) UIImageView *emptyHeroIcon;
@property(nonatomic,strong) UIView *heroPanel;
@property(nonatomic,strong) CAGradientLayer *heroShade;
@property(nonatomic) BOOL wideLayout;
@property(nonatomic,strong) UIButton *play,*gameSettings,*appSettings,*importButton,*appearanceButton;
@end
@implementation TTLibrary16
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {return UIInterfaceOrientationMaskAllButUpsideDown;}
- (void)viewDidLoad {
    [super viewDidLoad];self.overrideUserInterfaceStyle=TTLibraryStyle16();
    [NSLayoutConstraint deactivateConstraints:self.view.constraints];
    for(UIView *v in self.view.subviews.copy)[v removeFromSuperview];
    self.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    self.brand=[UILabel new];self.brand.text=@"TonTon \u6E38\u620F\u5323";
    self.brand.textColor=UIColor.labelColor;self.brand.font=[UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    self.heroPanel=[UIView new];self.heroPanel.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;self.heroPanel.layer.cornerRadius=20;
    self.hero=[UIImageView new];self.hero.contentMode=UIViewContentModeScaleAspectFill;self.hero.clipsToBounds=YES;self.hero.layer.cornerRadius=18;self.hero.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    self.emptyHeroIcon=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"gamecontroller.fill"]];
    self.emptyHeroIcon.tintColor=TTLibraryAccent16();self.emptyHeroIcon.contentMode=UIViewContentModeScaleAspectFit;self.emptyHeroIcon.hidden=YES;
    self.heroShade=[CAGradientLayer layer];self.heroShade.colors=@[(id)[UIColor colorWithWhite:0 alpha:0].CGColor,(id)[UIColor colorWithWhite:0 alpha:0.83].CGColor];self.heroShade.locations=@[@0.38,@1.0];[self.hero.layer addSublayer:self.heroShade];
    self.heroTitle=[UILabel new];self.heroTitle.textColor=UIColor.labelColor;self.heroTitle.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];self.heroTitle.numberOfLines=2;
    self.heroVersion=[UILabel new];self.heroVersion.textColor=UIColor.secondaryLabelColor;self.heroVersion.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.status.textColor=UIColor.secondaryLabelColor;self.controllerHintLabel.textColor=UIColor.secondaryLabelColor;self.controllerHintLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.play=[self button:@"\u5F00\u59CB\u6E38\u620F" symbol:@"play.fill" action:@selector(playSelected)];
    UIButtonConfiguration *playStyle=[UIButtonConfiguration filledButtonConfiguration];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if(@available(iOS 26.0,*)) playStyle=[UIButtonConfiguration prominentGlassButtonConfiguration];
#endif
    playStyle.title=@"\u5F00\u59CB\u6E38\u620F";playStyle.image=[UIImage systemImageNamed:@"play.fill"];
    playStyle.imagePadding=9;playStyle.cornerStyle=UIButtonConfigurationCornerStyleLarge;
    playStyle.baseBackgroundColor=TTLibraryAccent16();
    playStyle.baseForegroundColor=[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle==UIUserInterfaceStyleDark?C(35,22,61):UIColor.whiteColor;
    }];
    self.play.configuration=playStyle;self.play.backgroundColor=UIColor.clearColor;
    self.gameSettings=[self button:@"\u672C\u6E38\u620F\u8BBE\u7F6E" symbol:@"slider.horizontal.3" action:@selector(settingsSelected)];
    self.appSettings=[self button:@"\u8BBE\u7F6E" symbol:@"gearshape" action:@selector(showSettings)];
    self.importButton=[self button:@"\u6DFB\u52A0\u6E38\u620F" symbol:@"plus" action:@selector(addGame)];
    self.appearanceButton=[self button:@"\u5916\u89C2" symbol:@"circle.lefthalf.filled" action:@selector(showAppearance)];
    self.grid.translatesAutoresizingMaskIntoConstraints=YES;self.grid.backgroundColor=UIColor.clearColor;
    [self.grid registerClass:TTBannerCard16.class forCellWithReuseIdentifier:@"card"];
    for(UIView *v in @[self.heroPanel,self.hero,self.emptyHeroIcon,self.brand,self.heroTitle,self.heroVersion,self.status,self.controllerHintLabel,self.grid,self.play,self.gameSettings,self.appSettings,self.importButton,self.appearanceButton]){v.translatesAutoresizingMaskIntoConstraints=YES;[self.view addSubview:v];}
    self.view.accessibilityIdentifier=@"tonton.library.ios16";
}
- (UIButton *)button:(NSString *)label symbol:(NSString *)symbol action:(SEL)action {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *c=[UIButtonConfiguration tintedButtonConfiguration];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 260000
    if(@available(iOS 26.0,*)) c=[UIButtonConfiguration glassButtonConfiguration];
#endif
    c.image=[UIImage systemImageNamed:symbol];c.imagePadding=8;c.cornerStyle=UIButtonConfigurationCornerStyleCapsule;b.configuration=c;b.accessibilityLabel=label;
    b.backgroundColor=UIColor.clearColor;b.tintColor=TTLibraryAccent16();b.layer.cornerRadius=22;[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return b;
}
- (void)showAppearance {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"\u5916\u89C2" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *labels=@[@"\u8DDF\u968F\u7CFB\u7EDF",@"\u6D45\u8272",@"\u6DF1\u8272"];
    for(NSInteger i=0;i<labels.count;i++)[sheet addAction:[UIAlertAction actionWithTitle:labels[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        [NSUserDefaults.standardUserDefaults setInteger:i forKey:@"TonTonLibraryAppearance"];
        self.overrideUserInterfaceStyle=TTLibraryStyle16();self.view.window.overrideUserInterfaceStyle=TTLibraryStyle16();[self.grid reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"\u53D6\u6D88" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView=self.appearanceButton;sheet.popoverPresentationController.sourceRect=self.appearanceButton.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated];self.view.window.overrideUserInterfaceStyle=TTLibraryStyle16(); }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect safe=UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets);
    CGFloat inset=CGRectGetWidth(safe)<390?14:22;
    CGFloat x=CGRectGetMinX(safe)+inset,y=CGRectGetMinY(safe)+8,w=MAX(1,CGRectGetWidth(safe)-2*inset);
    CGFloat h=MAX(1,CGRectGetHeight(safe)-16);
    self.brand.frame=CGRectMake(x,y,MAX(1,w-148),44);
    self.appearanceButton.frame=CGRectMake(x+w-144,y,44,44);
    self.appSettings.frame=CGRectMake(x+w-94,y,44,44);
    self.importButton.frame=CGRectMake(x+w-44,y,44,44);
    self.wideLayout=w>=610&&w>h*1.12;
    CGFloat top=y+58,heroH=self.wideLayout?MIN(210,h*0.37):MIN(w*9/16,MIN(238,h*0.30));
    self.heroPanel.frame=CGRectMake(x,top,w,heroH);
    self.heroPanel.hidden=!self.wideLayout;
    CGFloat heroW=self.wideLayout?MIN(w*0.50,heroH*16/9):w;
    self.hero.frame=CGRectMake(x,top,heroW,heroH);
    self.emptyHeroIcon.frame=CGRectMake(x+16,top+16,44,32);
    self.heroShade.hidden=self.wideLayout||!self.hero.image;
    self.heroShade.frame=self.hero.bounds;
    BOOL overlay=!self.wideLayout&&self.hero.image!=nil;
    self.heroTitle.textColor=overlay?UIColor.whiteColor:UIColor.labelColor;
    self.heroVersion.textColor=overlay?[UIColor colorWithWhite:1 alpha:0.84]:UIColor.secondaryLabelColor;
    if(self.wideLayout) {
        self.heroTitle.frame=CGRectMake(x+heroW+24,top+14,MAX(1,w-heroW-42),MAX(30,heroH-60));
        self.heroVersion.frame=CGRectMake(x+heroW+24,top+heroH-42,MAX(1,w-heroW-42),24);
    } else {
        self.heroTitle.frame=CGRectMake(x+14,MAX(top,top+heroH-81),MAX(1,w-28),56);
        self.heroVersion.frame=CGRectMake(x+14,top+heroH-25,MAX(1,w-28),20);
    }
    self.status.frame=CGRectMake(x,top+heroH+8,w,24);
    CGFloat gridY=top+heroH+36,footerY=y+h-50;
    self.grid.frame=CGRectMake(x,gridY,w,MAX(0,footerY-10-gridY));
    self.play.frame=CGRectMake(x,footerY,MAX(1,w-58),48);
    self.gameSettings.frame=CGRectMake(x+w-46,footerY+2,46,44);
    self.controllerHintLabel.hidden=YES;
    UICollectionViewFlowLayout *flow=(UICollectionViewFlowLayout *)self.grid.collectionViewLayout;
    UICollectionViewScrollDirection direction=self.wideLayout?UICollectionViewScrollDirectionHorizontal:UICollectionViewScrollDirectionVertical;
    if(flow.scrollDirection!=direction){flow.scrollDirection=direction;[flow invalidateLayout];}
    flow.minimumLineSpacing=14;flow.minimumInteritemSpacing=14;flow.sectionInset=UIEdgeInsetsMake(2,0,10,0);
}
- (CGSize)collectionView:(UICollectionView *)v layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)p {
    CGFloat area=MAX(1,v.bounds.size.width);
    NSInteger columns=MAX(1,MIN(4,(NSInteger)((area+14)/156)));
    CGFloat height=MAX(1,v.bounds.size.height-12);
    CGFloat width=self.wideLayout?MIN(280,MAX(1,(height-64)*16/9)):MAX(1,floor((area-14*(columns-1))/columns));
    return CGSizeMake(width,self.wideLayout?height:width*9/16+64);
}
- (void)updateControllerSelection {
    [super updateControllerSelection];
    BOOL empty=self.controllerIndex==NSNotFound||self.controllerIndex>=self.displayGames.count;
    self.emptyHeroIcon.hidden=!empty;
    NSString *action=empty?@"\u6DFB\u52A0\u6E38\u620F":@"\u5F00\u59CB\u6E38\u620F";
    if(![self.play.configuration.title isEqual:action]){
        UIButtonConfiguration *style=self.play.configuration;
        style.title=action;style.image=[UIImage systemImageNamed:empty?@"plus":@"play.fill"];
        self.play.configuration=style;self.play.accessibilityLabel=action;
    }
    if(empty){self.play.enabled=YES;self.gameSettings.enabled=NO;self.heroTitle.text=@"\u6DFB\u52A0\u4F60\u7684\u6E38\u620F";self.hero.image=nil;self.heroVersion.text=nil;[self.view setNeedsLayout];return;}
    NSDictionary *g=self.displayGames[self.controllerIndex];
    if(![self.heroTitle.text isEqual:g[@"name"]] || ![self.heroVersion.text isEqual:g[@"version"]] || !self.hero.image) {
        self.hero.image=coverForGame(g);self.heroTitle.text=g[@"name"];self.heroVersion.text=g[@"version"];
        [self.view setNeedsLayout];
    }
    self.play.enabled=[self.installed containsObject:bundleForGame(g)];self.gameSettings.enabled=![g[@"id"] hasPrefix:@"import:"];
}
- (void)collectionView:(UICollectionView *)v didSelectItemAtIndexPath:(NSIndexPath *)path {
    self.controllerIndex=path.item;self.controllerTitleID=self.displayGames[path.item][@"id"];[self updateControllerSelection];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,self.play);
}
- (void)activateControllerSelection:(NSIndexPath *)path {
    (void)path; [self playSelected];
}
- (UICollectionViewScrollPosition)controllerScrollPosition {
    return self.wideLayout?UICollectionViewScrollPositionCenteredHorizontally:UICollectionViewScrollPositionCenteredVertically;
}
- (void)playSelected {
    if(!self.displayGames.count){[self addGame];return;}
    if(self.controllerIndex==NSNotFound||self.controllerIndex>=self.displayGames.count)return;
    [super collectionView:self.grid didSelectItemAtIndexPath:[NSIndexPath indexPathForItem:self.controllerIndex inSection:0]];
}
- (void)settingsSelected {
    if(self.controllerIndex==NSNotFound||self.controllerIndex>=self.displayGames.count)return;
    NSDictionary *g=self.displayGames[self.controllerIndex];
    [self presentViewController:TonTonGameSettingsController(g[@"id"],g[@"name"]) animated:YES completion:nil];
}
- (void)pollMenuController {
    // The proven polling adapter handles MCON's missing value-change notifications.
    // Defer A to Play, while superclass navigation/X retain the saved per-game mapping.
    BOOL wasA=!self.menuInput.initialized || (self.menuInput.buttons&TTMenuOpen)!=0;
    [super pollMenuController];
    if(!wasA&&(self.menuInput.buttons&TTMenuOpen)&&self.view.window&&!self.presentedViewController)[self playSelected];
}
@end

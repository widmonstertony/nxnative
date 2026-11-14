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
        return traits.userInterfaceStyle==UIUserInterfaceStyleDark?C(255,240,214):C(70,49,22);
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
    UIVisualEffectView *blur=[[UIVisualEffectView alloc]initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    self.art=[UIImageView new];self.art.contentMode=UIViewContentModeScaleAspectFit;
    self.placeholder=[UILabel new];self.placeholder.textColor=UIColor.whiteColor;self.placeholder.numberOfLines=3;
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
- (void)layoutSubviews { self.backdrop.image=self.art.image;[self.contentView layoutIfNeeded]; }
- (void)setControllerFocused:(BOOL)focused {
    self.layer.borderWidth=0;self.caseView.layer.borderWidth=focused?3:0;
    self.caseView.layer.borderColor=TTLibraryAccent16().CGColor;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous];[self setControllerFocused:self.controllerFocused]; }
@end

@interface TTLibrary16 : LibraryView
@property(nonatomic,strong) UILabel *brand,*heroTitle,*heroVersion;
@property(nonatomic,strong) UIImageView *hero;
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
    self.brand.textColor=UIColor.labelColor;self.brand.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    self.hero=[UIImageView new];self.hero.contentMode=UIViewContentModeScaleAspectFit;self.hero.clipsToBounds=YES;self.hero.layer.cornerRadius=18;self.hero.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    self.heroTitle=[UILabel new];self.heroTitle.textColor=UIColor.labelColor;self.heroTitle.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];self.heroTitle.numberOfLines=2;
    self.heroVersion=[UILabel new];self.heroVersion.textColor=UIColor.secondaryLabelColor;self.heroVersion.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.status.textColor=UIColor.secondaryLabelColor;self.controllerHintLabel.textColor=UIColor.secondaryLabelColor;self.controllerHintLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.play=[self button:@"\u5F00\u59CB\u6E38\u620F" symbol:@"play.fill" action:@selector(playSelected)];
    self.play.backgroundColor=C(255,240,214);self.play.tintColor=UIColor.blackColor;
    self.gameSettings=[self button:@"\u672C\u6E38\u620F\u8BBE\u7F6E" symbol:@"slider.horizontal.3" action:@selector(settingsSelected)];
    self.appSettings=[self button:@"\u8BBE\u7F6E" symbol:@"gearshape" action:@selector(showSettings)];
    self.importButton=[self button:@"\u6DFB\u52A0\u6E38\u620F" symbol:@"plus" action:@selector(addGame)];
    self.appearanceButton=[self button:@"\u5916\u89C2" symbol:@"circle.lefthalf.filled" action:@selector(showAppearance)];
    self.grid.translatesAutoresizingMaskIntoConstraints=YES;self.grid.backgroundColor=UIColor.clearColor;
    [self.grid registerClass:TTBannerCard16.class forCellWithReuseIdentifier:@"card"];
    for(UIView *v in @[self.hero,self.brand,self.heroTitle,self.heroVersion,self.status,self.controllerHintLabel,self.grid,self.play,self.gameSettings,self.appSettings,self.importButton,self.appearanceButton]){v.translatesAutoresizingMaskIntoConstraints=YES;[self.view addSubview:v];}
    self.view.accessibilityIdentifier=@"tonton.library.ios16";
}
- (UIButton *)button:(NSString *)label symbol:(NSString *)symbol action:(SEL)action {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *c=[UIButtonConfiguration plainButtonConfiguration];c.image=[UIImage systemImageNamed:symbol];c.imagePadding=8;c.cornerStyle=UIButtonConfigurationCornerStyleCapsule;b.configuration=c;b.accessibilityLabel=label;
    b.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;b.tintColor=TTLibraryAccent16();b.layer.cornerRadius=22;[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return b;
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
    [super viewDidLayoutSubviews];CGRect bounds=UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets);
    CGFloat x=bounds.origin.x+20,y=bounds.origin.y+8,w=MAX(1,bounds.size.width-40),h=MAX(1,bounds.size.height-16);
    BOOL wide=w>h*1.2;CGFloat top=50,bottom=64;
    self.brand.frame=CGRectMake(x,y,MAX(1,w-172),40);self.appearanceButton.frame=CGRectMake(x+w-148,y,44,44);self.appSettings.frame=CGRectMake(x+w-96,y,44,44);self.importButton.frame=CGRectMake(x+w-44,y,44,44);
    CGFloat heroH=wide?MIN(170,h*0.44):MIN(210,h*0.28),heroW=MIN(w*0.45,heroH*16/9);
    self.hero.frame=CGRectMake(x,y+top,heroW,heroH);
    self.heroTitle.frame=CGRectMake(x+heroW+18,y+top+12,MAX(1,w-heroW-18),MAX(44,heroH-52));
    self.heroVersion.frame=CGRectMake(x+heroW+18,y+top+heroH-34,MAX(1,w-heroW-18),24);
    self.status.frame=CGRectMake(x,y+top+heroH+10,w,22);
    CGFloat gridY=y+top+heroH+38;self.grid.frame=CGRectMake(x,gridY,w,MAX(60,y+h-bottom-gridY));
    self.play.frame=CGRectMake(x,y+h-50,MAX(120,w-116),44);self.gameSettings.frame=CGRectMake(x+w-104,y+h-50,44,44);
    self.controllerHintLabel.frame=CGRectMake(x,y+h-6,w,20);self.controllerHintLabel.hidden=YES;
    [self.play setTitle:@"\u5F00\u59CB\u6E38\u620F" forState:UIControlStateNormal];
    UICollectionViewFlowLayout *flow=(UICollectionViewFlowLayout *)self.grid.collectionViewLayout;
    UICollectionViewScrollDirection direction=wide?UICollectionViewScrollDirectionHorizontal:UICollectionViewScrollDirectionVertical;
    if(flow.scrollDirection!=direction){flow.scrollDirection=direction;[flow invalidateLayout];}
    flow.minimumLineSpacing=18;flow.minimumInteritemSpacing=16;flow.sectionInset=UIEdgeInsetsMake(4,0,12,0);
}
- (CGSize)collectionView:(UICollectionView *)v layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)p {
    BOOL wide=self.view.bounds.size.width>self.view.bounds.size.height*1.2;
    CGFloat width=wide?MIN(300,MAX(130,(v.bounds.size.height-64)*16/9)):floor((v.bounds.size.width-16*(MAX(2,(NSInteger)(v.bounds.size.width/240))-1))/MAX(2,(NSInteger)(v.bounds.size.width/240)));
    return CGSizeMake(width,width*9/16+64);
}
- (void)updateControllerSelection {
    [super updateControllerSelection];
    if(self.controllerIndex==NSNotFound||self.controllerIndex>=self.displayGames.count){self.play.enabled=NO;self.gameSettings.enabled=NO;self.heroTitle.text=@"\u6DFB\u52A0\u4F60\u7684\u6E38\u620F";self.hero.image=nil;return;}
    NSDictionary *g=self.displayGames[self.controllerIndex];self.hero.image=coverForGame(g);self.heroTitle.text=g[@"name"];self.heroVersion.text=g[@"version"];
    self.play.enabled=[self.installed containsObject:bundleForGame(g)];self.gameSettings.enabled=![g[@"id"] hasPrefix:@"import:"];
}
- (void)collectionView:(UICollectionView *)v didSelectItemAtIndexPath:(NSIndexPath *)path {
    self.controllerIndex=path.item;self.controllerTitleID=self.displayGames[path.item][@"id"];[self updateControllerSelection];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,self.play);
}
- (void)playSelected {
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

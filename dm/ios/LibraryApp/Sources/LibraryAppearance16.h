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
        return traits.userInterfaceStyle==UIUserInterfaceStyleDark?C(250,228,181):C(98,58,25);
    }];
}

static UIColor *TTShelfBackground(void) { return D(249,247,242,19,20,22); }
static UIColor *TTShelfReady(void) { return D(40,106,71,159,222,175); }
static UIColor *TTShelfWait(void) { return D(130,78,24,255,213,153); }

static UILabel *TTShelfLabel(UIFontTextStyle style, CGFloat size, UIFontWeight weight) {
    UILabel *label=[UILabel new];
    label.font=[[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]
                                                      maximumPointSize:size*1.45];
    label.adjustsFontForContentSizeCategory=YES;
    label.textColor=UIColor.labelColor;
    return label;
}

@interface TTBannerCard16 : CoverCard
@property(nonatomic,strong) UIView *selectionLine;
@end
@implementation TTBannerCard16
- (void)layoutSubviews {
    // The banner owns its own rounded rectangular mask; the old cartridge
    // view's outline should never clip the artwork.
    [super layoutSubviews];
    self.caseView.layer.mask=nil;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame]))return nil;
    for(UIView *view in self.contentView.subviews.copy)[view removeFromSuperview];
    self.caseView=[UIView new];self.caseView.layer.cornerRadius=16;self.caseView.clipsToBounds=YES;
    self.caseView.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    self.art=[UIImageView new];self.art.contentMode=UIViewContentModeScaleAspectFill;self.art.clipsToBounds=YES;
    self.art.layer.minificationFilter=kCAFilterTrilinear;
    self.placeholder=[UILabel new];self.placeholder.textColor=UIColor.labelColor;self.placeholder.numberOfLines=3;
    self.placeholder.textAlignment=NSTextAlignmentCenter;self.placeholder.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.title=TTShelfLabel(UIFontTextStyleSubheadline,14,UIFontWeightSemibold);self.title.numberOfLines=1;
    self.sizeLabel=TTShelfLabel(UIFontTextStyleCaption2,11,UIFontWeightMedium);self.sizeLabel.textColor=UIColor.secondaryLabelColor;
    self.selectionLine=[UIView new];self.selectionLine.layer.cornerRadius=1;self.selectionLine.backgroundColor=TTLibraryAccent16();
    self.selectionLine.hidden=YES;
    self.badge=[UILabel new];self.badge.textAlignment=NSTextAlignmentCenter;self.badge.font=[UIFont boldSystemFontOfSize:15];self.badge.layer.cornerRadius=14;self.badge.clipsToBounds=YES;
    for(UIView *v in @[self.caseView,self.title,self.sizeLabel,self.selectionLine]){v.translatesAutoresizingMaskIntoConstraints=NO;[self.contentView addSubview:v];}
    for(UIView *v in @[self.art,self.placeholder,self.badge]){v.translatesAutoresizingMaskIntoConstraints=NO;[self.caseView addSubview:v];}
    NSMutableArray *constraints=[NSMutableArray array];
    [constraints addObjectsFromArray:@[[self.art.topAnchor constraintEqualToAnchor:self.caseView.topAnchor],[self.art.bottomAnchor constraintEqualToAnchor:self.caseView.bottomAnchor],[self.art.leadingAnchor constraintEqualToAnchor:self.caseView.leadingAnchor],[self.art.trailingAnchor constraintEqualToAnchor:self.caseView.trailingAnchor]]];
    [constraints addObjectsFromArray:@[[self.caseView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],[self.caseView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],[self.caseView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],[self.caseView.heightAnchor constraintEqualToAnchor:self.caseView.widthAnchor multiplier:9.0/16.0],
        [self.title.topAnchor constraintEqualToAnchor:self.caseView.bottomAnchor constant:8],[self.title.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],[self.title.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.sizeLabel.topAnchor constraintEqualToAnchor:self.title.bottomAnchor constant:3],[self.sizeLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],[self.sizeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.placeholder.centerYAnchor constraintEqualToAnchor:self.caseView.centerYAnchor],[self.placeholder.leadingAnchor constraintEqualToAnchor:self.caseView.leadingAnchor constant:12],[self.placeholder.trailingAnchor constraintEqualToAnchor:self.caseView.trailingAnchor constant:-12],
        [self.selectionLine.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],[self.selectionLine.widthAnchor constraintEqualToConstant:24],
        [self.selectionLine.topAnchor constraintEqualToAnchor:self.sizeLabel.bottomAnchor constant:6],[self.selectionLine.heightAnchor constraintEqualToConstant:2],
        [self.badge.trailingAnchor constraintEqualToAnchor:self.caseView.trailingAnchor constant:-10],[self.badge.bottomAnchor constraintEqualToAnchor:self.caseView.bottomAnchor constant:-10],[self.badge.widthAnchor constraintEqualToConstant:28],[self.badge.heightAnchor constraintEqualToConstant:28]]];
    [NSLayoutConstraint activateConstraints:constraints];return self;
}
- (void)applyLibrarySelection:(BOOL)selected {
    UIAccessibilityTraits traits=UIAccessibilityTraitButton|(selected?UIAccessibilityTraitSelected:0);
    if(self.selectionLine.hidden==(!selected)&&self.accessibilityTraits==traits)return;
    self.selectionLine.hidden=!selected;
    self.accessibilityTraits=traits;
    self.title.textColor=selected?TTLibraryAccent16():UIColor.labelColor;
}
- (void)setControllerFocused:(BOOL)focused {
    [super setControllerFocused:focused];
    self.title.textColor=(focused||!self.selectionLine.hidden)?TTLibraryAccent16():UIColor.labelColor;
    self.layer.borderWidth=0;self.caseView.layer.borderWidth=focused?3:0;
    self.caseView.layer.borderColor=TTLibraryAccent16().CGColor;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous { [super traitCollectionDidChange:previous];[self setControllerFocused:self.controllerFocused]; }
@end

@interface TTLibrary16 : LibraryView
@property(nonatomic,strong) UILabel *brand,*heroTitle,*heroVersion,*heroAvailability,*shelfHeading;
@property(nonatomic,strong) UIImageView *hero,*brandIcon,*emptyHeroIcon;
@property(nonatomic,strong) UIView *heroPanel,*footer;
@property(nonatomic,strong) CAGradientLayer *heroShade,*heroTopShade,*heroEdge,*footerShade;
@property(nonatomic) BOOL wideLayout;
@property(nonatomic,strong) UIButton *play,*gameSettings,*appSettings,*importButton,*appearanceButton;
@property(nonatomic,copy) NSString *paintedGame;
@property(nonatomic,copy) NSString *paintedVersion;
@property(nonatomic,strong) NSArray *paintedCatalogue;
@property(nonatomic) BOOL choseInitialGame;
@end
@implementation TTLibrary16
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {return UIInterfaceOrientationMaskAllButUpsideDown;}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle=TTLibraryStyle16();
    [NSLayoutConstraint deactivateConstraints:self.view.constraints];
    for(UIView *view in self.view.subviews.copy)[view removeFromSuperview];
    self.view.backgroundColor=TTShelfBackground();
    self.heroPanel=[UIView new];self.heroPanel.clipsToBounds=YES;self.heroPanel.userInteractionEnabled=NO;
    self.hero=[UIImageView new];self.hero.contentMode=UIViewContentModeScaleAspectFill;self.hero.clipsToBounds=YES;
    self.hero.layer.minificationFilter=kCAFilterTrilinear;
    [self.heroPanel addSubview:self.hero];
    self.heroShade=[CAGradientLayer layer];self.heroTopShade=[CAGradientLayer layer];self.heroEdge=[CAGradientLayer layer];
    for(CAGradientLayer *shade in @[self.heroShade,self.heroTopShade,self.heroEdge])[self.heroPanel.layer addSublayer:shade];
    self.emptyHeroIcon=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"gamecontroller"]];
    self.emptyHeroIcon.contentMode=UIViewContentModeScaleAspectFit;
    [self.heroPanel addSubview:self.emptyHeroIcon];

    self.brandIcon=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"gamecontroller.fill"]];
    self.brandIcon.contentMode=UIViewContentModeScaleAspectFit;
    self.brand=TTShelfLabel(UIFontTextStyleHeadline,16,UIFontWeightBold);self.brand.text=@"TonTon \u6E38\u620F\u5323";
    self.brand.adjustsFontSizeToFitWidth=YES;self.brand.minimumScaleFactor=0.75;
    self.heroTitle=TTShelfLabel(UIFontTextStyleLargeTitle,38,UIFontWeightHeavy);self.heroTitle.numberOfLines=2;
    self.heroTitle.adjustsFontSizeToFitWidth=YES;self.heroTitle.minimumScaleFactor=0.62;
    self.heroTitle.accessibilityTraits=UIAccessibilityTraitHeader;
    self.heroVersion=TTShelfLabel(UIFontTextStyleSubheadline,14,UIFontWeightMedium);self.heroVersion.textColor=UIColor.secondaryLabelColor;
    self.heroAvailability=TTShelfLabel(UIFontTextStyleCaption1,13,UIFontWeightBold);
    self.shelfHeading=TTShelfLabel(UIFontTextStyleTitle2,22,UIFontWeightBold);self.shelfHeading.text=@"\u6211\u7684\u6E38\u620F";
    self.shelfHeading.accessibilityTraits=UIAccessibilityTraitHeader;
    self.status.textColor=UIColor.secondaryLabelColor;self.status.textAlignment=NSTextAlignmentRight;
    self.status.adjustsFontSizeToFitWidth=YES;self.status.minimumScaleFactor=0.67;
    self.controllerHintLabel.hidden=YES;

    self.play=[self button:@"\u5F00\u59CB\u6E38\u620F" symbol:@"play.fill" action:@selector(playSelected)];
    UIButtonConfiguration *playStyle=[UIButtonConfiguration filledButtonConfiguration];
#if __IPHONE_OS_VERS_MAX_ALLOWED >= 260000
    if(@available(iOS 26.0,*))playStyle=[UIButtonConfiguration prominentGlassButtonConfiguration];
#endif
    playStyle.cornerStyle=UIButtonConfigurationCornerStyleCapsule;
    // The system's vivid glass material sometimes lightens its tint.
    // Keep a dark label over this light action in both appearance modes.
    playStyle.baseBackgroundColor=C(255,231,183);playStyle.baseForegroundColor=C(43,29,16);
    playStyle.imagePadding=9;self.play.configuration=playStyle;
    self.gameSettings=[self button:@"\u672C\u6E38\u620F\u8BBE\u7F6E" symbol:@"slider.horizontal.3" action:@selector(settingsSelected)];
    self.appSettings=[self button:@"\u8BBE\u7F6E" symbol:@"gearshape" action:@selector(showSettings)];
    self.importButton=[self button:@"\u6DFB\u52A0\u6E38\u620F" symbol:@"plus" action:@selector(addGame)];
    self.appearanceButton=[self button:@"\u5916\u89C2" symbol:@"circle.lefthalf.filled" action:@selector(showAppearance)];
    self.grid.translatesAutoresizingMaskIntoConstraints=YES;self.grid.backgroundColor=UIColor.clearColor;
    self.grid.alwaysBounceVertical=NO;self.grid.showsVerticalScrollIndicator=NO;
    [self.grid registerClass:TTBannerCard16.class forCellWithReuseIdentifier:@"card"];

    self.footer=[UIView new];self.footer.userInteractionEnabled=NO;
    self.footerShade=[CAGradientLayer layer];[self.footer.layer addSublayer:self.footerShade];
    for(UIView *view in @[self.heroPanel,self.brandIcon,self.brand,self.heroAvailability,self.heroTitle,self.heroVersion,
                          self.shelfHeading,self.status,self.grid,self.footer,self.play,self.gameSettings,
                          self.appSettings,self.importButton,self.appearanceButton]){
        view.translatesAutoresizingMaskIntoConstraints=YES;[self.view addSubview:view];
    }
    self.view.accessibilityIdentifier=@"tonton.library.shelf";
    [self refreshPalette];
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
- (void)refreshPalette {
    UIColor *background=[TTShelfBackground() resolvedColorWithTraitCollection:self.traitCollection];
    BOOL dark=self.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    BOOL art=self.hero.image!=nil;
    self.heroPanel.backgroundColor=background;
    self.heroShade.colors=@[(id)[background colorWithAlphaComponent:0].CGColor,
        (id)[background colorWithAlphaComponent:0.13].CGColor,(id)[background colorWithAlphaComponent:0.79].CGColor,(id)background.CGColor];
    self.heroShade.locations=dark?@[@0,@0.39,@0.72,@0.98]:@[@0,@0.37,@0.70,@0.97];
    self.heroTopShade.colors=@[(id)[UIColor colorWithWhite:0 alpha:0.70].CGColor,
                               (id)[UIColor colorWithWhite:0 alpha:0.36].CGColor,
                               (id)[UIColor colorWithWhite:0 alpha:0].CGColor];
    self.heroTopShade.locations=@[@0,@0.5,@1];
    self.heroTopShade.hidden=!art;
    self.heroEdge.startPoint=CGPointMake(0,0.5);self.heroEdge.endPoint=CGPointMake(1,0.5);
    self.heroEdge.colors=@[(id)[background colorWithAlphaComponent:0].CGColor,(id)background.CGColor];
    self.heroEdge.locations=@[@0.66,@1];self.heroEdge.hidden=!self.wideLayout;
    self.footerShade.colors=@[(id)[background colorWithAlphaComponent:0].CGColor,(id)background.CGColor,(id)background.CGColor];
    self.footerShade.locations=@[@0,@0.32,@1];
    self.brand.textColor=art?UIColor.whiteColor:UIColor.labelColor;
    self.brandIcon.tintColor=art?UIColor.whiteColor:TTLibraryAccent16();
    self.emptyHeroIcon.hidden=art;
    self.emptyHeroIcon.tintColor=[TTLibraryAccent16() colorWithAlphaComponent:dark?0.20:0.16];
    for(UIButton *button in @[self.appearanceButton,self.appSettings,self.importButton]){
        UIColor *ink=art?UIColor.whiteColor:UIColor.labelColor;
        if([button.configuration.baseForegroundColor isEqual:ink])continue;
        UIButtonConfiguration *configuration=button.configuration;
        configuration.baseForegroundColor=ink;button.configuration=configuration;
    }
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];[self refreshPalette];[self.view setNeedsLayout];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds=self.view.bounds,safe=UIEdgeInsetsInsetRect(bounds,self.view.safeAreaInsets);
    CGFloat margin=safe.size.width<380?19:23;
    CGFloat x=safe.origin.x+margin,y=safe.origin.y;
    CGFloat right=CGRectGetMaxX(safe)-margin,bottom=CGRectGetMaxY(safe);
    CGFloat w=MAX(1,right-x),h=MAX(1,safe.size.height);
    self.wideLayout=w>h*1.14&&w>=570;
    CGFloat heroRight=self.wideLayout?CGRectGetMidX(safe)+14:bounds.size.width;
    CGFloat heroBottom=self.wideLayout?bounds.size.height:MIN(bottom-274,y+MAX(228,MIN(380,h*0.47)));
    CGFloat shelfX=self.wideLayout?CGRectGetMidX(safe)+24:x;
    CGFloat shelfY=self.wideLayout?y+75:MAX(y+190,heroBottom-4);
    CGFloat headerH=44,headerY=y+5;
    self.heroPanel.frame=CGRectMake(0,0,heroRight,MAX(1,heroBottom));
    self.hero.frame=self.heroPanel.bounds;
    CGFloat iconW=MIN(150,heroRight*0.41);
    self.emptyHeroIcon.frame=CGRectMake(MAX(x,heroRight-margin-iconW-18),MAX(headerY+54,heroBottom*0.27),iconW,iconW*0.60);
    [CATransaction begin];[CATransaction setDisableActions:YES];
    self.heroShade.frame=self.heroPanel.bounds;self.heroEdge.frame=self.heroPanel.bounds;
    self.heroTopShade.frame=CGRectMake(0,0,heroRight,headerY+headerH+66);
    [CATransaction commit];
    self.brandIcon.frame=CGRectMake(x,headerY+12,22,20);
    CGFloat toolbarEnd=self.wideLayout?heroRight-19:right;
    self.brand.frame=CGRectMake(x+30,headerY,MAX(1,toolbarEnd-x-186),headerH);
    self.appearanceButton.frame=CGRectMake(toolbarEnd-144,headerY,44,44);
    self.appSettings.frame=CGRectMake(toolbarEnd-94,headerY,44,44);
    self.importButton.frame=CGRectMake(toolbarEnd-44,headerY,44,44);
    CGFloat detailsW=MAX(1,(self.wideLayout?heroRight-38:right)-x);
    CGFloat footerY=bottom-60;
    CGFloat metaY=self.wideLayout?footerY-36:shelfY-37;
    CGFloat titleHeight=MIN(self.wideLayout?h*0.36:109,MAX(54,self.heroTitle.font.lineHeight*2));
    CGRect fit=[self.heroTitle textRectForBounds:CGRectMake(0,0,detailsW,titleHeight) limitedToNumberOfLines:2];
    CGFloat usedTitleHeight=MIN(titleHeight,MAX(41,ceil(fit.size.height)+3));
    self.heroVersion.frame=CGRectMake(x,metaY,detailsW,23);
    self.heroTitle.frame=CGRectMake(x,metaY-usedTitleHeight-4,detailsW,usedTitleHeight);
    self.heroAvailability.frame=CGRectMake(x,CGRectGetMinY(self.heroTitle.frame)-28,detailsW,23);
    self.shelfHeading.frame=CGRectMake(shelfX,shelfY,MAX(1,(right-shelfX)*0.40),33);
    self.status.frame=CGRectMake(shelfX+(right-shelfX)*0.40,shelfY+5,MAX(1,(right-shelfX)*0.60),25);
    CGFloat gridY=shelfY+40;
    self.grid.frame=CGRectMake(shelfX,gridY,MAX(1,right-shelfX),MAX(1,(self.wideLayout?bottom:footerY-4)-gridY));
    CGFloat footerWidth=self.wideLayout?heroRight:bounds.size.width;
    self.footer.frame=CGRectMake(0,footerY-22,footerWidth,bounds.size.height-footerY+22);
    [CATransaction begin];[CATransaction setDisableActions:YES];self.footerShade.frame=self.footer.bounds;[CATransaction commit];
    self.play.frame=CGRectMake(x,footerY,MAX(1,detailsW-64),51);
    self.gameSettings.frame=CGRectMake(x+detailsW-51,footerY,51,51);
    UICollectionViewFlowLayout *flow=(UICollectionViewFlowLayout *)self.grid.collectionViewLayout;
    flow.scrollDirection=UICollectionViewScrollDirectionVertical;
    self.grid.alwaysBounceHorizontal=NO;
    self.grid.alwaysBounceVertical=YES;
    flow.minimumLineSpacing=15;flow.minimumInteritemSpacing=12;flow.sectionInset=UIEdgeInsetsMake(0,0,0,0);
    if(!CGSizeEqualToSize(self.lastGridSize,self.grid.bounds.size)){
        self.lastGridSize=self.grid.bounds.size;[flow invalidateLayout];
    }
    [self refreshPalette];
}
- (CGSize)collectionView:(UICollectionView *)view layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)path {
    CGFloat area=MAX(1,view.bounds.size.width);
    (void)layout;(void)path;
    NSInteger columns=MAX(1,MIN(4,(NSInteger)((area+12)/156)));
    CGFloat width=floor((area-12*(columns-1))/columns);
    return CGSizeMake(width,width*9/16+64);
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)view cellForItemAtIndexPath:(NSIndexPath *)path {
    TTBannerCard16 *card=(TTBannerCard16 *)[super collectionView:view cellForItemAtIndexPath:path];
    card.badge.hidden=YES;card.art.backgroundColor=UIColor.clearColor;
    card.accessibilityLabel=card.title.text;card.isAccessibilityElement=YES;
    [card applyLibrarySelection:path.item==self.controllerIndex];
    return card;
}
- (void)updateControllerSelection {
    [super updateControllerSelection];
    if(!self.play)return;
    NSArray *catalogue=self.displayGames;
    if(!self.choseInitialGame&&catalogue.count){
        NSUInteger fallback=NSNotFound;
        for(NSUInteger i=0;i<catalogue.count;i++){
            NSDictionary *entry=catalogue[i];
            if(!coverForGame(entry))continue;
            if(fallback==NSNotFound)fallback=i;
            if([self.installed containsObject:bundleForGame(entry)]){fallback=i;break;}
        }
        if(fallback!=NSNotFound){
            self.controllerIndex=fallback;self.controllerTitleID=catalogue[fallback][@"id"];
            [super updateControllerSelection];
            [self.grid setNeedsLayout];
            NSString *chosen=self.controllerTitleID;
            dispatch_async(dispatch_get_main_queue(), ^{
                if([self.controllerTitleID isEqual:chosen]&&self.controllerIndex<[self.grid numberOfItemsInSection:0])
                    [self.grid scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:self.controllerIndex inSection:0]
                                     atScrollPosition:self.controllerScrollPosition animated:NO];
            });
        }
        self.choseInitialGame=YES;
    }
    BOOL empty=self.controllerIndex==NSNotFound||self.controllerIndex>=catalogue.count;
    for(NSIndexPath *path in self.grid.indexPathsForVisibleItems){
        id cell=[self.grid cellForItemAtIndexPath:path];
        if([cell isKindOfClass:TTBannerCard16.class])[cell applyLibrarySelection:path.item==self.controllerIndex];
    }
    NSDictionary *game=empty?nil:self.displayGames[self.controllerIndex];
    BOOL ready=game&&[self.installed containsObject:bundleForGame(game)];
    NSString *action=empty?@"\u6DFB\u52A0\u6E38\u620F":ready?@"\u5F00\u59CB\u6E38\u620F":@"\u5C1A\u672A\u5C31\u7EEA";
    if(![self.play.configuration.title isEqual:action]){
        UIButtonConfiguration *style=self.play.configuration;
        style.title=action;style.image=[UIImage systemImageNamed:empty?@"plus":ready?@"play.fill":@"hourglass"];
        self.play.configuration=style;self.play.accessibilityLabel=action;
    }
    self.play.enabled=empty||ready;
    self.gameSettings.enabled=!empty&&![game[@"id"] hasPrefix:@"import:"];
    self.heroAvailability.text=empty?nil:ready?@"\u25CF  \u53EF\u5F00\u59CB":@"\u25CB  \u51C6\u5907\u4E2D";
    self.heroAvailability.textColor=ready?TTShelfReady():TTShelfWait();
    NSString *idValue=game[@"id"]?:@"";
    NSString *version=game[@"version"]?:@"";
    if(![self.paintedGame isEqual:idValue]||![self.paintedVersion isEqual:version]||self.paintedCatalogue!=catalogue){
        BOOL animate=self.paintedGame!=nil&&![self.paintedGame isEqual:idValue]&&!UIAccessibilityIsReduceMotionEnabled()&&self.view.window;
        self.paintedGame=idValue;self.paintedVersion=version;self.paintedCatalogue=catalogue;
        UIImage *image=game?(TTLibraryPreferredArtwork(idValue,YES) ?: coverForGame(game)):nil;
        void (^change)(void)=^{self.hero.image=image;};
        if(animate)[UIView transitionWithView:self.hero duration:0.20 options:UIViewAnimationOptionTransitionCrossDissolve|UIViewAnimationOptionBeginFromCurrentState animations:change completion:nil];
        else change();
        self.heroTitle.text=game[@"name"]?:@"\u6DFB\u52A0\u4F60\u7684\u6E38\u620F";
        NSString *size=game[@"size"]?:@"";
        self.heroVersion.text=empty?@"\u4ECE\u6587\u4EF6\u6DFB\u52A0\u4F60\u7684\u7B2C\u4E00\u6B3E\u6E38\u620F":version.length&&size.length?[NSString stringWithFormat:@"%@  \u00B7  %@",version,size]:version.length?version:size;
        [self.view setNeedsLayout];
    }
}
- (void)collectionView:(UICollectionView *)view didSelectItemAtIndexPath:(NSIndexPath *)path {
    self.controllerIndex=path.item;self.controllerTitleID=self.displayGames[path.item][@"id"];[self updateControllerSelection];
    if(UIAccessibilityIsVoiceOverRunning())UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,self.play);
}
- (void)activateControllerSelection:(NSIndexPath *)path {
    (void)path; [self playSelected];
}
- (UICollectionViewScrollPosition)controllerScrollPosition {
    return UICollectionViewScrollPositionCenteredVertically;
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
@end

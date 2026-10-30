#import <UIKit/UIKit.h>
#import "GameOpen.h"
static UIColor *C(int r,int g,int b){return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1];}
static UIColor *D(int lr,int lg,int lb,int dr,int dg,int db){return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t){return t.userInterfaceStyle==UIUserInterfaceStyleDark?C(dr,dg,db):C(lr,lg,lb);}];}
static void excludeGameResourcesFromBackup(void){
    NSString *doc=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString *root=[doc stringByAppendingPathComponent:@"Games"];
    NSFileManager *fm=NSFileManager.defaultManager;
    for(NSString *name in [fm contentsOfDirectoryAtPath:root error:nil]){
        if([name hasPrefix:@"."])continue;
        NSURL *resources=[NSURL fileURLWithPath:[[root stringByAppendingPathComponent:name] stringByAppendingPathComponent:@"Resources"] isDirectory:YES];
        if([fm fileExistsAtPath:resources.path]) [resources setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    }
}
static NSArray<NSDictionary *> *games(void){return @[
@{@"name":@"GTA V",@"id":@"gta5",@"bundle":@"io.github.playgta5ios.app",@"size":@"约 42.2 GB",@"version":@"Port 1.5.2"},
@{@"name":@"极品飞车：热力追踪",@"id":@"010029b0118e8000",@"size":@"7.53 GB",@"version":@"更新 1.0.3"},
@{@"name":@"集合啦！动物森友会",@"id":@"01006f8002326000",@"size":@"10.42 GB",@"version":@"更新 3.0.3 · 3 DLC"},
@{@"name":@"宝可梦铁拳 DX",@"id":@"0100b3f000be2000",@"size":@"3.67 GB",@"version":@"版本 1.3.3"},
@{@"name":@"魔法使之夜",@"id":@"0100751018dba000",@"size":@"21.32 GB",@"version":@"更新 1.0.3"},
@{@"name":@"宝可梦传说：阿尔宙斯",@"id":@"01001f5010dfa000",@"size":@"6.42 GB",@"version":@"更新 1.1.1"},
@{@"name":@"宝可梦传说：Z-A",@"id":@"0100f43008c44000",@"size":@"5.99 GB",@"version":@"更新 2.0.2"},
@{@"name":@"巫师 3",@"id":@"0100e67012924000",@"size":@"21.42 GB",@"version":@"更新 4.04b"}];}
static NSString *bundleForGame(NSDictionary *g){return g[@"bundle"] ?: [@"org.nxnative." stringByAppendingString:g[@"id"]];}
@interface CoverCard:UICollectionViewCell
@property(nonatomic,strong)UIView *caseView,*spine,*coverFrame,*shine,*tab,*labelBand,*leftRib,*rightRib;
@property(nonatomic,strong)UIImageView *art;
@property(nonatomic,strong)UILabel *title,*sizeLabel,*badge,*caseMark,*contacts,*bandText;
@property(nonatomic,strong)CAShapeLayer *shellMask,*shellEdge;
@end
@implementation CoverCard
- (instancetype)initWithFrame:(CGRect)f{if(!(self=[super initWithFrame:f]))return nil;
self.contentView.backgroundColor=UIColor.clearColor;
_caseView=[UIView new];_caseView.backgroundColor=C(30,34,39);_caseView.layer.masksToBounds=YES;
_shellMask=[CAShapeLayer layer];_caseView.layer.mask=_shellMask;
_shellEdge=[CAShapeLayer layer];_shellEdge.fillColor=UIColor.clearColor.CGColor;_shellEdge.strokeColor=C(96,103,111).CGColor;_shellEdge.lineWidth=2;[_caseView.layer addSublayer:_shellEdge];
_spine=[UIView new];_spine.backgroundColor=C(19,22,26);_spine.layer.cornerRadius=2;
_leftRib=[UIView new];_leftRib.backgroundColor=C(68,73,79);
_rightRib=[UIView new];_rightRib.backgroundColor=C(13,16,19);
_tab=[UIView new];_tab.backgroundColor=C(78,84,90);_tab.layer.cornerRadius=3;
_coverFrame=[UIView new];_coverFrame.backgroundColor=C(8,11,15);_coverFrame.layer.cornerRadius=10;_coverFrame.layer.masksToBounds=YES;
_labelBand=[UIView new];_labelBand.backgroundColor=C(227,44,49);
_bandText=[UILabel new];_bandText.text=@"TONTON  /  GAME CARD";_bandText.textColor=UIColor.whiteColor;_bandText.font=[UIFont systemFontOfSize:9 weight:UIFontWeightHeavy];_bandText.adjustsFontSizeToFitWidth=YES;
_art=[UIImageView new];_art.contentMode=UIViewContentModeScaleAspectFill;_art.backgroundColor=UIColor.tertiarySystemBackgroundColor;_art.clipsToBounds=YES;
_shine=[UIView new];_shine.backgroundColor=[UIColor colorWithWhite:1 alpha:0.08];_shine.transform=CGAffineTransformMakeRotation(-0.35);
_caseMark=[UILabel new];_caseMark.text=@"TTG  •  GAME CARD";_caseMark.textColor=C(155,162,171);_caseMark.font=[UIFont systemFontOfSize:8 weight:UIFontWeightBold];_caseMark.adjustsFontSizeToFitWidth=YES;
_contacts=[UILabel new];_contacts.text=@"▮ ▮ ▮ ▮";_contacts.textColor=C(202,165,83);_contacts.font=[UIFont systemFontOfSize:8 weight:UIFontWeightHeavy];
_title=[UILabel new];_title.font=[UIFont systemFontOfSize:15 weight:UIFontWeightBold];_title.textColor=UIColor.labelColor;_title.textAlignment=NSTextAlignmentLeft;_title.numberOfLines=2;
_sizeLabel=[UILabel new];_sizeLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightMedium];_sizeLabel.textColor=UIColor.secondaryLabelColor;_sizeLabel.adjustsFontSizeToFitWidth=YES;_sizeLabel.minimumScaleFactor=0.8;
_badge=[UILabel new];_badge.font=[UIFont boldSystemFontOfSize:14];_badge.textAlignment=NSTextAlignmentCenter;_badge.layer.cornerRadius=17;_badge.layer.masksToBounds=YES;
for(UIView *v in @[_caseView,_title,_sizeLabel]){v.translatesAutoresizingMaskIntoConstraints=NO;[self.contentView addSubview:v];}
for(UIView *v in @[_spine,_leftRib,_rightRib,_tab,_coverFrame,_caseMark,_contacts,_badge]){v.translatesAutoresizingMaskIntoConstraints=NO;[_caseView addSubview:v];}
for(UIView *v in @[_art,_shine,_labelBand]){v.translatesAutoresizingMaskIntoConstraints=NO;[_coverFrame addSubview:v];}
_bandText.translatesAutoresizingMaskIntoConstraints=NO;[_labelBand addSubview:_bandText];
[NSLayoutConstraint activateConstraints:@[
[_caseView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],[_caseView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],[_caseView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],[_caseView.heightAnchor constraintEqualToAnchor:self.contentView.widthAnchor],
[_spine.topAnchor constraintEqualToAnchor:_caseView.topAnchor constant:13],[_spine.bottomAnchor constraintEqualToAnchor:_caseView.bottomAnchor constant:-13],[_spine.leadingAnchor constraintEqualToAnchor:_caseView.leadingAnchor constant:5],[_spine.widthAnchor constraintEqualToConstant:6],
[_leftRib.topAnchor constraintEqualToAnchor:_spine.topAnchor],[_leftRib.bottomAnchor constraintEqualToAnchor:_spine.bottomAnchor],[_leftRib.leadingAnchor constraintEqualToAnchor:_spine.trailingAnchor constant:2],[_leftRib.widthAnchor constraintEqualToConstant:2],
[_rightRib.topAnchor constraintEqualToAnchor:_spine.topAnchor],[_rightRib.bottomAnchor constraintEqualToAnchor:_spine.bottomAnchor],[_rightRib.trailingAnchor constraintEqualToAnchor:_caseView.trailingAnchor constant:-4],[_rightRib.widthAnchor constraintEqualToConstant:3],
[_tab.topAnchor constraintEqualToAnchor:_caseView.topAnchor constant:2],[_tab.centerXAnchor constraintEqualToAnchor:_caseView.centerXAnchor],[_tab.widthAnchor constraintEqualToConstant:42],[_tab.heightAnchor constraintEqualToConstant:6],
[_coverFrame.topAnchor constraintEqualToAnchor:_caseView.topAnchor constant:13],[_coverFrame.leadingAnchor constraintEqualToAnchor:_leftRib.trailingAnchor constant:5],[_coverFrame.trailingAnchor constraintEqualToAnchor:_rightRib.leadingAnchor constant:-6],[_coverFrame.bottomAnchor constraintEqualToAnchor:_caseMark.topAnchor constant:-6],
[_labelBand.topAnchor constraintEqualToAnchor:_coverFrame.topAnchor],[_labelBand.leadingAnchor constraintEqualToAnchor:_coverFrame.leadingAnchor],[_labelBand.trailingAnchor constraintEqualToAnchor:_coverFrame.trailingAnchor],[_labelBand.heightAnchor constraintEqualToConstant:20],
[_bandText.leadingAnchor constraintEqualToAnchor:_labelBand.leadingAnchor constant:8],[_bandText.centerYAnchor constraintEqualToAnchor:_labelBand.centerYAnchor],[_bandText.trailingAnchor constraintLessThanOrEqualToAnchor:_labelBand.trailingAnchor constant:-5],
[_art.topAnchor constraintEqualToAnchor:_labelBand.bottomAnchor],[_art.bottomAnchor constraintEqualToAnchor:_coverFrame.bottomAnchor],[_art.leadingAnchor constraintEqualToAnchor:_coverFrame.leadingAnchor],[_art.trailingAnchor constraintEqualToAnchor:_coverFrame.trailingAnchor],
[_shine.topAnchor constraintEqualToAnchor:_coverFrame.topAnchor constant:-60],[_shine.bottomAnchor constraintEqualToAnchor:_coverFrame.bottomAnchor constant:60],[_shine.leadingAnchor constraintEqualToAnchor:_coverFrame.leadingAnchor constant:15],[_shine.widthAnchor constraintEqualToConstant:24],
[_caseMark.leadingAnchor constraintEqualToAnchor:_coverFrame.leadingAnchor],[_caseMark.trailingAnchor constraintLessThanOrEqualToAnchor:_contacts.leadingAnchor constant:-3],[_caseMark.bottomAnchor constraintEqualToAnchor:_caseView.bottomAnchor constant:-7],[_caseMark.heightAnchor constraintEqualToConstant:10],
[_contacts.trailingAnchor constraintEqualToAnchor:_coverFrame.trailingAnchor],[_contacts.centerYAnchor constraintEqualToAnchor:_caseMark.centerYAnchor],[_contacts.widthAnchor constraintEqualToConstant:43],
[_title.topAnchor constraintEqualToAnchor:_caseView.bottomAnchor constant:9],[_title.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:3],[_title.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
[_sizeLabel.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:3],[_sizeLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],[_sizeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
[_badge.bottomAnchor constraintEqualToAnchor:_coverFrame.bottomAnchor constant:-8],[_badge.trailingAnchor constraintEqualToAnchor:_coverFrame.trailingAnchor constant:-8],[_badge.widthAnchor constraintEqualToConstant:34],[_badge.heightAnchor constraintEqualToConstant:34]]];return self;}
- (void)layoutSubviews{[super layoutSubviews];CGRect b=_caseView.bounds;if(CGRectIsEmpty(b))return;
CGFloat w=b.size.width,h=b.size.height;
UIBezierPath *p=[UIBezierPath bezierPath];[p moveToPoint:CGPointMake(12,0)];
[p addLineToPoint:CGPointMake(w-26,0)];[p addLineToPoint:CGPointMake(w-26,7)];[p addLineToPoint:CGPointMake(w-8,7)];
[p addQuadCurveToPoint:CGPointMake(w,15) controlPoint:CGPointMake(w,7)];[p addLineToPoint:CGPointMake(w,h-13)];
[p addQuadCurveToPoint:CGPointMake(w-13,h) controlPoint:CGPointMake(w,h)];[p addLineToPoint:CGPointMake(13,h)];
[p addQuadCurveToPoint:CGPointMake(0,h-13) controlPoint:CGPointMake(0,h)];[p addLineToPoint:CGPointMake(0,12)];
[p addQuadCurveToPoint:CGPointMake(12,0) controlPoint:CGPointMake(0,0)];[p closePath];
_shellMask.frame=b;_shellMask.path=p.CGPath;_shellEdge.frame=b;_shellEdge.path=p.CGPath;}
@end
@interface LibraryView:UIViewController<UICollectionViewDataSource,UICollectionViewDelegateFlowLayout>
@property(nonatomic,strong)UICollectionView *grid;
@property(nonatomic,strong)UILabel *status,*countLabel;
@property(nonatomic,strong)NSSet<NSString *> *installed;
@property(nonatomic,assign)CGSize lastGridSize;
@end
@implementation LibraryView
- (void)viewDidLoad{[super viewDidLoad];self.view.backgroundColor=D(242,240,235,16,19,24);self.installed=[NSSet set];
UIView *header=[UIView new];header.backgroundColor=D(255,255,252,31,37,45);header.layer.cornerRadius=24;header.layer.borderWidth=1;header.layer.borderColor=C(190,194,197).CGColor;
UIView *red=[UIView new];red.backgroundColor=C(224,49,54);red.layer.cornerRadius=4;
UILabel *eyebrow=[UILabel new];eyebrow.text=@"T O N T O N   /   G A M E   C A R D S";eyebrow.textColor=C(203,54,59);eyebrow.font=[UIFont systemFontOfSize:10 weight:UIFontWeightHeavy];
UILabel *title=[UILabel new];title.text=@"TonTon游戏匣";title.textColor=UIColor.labelColor;title.font=[UIFont systemFontOfSize:32 weight:UIFontWeightHeavy];
UILabel *sub=[UILabel new];sub.text=@"打开你的游戏卡带";sub.textColor=UIColor.secondaryLabelColor;sub.font=[UIFont systemFontOfSize:14];
UILabel *count=[UILabel new];count.text=@"—\n款游戏";count.numberOfLines=2;count.textAlignment=NSTextAlignmentCenter;count.textColor=UIColor.labelColor;count.font=[UIFont systemFontOfSize:15 weight:UIFontWeightBold];count.backgroundColor=D(238,239,238,45,51,59);count.layer.cornerRadius=14;count.layer.masksToBounds=YES;self.countLabel=count;
_status=[UILabel new];_status.text=@"正在读取卡带…";_status.textColor=UIColor.secondaryLabelColor;_status.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
UIButton *add=[UIButton buttonWithType:UIButtonTypeSystem];UIImageSymbolConfiguration *cfg=[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];[add setImage:[UIImage systemImageNamed:@"plus" withConfiguration:cfg] forState:UIControlStateNormal];add.imageView.contentMode=UIViewContentModeCenter;add.accessibilityLabel=@"添加或扫描本机游戏";add.tintColor=UIColor.whiteColor;add.backgroundColor=C(218,50,56);add.layer.cornerRadius=27;add.layer.shadowColor=UIColor.blackColor.CGColor;add.layer.shadowOpacity=0.25;add.layer.shadowRadius=10;add.layer.shadowOffset=CGSizeMake(0,5);[add addTarget:self action:@selector(refresh) forControlEvents:UIControlEventTouchUpInside];
UICollectionViewFlowLayout *flow=[UICollectionViewFlowLayout new];flow.minimumInteritemSpacing=15;flow.minimumLineSpacing=10;flow.sectionInset=UIEdgeInsetsMake(4,0,68,0);
_grid=[[UICollectionView alloc]initWithFrame:CGRectZero collectionViewLayout:flow];_grid.backgroundColor=UIColor.clearColor;_grid.dataSource=self;_grid.delegate=self;[_grid registerClass:CoverCard.class forCellWithReuseIdentifier:@"card"];
for(UIView *v in @[header,_status,_grid,add]){v.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:v];}
for(UIView *v in @[red,eyebrow,title,sub,count]){v.translatesAutoresizingMaskIntoConstraints=NO;[header addSubview:v];}
UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
[NSLayoutConstraint activateConstraints:@[[header.topAnchor constraintEqualToAnchor:safe.topAnchor constant:6],[header.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:18],[header.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-18],[header.heightAnchor constraintEqualToConstant:86],
[red.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:18],[red.topAnchor constraintEqualToAnchor:header.topAnchor constant:14],[red.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-14],[red.widthAnchor constraintEqualToConstant:5],
[eyebrow.topAnchor constraintEqualToAnchor:header.topAnchor constant:11],[eyebrow.leadingAnchor constraintEqualToAnchor:red.trailingAnchor constant:14],
[title.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:3],[title.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],[title.trailingAnchor constraintLessThanOrEqualToAnchor:count.leadingAnchor constant:-12],
[sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:1],[sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
[count.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-17],[count.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],[count.widthAnchor constraintEqualToConstant:68],[count.heightAnchor constraintEqualToConstant:62],
[_status.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],[_status.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:4],
[_grid.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:7],[_grid.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:18],[_grid.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-18],[_grid.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
[add.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-22],[add.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],[add.widthAnchor constraintEqualToConstant:54],[add.heightAnchor constraintEqualToConstant:54]]];[self refresh];}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];if(!CGSizeEqualToSize(self.lastGridSize,self.grid.bounds.size)){self.lastGridSize=self.grid.bounds.size;[self.grid.collectionViewLayout invalidateLayout];}}
- (void)refresh{self.status.text=@"正在读取卡带…";dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{excludeGameResourcesFromBackup();NSSet *ids=NXInstalledGames();dispatch_async(dispatch_get_main_queue(),^{self.installed=ids;NSUInteger n=0;for(NSDictionary *g in games())if([ids containsObject:bundleForGame(g)])n++;self.countLabel.text=[NSString stringWithFormat:@"%02lu\n款游戏",(unsigned long)n];self.status.text=n?[NSString stringWithFormat:@"%lu 款可打开 · 轻点卡带封面",(unsigned long)n]:@"等待读取游戏；点右下角重新扫描";[self.grid reloadData];});});}
- (NSArray<NSDictionary *> *)displayGames{if(!self.installed.count)return games();NSMutableArray *array=[NSMutableArray new];for(NSDictionary *g in games())if([self.installed containsObject:bundleForGame(g)])[array addObject:g];return array;}
- (NSInteger)collectionView:(UICollectionView *)v numberOfItemsInSection:(NSInteger)s{(void)v;(void)s;return self.displayGames.count;}
- (UICollectionViewCell *)collectionView:(UICollectionView *)v cellForItemAtIndexPath:(NSIndexPath *)p{CoverCard *c=(CoverCard *)[v dequeueReusableCellWithReuseIdentifier:@"card" forIndexPath:p];NSDictionary *g=self.displayGames[p.item];NSString *b=bundleForGame(g);BOOL installed=[self.installed containsObject:b];c.art.image=[UIImage imageNamed:g[@"id"]];c.title.text=g[@"name"];c.sizeLabel.text=[NSString stringWithFormat:@"%@  ·  %@",g[@"size"],g[@"version"]];c.badge.text=installed?@"▶":@"…";c.badge.backgroundColor=installed?[UIColor colorWithWhite:0 alpha:0.72]:[UIColor colorWithWhite:0 alpha:0.45];c.badge.textColor=UIColor.whiteColor;return c;}
- (CGSize)collectionView:(UICollectionView *)v layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)p{(void)l;(void)p;CGFloat w=v.bounds.size.width;NSInteger n=w>=700?4:w>=500?3:2;NSInteger rows=(self.displayGames.count+n-1)/n;CGFloat byWidth=floor((w-(n-1)*15)/n);CGFloat byHeight=rows==2?floor((v.bounds.size.height-4-68-10)/2-60):300;CGFloat side=MIN(300,MIN(byWidth,MAX(120,byHeight)));return CGSizeMake(side,side+60);}
- (void)collectionView:(UICollectionView *)v didSelectItemAtIndexPath:(NSIndexPath *)p{(void)v;NSDictionary *g=self.displayGames[p.item];NSString *b=bundleForGame(g);if(![self.installed containsObject:b])return;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{if(!NXOpenInstalledGame(b))dispatch_async(dispatch_get_main_queue(),^{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"启动失败" message:@"请保持 MCP 服务运行后刷新，再试一次。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];});});}
@end
@interface LibraryDelegate:UIResponder<UIApplicationDelegate>
@property(nonatomic,strong)UIWindow *window;
@end
@implementation LibraryDelegate
- (BOOL)application:(UIApplication *)a didFinishLaunchingWithOptions:(NSDictionary *)o{(void)a;(void)o;self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[LibraryView new];[self.window makeKeyAndVisible];return YES;}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(LibraryDelegate.class));}}

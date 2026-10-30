#import <UIKit/UIKit.h>
#import "GameOpen.h"
static UIColor *C(int r,int g,int b){return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1];}
static NSArray<NSDictionary *> *games(void){return @[
@{@"name":@"极品飞车：热力追踪",@"id":@"010029b0118e8000"},
@{@"name":@"集合啦！动物森友会",@"id":@"01006f8002326000"},
@{@"name":@"宝可梦铁拳 DX",@"id":@"0100b3f000be2000"},
@{@"name":@"魔法使之夜",@"id":@"0100751018dba000"},
@{@"name":@"宝可梦传说：阿尔宙斯",@"id":@"01001f5010dfa000"},
@{@"name":@"宝可梦传说：Z-A",@"id":@"0100f43008c44000"},
@{@"name":@"巫师 3",@"id":@"0100e67012924000"}];}
@interface CoverCard:UICollectionViewCell
@property(nonatomic,strong)UIImageView *art;
@property(nonatomic,strong)UILabel *title,*badge;
@property(nonatomic,strong)CAGradientLayer *shade;
@end
@implementation CoverCard
- (instancetype)initWithFrame:(CGRect)f{if(!(self=[super initWithFrame:f]))return nil;
self.contentView.backgroundColor=UIColor.secondarySystemBackgroundColor;self.contentView.layer.cornerRadius=18;self.contentView.layer.masksToBounds=YES;
_art=[UIImageView new];_art.contentMode=UIViewContentModeScaleAspectFill;_art.backgroundColor=UIColor.tertiarySystemBackgroundColor;_art.clipsToBounds=YES;
_shade=[CAGradientLayer layer];_shade.colors=@[(__bridge id)UIColor.clearColor.CGColor,(__bridge id)[UIColor colorWithWhite:0 alpha:0.82].CGColor];_shade.startPoint=CGPointMake(0,0.35);_shade.endPoint=CGPointMake(0,1);
_title=[UILabel new];_title.font=[UIFont boldSystemFontOfSize:17];_title.textColor=UIColor.whiteColor;_title.numberOfLines=2;
_badge=[UILabel new];_badge.font=[UIFont boldSystemFontOfSize:12];_badge.textAlignment=NSTextAlignmentCenter;_badge.layer.cornerRadius=9;_badge.layer.masksToBounds=YES;
for(UIView *v in @[_art,_title,_badge]){v.translatesAutoresizingMaskIntoConstraints=NO;[self.contentView addSubview:v];}
[self.contentView.layer insertSublayer:_shade above:_art.layer];
[NSLayoutConstraint activateConstraints:@[
[_art.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],[_art.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],[_art.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],[_art.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
[_title.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-14],[_title.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],[_title.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14],
[_badge.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],[_badge.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],[_badge.widthAnchor constraintEqualToConstant:56],[_badge.heightAnchor constraintEqualToConstant:24]]];return self;}
- (void)layoutSubviews{[super layoutSubviews];self.shade.frame=self.contentView.bounds;}
@end
@interface LibraryView:UIViewController<UICollectionViewDataSource,UICollectionViewDelegateFlowLayout>
@property(nonatomic,strong)UICollectionView *grid;
@property(nonatomic,strong)UILabel *status;
@property(nonatomic,strong)NSSet<NSString *> *installed;
@end
@implementation LibraryView
- (void)viewDidLoad{[super viewDidLoad];self.view.backgroundColor=UIColor.systemBackgroundColor;self.installed=[NSSet set];
UILabel *title=[UILabel new];title.text=@"游戏库";title.textColor=UIColor.labelColor;title.font=[UIFont systemFontOfSize:36 weight:UIFontWeightHeavy];
UILabel *sub=[UILabel new];sub.text=@"你在这台设备上的 Switch 游戏";sub.textColor=UIColor.secondaryLabelColor;sub.font=[UIFont systemFontOfSize:16];
_status=[UILabel new];_status.text=@"正在读取已安装游戏…";_status.textColor=UIColor.systemTealColor;_status.font=[UIFont systemFontOfSize:13];
UIButton *refresh=[UIButton buttonWithType:UIButtonTypeSystem];[refresh setTitle:@"刷新" forState:UIControlStateNormal];refresh.tintColor=UIColor.systemTealColor;[refresh addTarget:self action:@selector(refresh) forControlEvents:UIControlEventTouchUpInside];
UICollectionViewFlowLayout *flow=[UICollectionViewFlowLayout new];flow.minimumInteritemSpacing=18;flow.minimumLineSpacing=22;flow.sectionInset=UIEdgeInsetsMake(16,0,24,0);
_grid=[[UICollectionView alloc]initWithFrame:CGRectZero collectionViewLayout:flow];_grid.backgroundColor=UIColor.clearColor;_grid.dataSource=self;_grid.delegate=self;[_grid registerClass:CoverCard.class forCellWithReuseIdentifier:@"card"];
for(UIView *v in @[title,sub,_status,refresh,_grid]){v.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:v];}
UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
[NSLayoutConstraint activateConstraints:@[[title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:22],[title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:28],
[sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],[sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
[_status.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:11],[_status.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
[refresh.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],[refresh.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-28],
[_grid.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:12],[_grid.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:28],[_grid.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-28],[_grid.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]]];[self refresh];}
- (void)refresh{self.status.text=@"正在读取已安装游戏…";dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSSet *ids=NXInstalledGames();dispatch_async(dispatch_get_main_queue(),^{self.installed=ids;NSUInteger n=0;for(NSDictionary *g in games())if([ids containsObject:[@"org.nxnative." stringByAppendingString:g[@"id"]]])n++;self.status.text=n?[NSString stringWithFormat:@"已安装 %lu 款 · 点封面启动",(unsigned long)n]:@"尚未读取到游戏；请保持 MCP 运行后刷新";[self.grid reloadData];});});}
- (NSInteger)collectionView:(UICollectionView *)v numberOfItemsInSection:(NSInteger)s{(void)v;(void)s;return games().count;}
- (UICollectionViewCell *)collectionView:(UICollectionView *)v cellForItemAtIndexPath:(NSIndexPath *)p{CoverCard *c=(CoverCard *)[v dequeueReusableCellWithReuseIdentifier:@"card" forIndexPath:p];NSDictionary *g=games()[p.item];NSString *b=[@"org.nxnative." stringByAppendingString:g[@"id"]];BOOL installed=[self.installed containsObject:b];c.art.image=[UIImage imageNamed:g[@"id"]];c.title.text=g[@"name"];c.badge.text=installed?@"打开":@"待安装";c.badge.backgroundColor=installed?C(96,222,231):C(55,65,84);c.badge.textColor=installed?C(8,41,48):C(182,194,210);return c;}
- (CGSize)collectionView:(UICollectionView *)v layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)p{(void)l;(void)p;CGFloat w=v.bounds.size.width;NSInteger n=w>950?4:w>650?3:2;CGFloat side=floor((w-(n-1)*18)/n);return CGSizeMake(side,round(side*1.32));}
- (void)collectionView:(UICollectionView *)v didSelectItemAtIndexPath:(NSIndexPath *)p{(void)v;NSDictionary *g=games()[p.item];NSString *b=[@"org.nxnative." stringByAppendingString:g[@"id"]];if(![self.installed containsObject:b])return;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{if(!NXOpenInstalledGame(b))dispatch_async(dispatch_get_main_queue(),^{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"启动失败" message:@"请保持 MCP 服务运行后刷新，再试一次。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];});});}
@end
@interface LibraryDelegate:UIResponder<UIApplicationDelegate>
@property(nonatomic,strong)UIWindow *window;
@end
@implementation LibraryDelegate
- (BOOL)application:(UIApplication *)a didFinishLaunchingWithOptions:(NSDictionary *)o{(void)a;(void)o;self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[LibraryView new];[self.window makeKeyAndVisible];return YES;}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(LibraryDelegate.class));}}

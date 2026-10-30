#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <stdbool.h>
#include <errno.h>
#include <sys/stat.h>
#include <string.h>
#import "GameOpen.h"
#import "LibraryRoot.h"
#ifdef DM_LIBRARY_HOST
#include "game_profile_runtime.h"
#include "dmsh_chain.h"
// The library picks a card before the game front end is created. The standalone
// Swift launcher is per IPA and has no active game until that selection.
bool dm_show_launcher(void *view_controller, void (*done)(void)) {
    (void)view_controller; (void)done;
    return false;
}
#endif
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
static NSDictionary *gameCard(NSString *title, NSString *documents, NSString *bundled){
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *slot=[documents stringByAppendingPathComponent:title];
    NSString *meta=[slot stringByAppendingPathComponent:@"GameCard.json"];
    if(![fm fileExistsAtPath:meta])meta=[[bundled stringByAppendingPathComponent:title] stringByAppendingPathComponent:@"GameCard.json"];
    NSData *data=[NSData dataWithContentsOfFile:meta];
    NSDictionary *stored=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if(![stored isKindOfClass:NSDictionary.class] ||
       ![stored[@"title_id"] isKindOfClass:NSString.class] ||
       [stored[@"title_id"] caseInsensitiveCompare:title]!=NSOrderedSame)stored=nil;
    NSString *name=[stored[@"name"] isKindOfClass:NSString.class]&&[stored[@"name"] length]?stored[@"name"]:title;
#ifdef DM_LIBRARY_HOST
    if([name isEqualToString:title]){
        const dm_game_profile *profile=dm_profile_find(title.UTF8String);
        if(profile&&profile->name&&profile->name[0])name=[NSString stringWithUTF8String:profile->name];
    }
#endif
    NSString *version=[stored[@"version"] isKindOfClass:NSString.class]&&[stored[@"version"] length]?stored[@"version"]:@"本地文件";
    NSString *size=[stored[@"size"] isKindOfClass:NSString.class]&&[stored[@"size"] length]?stored[@"size"]:@"已导入";
    NSString *source=[slot stringByAppendingPathComponent:@"Source"];
    BOOL sourceDir=NO;
    BOOL pending=[fm fileExistsAtPath:source isDirectory:&sourceDir]&&sourceDir&&
        [fm contentsOfDirectoryAtPath:source error:nil].count>0;
    NSMutableDictionary *card=[@{@"name":name,@"id":title,@"size":size,@"version":version,@"pending":@(pending)} mutableCopy];
    if([stored[@"bundle"] isKindOfClass:NSString.class])card[@"bundle"]=stored[@"bundle"];
    return card;
}
static NSArray<NSDictionary *> *games(void){
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *doc=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString *root=[doc stringByAppendingPathComponent:@"Games"];
    NSString *bundled=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"GameResources"];
    NSMutableSet<NSString *> *titles=[NSMutableSet set];
    for(NSString *base in @[root,bundled])for(NSString *name in [fm contentsOfDirectoryAtPath:base error:nil]){
        if(!name.length||[name hasPrefix:@"."]||name.length>64)continue;
        BOOL directory=NO;
        NSString *slot=[base stringByAppendingPathComponent:name];
        if(!([fm fileExistsAtPath:slot isDirectory:&directory]&&directory))continue;
        BOOL containsGameFiles=NO;
        for(NSString *part in @[@"Resources",@"UserData",@"Source"]){
            NSString *path=[slot stringByAppendingPathComponent:part];
            BOOL partIsDirectory=NO;
            if([fm fileExistsAtPath:path isDirectory:&partIsDirectory]&&partIsDirectory&&
               [fm contentsOfDirectoryAtPath:path error:nil].count>0){containsGameFiles=YES;break;}
        }
        if(containsGameFiles)[titles addObject:name.lowercaseString];
    }
    NSMutableArray<NSDictionary *> *all=[NSMutableArray array];
    for(NSString *title in titles)[all addObject:gameCard(title,root,bundled)];
    NSString *incoming=[doc stringByAppendingPathComponent:@"Imports"];
    for(NSString *name in [fm contentsOfDirectoryAtPath:incoming error:nil]){
        if([name hasPrefix:@"."])continue;
        NSString *path=[incoming stringByAppendingPathComponent:name];
        BOOL folder=NO;[fm fileExistsAtPath:path isDirectory:&folder];
        NSDictionary *attrs=[fm attributesOfItemAtPath:path error:nil];
        unsigned long long bytes=[attrs[NSFileSize] unsignedLongLongValue];
        NSString *size=folder?@"游戏文件夹":[NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
        [all addObject:@{@"name":name.stringByDeletingPathExtension,@"id":[@"import:" stringByAppendingString:name],@"size":size,@"version":@"等待转换",@"pending":@YES}];
    }
    [all sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"name"] localizedStandardCompare:b[@"name"]];}];
    return all;
}
static NSString *bundleForGame(NSDictionary *g){return g[@"bundle"] ?: [@"org.nxnative." stringByAppendingString:g[@"id"]];}
static UIImage *coverForGame(NSDictionary *g){
    NSString *title=g[@"id"];
    UIImage *bundled=[UIImage imageNamed:title];
    if(bundled)return bundled;
    NSString *doc=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString *slot=[[doc stringByAppendingPathComponent:@"Games"] stringByAppendingPathComponent:title];
    NSString *inside=[[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"GameResources"] stringByAppendingPathComponent:title];
    for(NSString *base in @[slot,inside])for(NSString *file in @[@"Cover.png",@"cover.png",@"Icon.png"]){
        UIImage *image=[UIImage imageWithContentsOfFile:[base stringByAppendingPathComponent:file]];
        if(image)return image;
    }
    return nil;
}
#ifdef DM_LIBRARY_HOST
static NSString *resourceRootForTitle(NSString *gamesRoot, NSString *title){
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *documents=[[gamesRoot stringByAppendingPathComponent:title] stringByAppendingPathComponent:@"Resources"];
    NSString *bundled=[[[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"GameResources"] stringByAppendingPathComponent:title] stringByStandardizingPath];
    for(NSString *candidate in @[documents,bundled]){
        BOOL isDir=NO;
        if([fm fileExistsAtPath:[candidate stringByAppendingPathComponent:@"dm/shader_map.tsv"]] &&
           [fm fileExistsAtPath:[candidate stringByAppendingPathComponent:@"msl"] isDirectory:&isDir]&&isDir)
            return candidate;
    }
    return nil;
}
#endif
static NSSet<NSString *> *availableGames(NSArray<NSDictionary *> *catalog){
#ifdef DM_LIBRARY_HOST
    NSString *doc=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString *root=[doc stringByAppendingPathComponent:@"Games"];
    NSMutableSet<NSString *> *result=[NSMutableSet set];
    for(NSDictionary *g in catalog){
        NSString *title=g[@"id"];
        const dm_game_profile *profile=dm_profile_find(title.UTF8String);
        if(!profile)continue;
        NSString *resources=resourceRootForTitle(root,title);
        if(!resources)continue;
        NSString *tables=[resources stringByAppendingPathComponent:@"dm"];
        NSString *chain=[resources stringByAppendingPathComponent:[NSString stringWithFormat:@"msl/b-%s",DMSH_CHAIN]];
        NSString *stamp=[NSString stringWithContentsOfFile:[chain stringByAppendingPathComponent:@"inputs.tsv"] encoding:NSUTF8StringEncoding error:nil];
        NSString *gameRow=[NSString stringWithFormat:@"game\t%@",title.uppercaseString];
        if(![[stamp componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] containsObject:gameRow])continue;
        BOOL isDir=NO;
        NSString *user=[[root stringByAppendingPathComponent:title] stringByAppendingPathComponent:@"UserData"];
        BOOL bundled=[resources hasPrefix:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"GameResources/"]];
        BOOL userIsDir=NO;
        BOOL haveUser=[NSFileManager.defaultManager fileExistsAtPath:user isDirectory:&userIsDir]&&userIsDir;
        NSString *marker=[NSString stringWithUTF8String:profile->romfs_marker];
        BOOL romfs=[NSFileManager.defaultManager fileExistsAtPath:[resources stringByAppendingPathComponent:@"romfs.img"]] ||
            [NSFileManager.defaultManager fileExistsAtPath:[user stringByAppendingPathComponent:@"romfs.img"]] ||
            [NSFileManager.defaultManager fileExistsAtPath:[[resources stringByAppendingPathComponent:@"romfs"] stringByAppendingPathComponent:marker]] ||
            [NSFileManager.defaultManager fileExistsAtPath:[[user stringByAppendingPathComponent:@"romfs"] stringByAppendingPathComponent:marker]];
        if((bundled||haveUser)&&
           [NSFileManager.defaultManager fileExistsAtPath:tables isDirectory:&isDir]&&isDir&&
           [NSFileManager.defaultManager fileExistsAtPath:[resources stringByAppendingPathComponent:@"msl"] isDirectory:&isDir]&&isDir&&
           [NSFileManager.defaultManager fileExistsAtPath:[tables stringByAppendingPathComponent:@"shader_map.tsv"]]&&
           romfs)
            [result addObject:bundleForGame(g)];
    }
    return result;
#else
    return NXInstalledGames();
#endif
}
@interface CoverCard:UICollectionViewCell
@property(nonatomic,strong)UIView *caseView,*spine,*coverFrame,*shine,*tab,*labelBand,*leftRib,*rightRib;
@property(nonatomic,strong)UIImageView *art;
@property(nonatomic,strong)UILabel *title,*sizeLabel,*badge,*caseMark,*contacts,*bandText,*placeholder;
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
_placeholder=[UILabel new];_placeholder.textColor=UIColor.whiteColor;_placeholder.font=[UIFont systemFontOfSize:21 weight:UIFontWeightHeavy];_placeholder.textAlignment=NSTextAlignmentCenter;_placeholder.numberOfLines=4;
_shine=[UIView new];_shine.backgroundColor=[UIColor colorWithWhite:1 alpha:0.08];_shine.transform=CGAffineTransformMakeRotation(-0.35);
_caseMark=[UILabel new];_caseMark.text=@"TTG  •  GAME CARD";_caseMark.textColor=C(155,162,171);_caseMark.font=[UIFont systemFontOfSize:8 weight:UIFontWeightBold];_caseMark.adjustsFontSizeToFitWidth=YES;
_contacts=[UILabel new];_contacts.text=@"▮ ▮ ▮ ▮";_contacts.textColor=C(202,165,83);_contacts.font=[UIFont systemFontOfSize:8 weight:UIFontWeightHeavy];
_title=[UILabel new];_title.font=[UIFont systemFontOfSize:15 weight:UIFontWeightBold];_title.textColor=UIColor.labelColor;_title.textAlignment=NSTextAlignmentLeft;_title.numberOfLines=2;
_sizeLabel=[UILabel new];_sizeLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightMedium];_sizeLabel.textColor=UIColor.secondaryLabelColor;_sizeLabel.adjustsFontSizeToFitWidth=YES;_sizeLabel.minimumScaleFactor=0.8;
_badge=[UILabel new];_badge.font=[UIFont boldSystemFontOfSize:14];_badge.textAlignment=NSTextAlignmentCenter;_badge.layer.cornerRadius=17;_badge.layer.masksToBounds=YES;
for(UIView *v in @[_caseView,_title,_sizeLabel]){v.translatesAutoresizingMaskIntoConstraints=NO;[self.contentView addSubview:v];}
for(UIView *v in @[_spine,_leftRib,_rightRib,_tab,_coverFrame,_caseMark,_contacts,_badge]){v.translatesAutoresizingMaskIntoConstraints=NO;[_caseView addSubview:v];}
for(UIView *v in @[_art,_placeholder,_shine,_labelBand]){v.translatesAutoresizingMaskIntoConstraints=NO;[_coverFrame addSubview:v];}
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
[_placeholder.centerYAnchor constraintEqualToAnchor:_art.centerYAnchor],[_placeholder.leadingAnchor constraintEqualToAnchor:_art.leadingAnchor constant:12],[_placeholder.trailingAnchor constraintEqualToAnchor:_art.trailingAnchor constant:-12],
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
@interface LibraryView:UIViewController<UICollectionViewDataSource,UICollectionViewDelegateFlowLayout,UIDocumentPickerDelegate>
@property(nonatomic,strong)UICollectionView *grid;
@property(nonatomic,strong)UILabel *status,*countLabel;
@property(nonatomic,strong)NSSet<NSString *> *installed;
@property(nonatomic,copy)NSArray<NSDictionary *> *catalog;
@property(nonatomic,assign)CGSize lastGridSize;
@property(nonatomic,copy)void (^startGame)(NSString *titleID);
@end
@implementation LibraryView
- (void)viewDidLoad{[super viewDidLoad];self.view.backgroundColor=D(242,240,235,16,19,24);self.installed=[NSSet set];
UIView *header=[UIView new];header.backgroundColor=D(255,255,252,31,37,45);header.layer.cornerRadius=24;header.layer.borderWidth=1;header.layer.borderColor=C(190,194,197).CGColor;
UIView *red=[UIView new];red.backgroundColor=C(224,49,54);red.layer.cornerRadius=4;
UILabel *eyebrow=[UILabel new];eyebrow.text=@"T O N T O N   /   G A M E   C A R D S";eyebrow.textColor=C(203,54,59);eyebrow.font=[UIFont systemFontOfSize:10 weight:UIFontWeightHeavy];
UILabel *title=[UILabel new];title.text=@"TonTon游戏匣";title.textColor=UIColor.labelColor;title.font=[UIFont systemFontOfSize:32 weight:UIFontWeightHeavy];
UILabel *sub=[UILabel new];sub.text=@"打开你的游戏卡带";sub.textColor=UIColor.secondaryLabelColor;sub.font=[UIFont systemFontOfSize:14];
UILabel *count=[UILabel new];count.text=@"—\n款卡带";count.numberOfLines=2;count.textAlignment=NSTextAlignmentCenter;count.textColor=UIColor.labelColor;count.font=[UIFont systemFontOfSize:15 weight:UIFontWeightBold];count.backgroundColor=D(238,239,238,45,51,59);count.layer.cornerRadius=14;count.layer.masksToBounds=YES;self.countLabel=count;
_status=[UILabel new];_status.text=@"正在读取卡带…";_status.textColor=UIColor.secondaryLabelColor;_status.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
UIButton *add=[UIButton buttonWithType:UIButtonTypeSystem];UIImageSymbolConfiguration *cfg=[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];[add setImage:[UIImage systemImageNamed:@"plus" withConfiguration:cfg] forState:UIControlStateNormal];add.imageView.contentMode=UIViewContentModeCenter;add.accessibilityLabel=@"添加 Switch 游戏";add.tintColor=UIColor.whiteColor;add.backgroundColor=C(218,50,56);add.layer.cornerRadius=27;add.layer.shadowColor=UIColor.blackColor.CGColor;add.layer.shadowOpacity=0.25;add.layer.shadowRadius=10;add.layer.shadowOffset=CGSizeMake(0,5);[add addTarget:self action:@selector(addGame) forControlEvents:UIControlEventTouchUpInside];
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
[add.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-22],[add.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],[add.widthAnchor constraintEqualToConstant:54],[add.heightAnchor constraintEqualToConstant:54]]];[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:UIApplicationDidBecomeActiveNotification object:nil];[self refresh];}
- (void)dealloc{[[NSNotificationCenter defaultCenter] removeObserver:self];}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];if(!CGSizeEqualToSize(self.lastGridSize,self.grid.bounds.size)){self.lastGridSize=self.grid.bounds.size;[self.grid.collectionViewLayout invalidateLayout];}}
- (void)showNotice:(NSString *)title detail:(NSString *)detail{UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)addGame{
    if(self.presentedViewController)return;
    self.status.text=@"正在打开文件选择器…";
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypeFolder,UTTypeData] asCopy:NO];
    picker.delegate=self;picker.allowsMultipleSelection=NO;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)picker{(void)picker;[self refresh];}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
    (void)picker;NSURL *source=urls.firstObject;if(!source)return;
    BOOL scoped=[source startAccessingSecurityScopedResource];
    NSString *name=source.lastPathComponent;
    BOOL folder=NO;[NSFileManager.defaultManager fileExistsAtPath:source.path isDirectory:&folder];
    NSString *ext=name.pathExtension.lowercaseString;
    if(!folder && ![@[@"nsp",@"xci",@"nsz",@"nca"] containsObject:ext]){
        if(scoped)[source stopAccessingSecurityScopedResource];
        [self showNotice:@"无法添加" detail:@"请选择 Switch 游戏文件（NSP、XCI、NSZ）或游戏文件夹。"];return;
    }
    NSString *doc=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString *incoming=[doc stringByAppendingPathComponent:@"Imports"];
    NSString *gamesRoot=[doc stringByAppendingPathComponent:@"Games"];
    NSFileManager *fm=NSFileManager.defaultManager;
    [fm createDirectoryAtPath:incoming withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:gamesRoot withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *title=name.lowercaseString;
#ifdef DM_LIBRARY_HOST
    BOOL registered=title.length==16 && dm_profile_find(title.UTF8String)!=NULL;
#else
    BOOL registered=NO;
#endif
    BOOL prepared=folder && registered &&
        [fm fileExistsAtPath:[[source.path stringByAppendingPathComponent:@"Resources/dm"] stringByAppendingPathComponent:@"shader_map.tsv"]] &&
        [fm fileExistsAtPath:[source.path stringByAppendingPathComponent:@"Resources/msl"]] &&
        [fm fileExistsAtPath:[source.path stringByAppendingPathComponent:@"UserData"]];
    NSString *destination=prepared?[gamesRoot stringByAppendingPathComponent:title]:[incoming stringByAppendingPathComponent:name];
    if([fm fileExistsAtPath:destination]){
        if(scoped)[source stopAccessingSecurityScopedResource];
        [self showNotice:@"已存在" detail:@"游戏匣里已有同名文件；没有覆盖原数据。"];return;
    }
    __block NSString *failure=nil;__block BOOL moved=NO;
    NSURL *target=[NSURL fileURLWithPath:destination];
    NSFileCoordinator *coordinator=[[NSFileCoordinator alloc]initWithFilePresenter:nil];NSError *coordinateError=nil;
    [coordinator coordinateWritingItemAtURL:source options:NSFileCoordinatorWritingForMoving error:&coordinateError byAccessor:^(NSURL *coordinated){
        struct stat a,b,c;
        if(stat(coordinated.fileSystemRepresentation,&a)||stat(target.URLByDeletingLastPathComponent.fileSystemRepresentation,&b)){
            failure=@"无法读取文件或目标目录。";return;
        }
        if(a.st_dev!=b.st_dev){failure=@"文件和游戏匣不在同一个磁盘；请先移到“我的 iPad”后再添加。";return;}
        if(rename(coordinated.fileSystemRepresentation,target.fileSystemRepresentation)){
            failure=[NSString stringWithFormat:@"移动失败（%s）。原文件仍保留。",strerror(errno)];return;
        }
        if(stat(target.fileSystemRepresentation,&c)||c.st_dev!=a.st_dev||c.st_ino!=a.st_ino){
            failure=@"移动后的文件身份未通过核对，请不要重复导入。";return;
        }
        [coordinator itemAtURL:coordinated didMoveToURL:target];moved=YES;
    }];
    if(scoped)[source stopAccessingSecurityScopedResource];
    if(coordinateError && !failure)failure=coordinateError.localizedDescription;
    if(!moved){[self showNotice:@"无法添加" detail:failure?:@"文件尚未移动，请再试一次。"];return;}
    [self refresh];
    [self showNotice:prepared?@"卡带已加入":@"文件已加入游戏匣" detail:prepared?@"可以从卡带封面打开。":@"文件已直接移动到游戏匣。转换程序完成后，这张卡带才能启动。"];
}
- (void)refresh{self.status.text=@"正在读取卡带…";dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{excludeGameResourcesFromBackup();NSArray *catalog=games();NSSet *ids=availableGames(catalog);dispatch_async(dispatch_get_main_queue(),^{self.catalog=catalog;self.installed=ids;NSUInteger playable=0;for(NSDictionary *g in catalog)if([ids containsObject:bundleForGame(g)])playable++;self.countLabel.text=[NSString stringWithFormat:@"%02lu\n款卡带",(unsigned long)catalog.count];self.status.text=catalog.count?[NSString stringWithFormat:@"%lu 款已收录 · %lu 款可打开",(unsigned long)catalog.count,(unsigned long)playable]:@"点右下角添加游戏";[self.grid reloadData];});});}
- (NSArray<NSDictionary *> *)displayGames{return self.catalog?:@[];}
- (NSInteger)collectionView:(UICollectionView *)v numberOfItemsInSection:(NSInteger)s{(void)v;(void)s;return self.displayGames.count;}
- (UICollectionViewCell *)collectionView:(UICollectionView *)v cellForItemAtIndexPath:(NSIndexPath *)p{CoverCard *c=(CoverCard *)[v dequeueReusableCellWithReuseIdentifier:@"card" forIndexPath:p];NSDictionary *g=self.displayGames[p.item];NSString *b=bundleForGame(g);BOOL installed=[self.installed containsObject:b];c.art.image=coverForGame(g);c.placeholder.text=g[@"name"];c.placeholder.hidden=c.art.image!=nil;c.art.backgroundColor=C(37,48,66);c.title.text=g[@"name"];c.sizeLabel.text=[NSString stringWithFormat:@"%@  ·  %@",g[@"size"],g[@"version"]];c.badge.text=installed?@"▶":@"…";c.badge.backgroundColor=installed?[UIColor colorWithWhite:0 alpha:0.72]:[UIColor colorWithWhite:0 alpha:0.45];c.badge.textColor=UIColor.whiteColor;return c;}
- (CGSize)collectionView:(UICollectionView *)v layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)p{(void)l;(void)p;CGFloat w=v.bounds.size.width;NSInteger n=w>=700?4:w>=500?3:2;NSInteger rows=(self.displayGames.count+n-1)/n;CGFloat byWidth=floor((w-(n-1)*15)/n);CGFloat byHeight=rows==2?floor((v.bounds.size.height-4-68-10)/2-60):300;CGFloat side=MIN(300,MIN(byWidth,MAX(120,byHeight)));return CGSizeMake(side,side+60);}
- (void)collectionView:(UICollectionView *)v didSelectItemAtIndexPath:(NSIndexPath *)p{(void)v;NSDictionary *g=self.displayGames[p.item];NSString *b=bundleForGame(g);if(![self.installed containsObject:b]){if([g[@"pending"] boolValue])[self showNotice:@"文件已加入" detail:@"游戏文件已移入游戏匣。程序转换完成并更新游戏匣后才能打开。"];else [self showNotice:@"等待整合" detail:@"这款游戏已登记；程序和资源完成整合后才能从这里启动。原游戏和存档会保留到新版本可用。"] ;return;}
#ifdef DM_LIBRARY_HOST
    if(self.startGame)self.startGame(g[@"id"]);
#else
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{if(!NXOpenInstalledGame(b))dispatch_async(dispatch_get_main_queue(),^{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"启动失败" message:@"请保持 MCP 服务运行后刷新，再试一次。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];});});
#endif
}
@end
UIViewController *TonTonLibraryController(void (^startGame)(NSString *titleID)){
    LibraryView *view=[LibraryView new];view.startGame=startGame;return view;
}
#ifndef DM_LIBRARY_HOST
@interface LibraryDelegate:UIResponder<UIApplicationDelegate>
@property(nonatomic,strong)UIWindow *window;
@end
@implementation LibraryDelegate
- (BOOL)application:(UIApplication *)a didFinishLaunchingWithOptions:(NSDictionary *)o{(void)a;(void)o;self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[LibraryView new];[self.window makeKeyAndVisible];return YES;}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(LibraryDelegate.class));}}
#endif

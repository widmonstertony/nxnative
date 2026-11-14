#import <UIKit/UIKit.h>
#import <GameController/GCEventInteraction.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <stdbool.h>
#include <errno.h>
#include <sys/stat.h>
#include <string.h>
#import "GameOpen.h"
#import "LibraryRoot.h"
#import "ResourceImport.h"
#import "StorageStatus.h"
#import "GameSettings.h"
#import "GameTitleNames.h"
#import "GameRemoval.h"
#import <GameController/GameController.h>
#import "MenuControllerInput.h"
#import "ControlPreferences.h"
#import "TouchLayoutEditor.h"
#ifdef DM_LIBRARY_HOST
#import "../../Sources/CloudSaves.h"
#endif
#ifdef DM_LIBRARY_HOST
#include "game_profile_runtime.h"
#include "dmsh_chain.h"
#import "LibraryAvailability.h"
// The library picks a card before the game front end is created. The standalone
// Swift launcher is per IPA and has no active game until that selection.
bool dm_show_launcher(void *view_controller, void (*done)(void)) {
    (void)view_controller; (void)done;
    return false;
}
#endif
static UIColor *C(int r,int g,int b){return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1];}
static UIColor *D(int lr,int lg,int lb,int dr,int dg,int db){return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t){return t.userInterfaceStyle==UIUserInterfaceStyleDark?C(dr,dg,db):C(lr,lg,lb);}];}
// These are preferences for the library, not a second copy of each game's
// launcher.json. Game-specific settings still require an entry in that schema.
static NSArray<NSDictionary *> *libraryPreferences(void){
    return @[
        @{@"key":@"DM_FRAME_LIMIT",@"title":@"\u5E27\u7387\u9650\u5236",@"default":@"game",@"choices":@[@[@"unlimited",@"\u4E0D\u9650\u5236"],@[@"game",@"\u6E38\u620F\u539F\u59CB\u8BBE\u7F6E"]]},
        @{@"key":@"DM_LANG",@"title":@"\u6E38\u620F\u8BED\u8A00",@"choices":@[@[@"auto",@"\u6E38\u620F\u9ED8\u8BA4"],@[@"chinese",@"\u4F18\u5148\u4E2D\u6587"],@[@"english",@"\u82F1\u8BED"]]},
        @{@"key":@"DM_OPMODE",@"title":@"\u8FD0\u884C\u6A21\u5F0F",@"default":@"0",@"choices":@[@[@"auto",@"\u6E38\u620F\u9ED8\u8BA4"],@[@"0",@"\u638C\u673A"],@[@"1",@"\u5E95\u5EA7"]]},
        @{@"key":@"DM_PRESENT_ASPECT",@"title":@"\u753B\u9762\u9002\u914D",@"choices":@[@[@"auto",@"\u6E38\u620F\u9ED8\u8BA4"],@[@"fit",@"\u4FDD\u6301\u539F\u6BD4\u4F8B"],@[@"fill",@"\u94FA\u6EE1\u5C4F\u5E55"]]},
        @{@"key":@"DM_TOUCH_SIZE",@"title":@"\u865A\u62DF\u6309\u952E\u5927\u5C0F",@"choices":@[@[@"auto",@"\u6E38\u620F\u9ED8\u8BA4"],@[@"small",@"\u5C0F"],@[@"medium",@"\u4E2D"],@[@"large",@"\u5927"]]},
        @{@"key":@"DM_TOUCH_STICK",@"title":@"\u865A\u62DF\u5DE6\u6447\u6746\u4F4D\u7F6E",@"choices":@[@[@"auto",@"\u6E38\u620F\u9ED8\u8BA4"],@[@"corner",@"\u5DE6\u4E0B"],@[@"higher",@"\u9760\u4E0A"],@[@"inward",@"\u9760\u5185"]]},
        @{@"key":@"DM_PRESENT_UPSCALE",@"title":@"\u753B\u9762\u8D85\u5206",@"default":@"metalfx",@"choices":@[@[@"auto",@"\u6E38\u620F\u9ED8\u8BA4"],@[@"off",@"\u5173\u95ED"],@[@"metalfx",@"MetalFX"]]},
        @{@"key":@"DM_FRAMEGEN",@"title":@"\u753B\u9762\u63D2\u5E27",@"choices":@[@[@"auto",@"\u6E38\u620F\u9ED8\u8BA4"],@[@"off",@"\u5173\u95ED"],@[@"opticalflow",@"\u5B9E\u9A8C\u6027\u5149\u6D41"]]},
        @{@"key":@"DM_SHOW_FPS",@"title":@"\u663E\u793A\u5E27\u7387",@"choices":@[@[@"auto",@"\u6E38\u620F\u9ED8\u8BA4"],@[@"0",@"\u9690\u85CF"],@[@"1",@"\u663E\u793A"]]}
    ];
}
static NSString *libraryPreferenceKey(NSString *key){return [@"tonton.global." stringByAppendingString:key];}
static NSDictionary *librarySetting(NSString *titleID, NSString *key){
    NSString *doc=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString *relative=[NSString stringWithFormat:@"Games/%@/Resources/dm/launcher.json",titleID.lowercaseString];
    NSString *path=[doc stringByAppendingPathComponent:relative];
    if(![NSFileManager.defaultManager fileExistsAtPath:path])
        path=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:[NSString stringWithFormat:@"GameResources/%@/Resources/dm/launcher.json",titleID.lowercaseString]];
    NSData *data=[NSData dataWithContentsOfFile:path];
    NSDictionary *json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    for(NSDictionary *item in [json[@"settings"] isKindOfClass:NSArray.class]?json[@"settings"]:@[])
        if([item[@"env"] isEqual:key])return item;
    return nil;
}
void TonTonApplyGlobalSettings(NSString *titleID){
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    for(NSDictionary *spec in libraryPreferences()){
        NSString *key=spec[@"key"],*choice=[defaults stringForKey:libraryPreferenceKey(key)];
        if(!choice.length)choice=spec[@"default"];
        if(!choice.length||[choice isEqual:@"auto"])continue;
        if([key isEqual:@"DM_FRAME_LIMIT"]){
            // Keep an explicit game pacing profile over the library default.
            // A saved setting for this title still wins below.
            const char *profile=getenv("DM_FRAME_LIMIT");
            if(profile && (!strcmp(profile,"game") || !strcmp(profile,"unlimited")))continue;
            if([choice isEqual:@"unlimited"]||[choice isEqual:@"game"])setenv(key.UTF8String,choice.UTF8String,1);
            continue;
        }
        if([key isEqual:@"DM_PRESENT_ASPECT"]){
            if([choice isEqual:@"fit"]||[choice isEqual:@"fill"])setenv(key.UTF8String,choice.UTF8String,1);
            continue;
        }
        if([@[@"DM_TOUCH_SIZE",@"DM_TOUCH_STICK"] containsObject:key]){
            for(NSArray *option in spec[@"choices"])
                if([option[0] isEqual:choice]){setenv(key.UTF8String,choice.UTF8String,1);break;}
            continue;
        }
        // The native FPS label belongs to the library front end, even when a
        // data-only game import has no per-game launcher schema.
        if([key isEqual:@"DM_SHOW_FPS"]){
            if([choice isEqual:@"0"]||[choice isEqual:@"1"])
                setenv(key.UTF8String,choice.UTF8String,1);
            continue;
        }
        NSDictionary *setting=librarySetting(titleID,key)?:TTNativeGraphicsSetting(titleID,key);
        if(!setting)continue;
        NSArray *options=[setting[@"options"] isKindOfClass:NSArray.class]?setting[@"options"]:@[];
        NSMutableSet<NSString *> *allowed=[NSMutableSet set];
        for(NSArray *option in options)if([option isKindOfClass:NSArray.class]&&option.count&&[option[0] isKindOfClass:NSString.class])[allowed addObject:option[0]];
        NSString *value=choice;
        if([key isEqual:@"DM_LANG"]){
            NSArray *preferred=[choice isEqual:@"chinese"]?@[@"zh-Hans",@"zh-Hant",@"zh-CN",@"zh-TW"]:@[@"en-US",@"en-GB"];
            value=nil;
            for(NSString *candidate in preferred)if([allowed containsObject:candidate]){value=candidate;break;}
        }
        BOOL valid=value.length&&([setting[@"kind"] isEqual:@"toggle"]?
            ([value isEqual:(setting[@"on"]?:@"1")]||[value isEqual:(setting[@"off"]?:@"0")]):
            [allowed containsObject:value]);
        if(valid){setenv(key.UTF8String,value.UTF8String,1);NSLog(@"TonTon global %@=%@ for %@",key,value,titleID);}
    }
    TTApplyGameOverrides(titleID);
    TTApplyTouchLayout(titleID);
    // A profile-owned map remains authoritative, including an empty map.
    if(!librarySetting(titleID,@"DM_PAD_MAP")) {
        NSDictionary *mapping=TTControlMerged(defaults,titleID);
        if(mapping.count)setenv("DM_PAD_MAP",TTControlEnvironment(mapping).UTF8String,1);
    }
}
static void excludeGameResourcesFromBackup(void){
    NSString *doc=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString *root=[doc stringByAppendingPathComponent:@"Games"];
    NSFileManager *fm=NSFileManager.defaultManager;
    for(NSString *name in [fm contentsOfDirectoryAtPath:root error:nil]){
        if([name hasPrefix:@"."])continue;
        for (NSString *generated in @[@"Resources", @"EngineResources"]) {
            NSURL *resources=[NSURL fileURLWithPath:[[root stringByAppendingPathComponent:name] stringByAppendingPathComponent:generated] isDirectory:YES];
            if([fm fileExistsAtPath:resources.path]) [resources setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        }
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
    NSString *preferred=TonTonPreferredGameTitle(title,slot,bundled);
    if(preferred.length)name=preferred;
    NSString *version=[stored[@"version"] isKindOfClass:NSString.class]&&[stored[@"version"] length]?stored[@"version"]:@"\u672C\u5730\u6587\u4EF6";
    NSString *size=[stored[@"size"] isKindOfClass:NSString.class]&&[stored[@"size"] length]?stored[@"size"]:@"\u5DF2\u5BFC\u5165";
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
    NSDictionary *removed=TTDeletedGames(doc,NULL)?:@{};
    for(NSString *title in titles)if(!removed[title])[all addObject:gameCard(title,root,bundled)];
    NSString *incoming=[doc stringByAppendingPathComponent:@"Imports"];
    for(NSString *name in [fm contentsOfDirectoryAtPath:incoming error:nil]){
        if([name hasPrefix:@"."])continue;
        NSString *path=[incoming stringByAppendingPathComponent:name];
        BOOL folder=NO;[fm fileExistsAtPath:path isDirectory:&folder];
        NSDictionary *attrs=[fm attributesOfItemAtPath:path error:nil];
        unsigned long long bytes=[attrs[NSFileSize] unsignedLongLongValue];
        NSString *size=folder?@"\u6E38\u620F\u6587\u4EF6\u5939":[NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleFile];
        [all addObject:@{@"name":name.stringByDeletingPathExtension,@"id":[@"import:" stringByAppendingString:name],@"size":size,@"version":@"\u7B49\u5F85\u8F6C\u6362",@"pending":@YES}];
    }
    [all sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"name"] localizedStandardCompare:b[@"name"]];}];
    return all;
}
static NSString *bundleForGame(NSDictionary *g){return g[@"bundle"] ?: [@"org.nxnative." stringByAppendingString:g[@"id"]];}
static UIImage *coverForGame(NSDictionary *g){
    NSString *title=g[@"id"];
    UIImage *bundled=[UIImage imageNamed:title];
    if(bundled)return bundled;
    NSString *local=[NSBundle.mainBundle pathForResource:title ofType:@"png"];
    if(local){UIImage *image=[UIImage imageWithContentsOfFile:local];if(image)return image;}
    NSString *doc=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString *slot=[[doc stringByAppendingPathComponent:@"Games"] stringByAppendingPathComponent:title];
    NSString *inside=[[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"GameResources"] stringByAppendingPathComponent:title];
    for(NSString *base in @[slot,inside])for(NSString *file in @[@"Cover.png",@"cover.png",@"Icon.png"]){
        UIImage *image=[UIImage imageWithContentsOfFile:[base stringByAppendingPathComponent:file]];
        if(image)return image;
    }
    return nil;
}
static NSSet<NSString *> *availableGames(NSArray<NSDictionary *> *catalog, BOOL publishReport){
#ifdef DM_LIBRARY_HOST
    NSString *doc=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString *root=[doc stringByAppendingPathComponent:@"Games"];
    NSString *bundled=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"GameResources"];
    NSMutableSet<NSString *> *result=[NSMutableSet set];
    NSMutableDictionary *report=[NSMutableDictionary dictionary];
    for(NSDictionary *g in catalog){
        NSDictionary *status=TonTonGameReadiness(g[@"id"],root,bundled);
        report[g[@"id"]]=status;
        if([status[@"ready"] boolValue])[result addObject:bundleForGame(g)];
    }
    // A card-tap check covers one title; retain the full catalogue report.
    if(publishReport){
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"version":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]?:@"",@"games":report} options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:[doc stringByAppendingPathComponent:@"LibraryAvailability.json"] options:NSDataWritingAtomic error:nil];
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
@property(nonatomic,assign)BOOL controllerFocused;
@end
@implementation CoverCard
- (void)setControllerFocused:(BOOL)focused{_controllerFocused=focused;self.layer.borderWidth=focused?3:0;self.layer.borderColor=C(35,132,255).CGColor;self.layer.cornerRadius=12;self.title.textColor=focused?C(35,132,255):UIColor.labelColor;}
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
_caseMark=[UILabel new];_caseMark.text=@"TTG  \u2022  GAME CARD";_caseMark.textColor=C(155,162,171);_caseMark.font=[UIFont systemFontOfSize:8 weight:UIFontWeightBold];_caseMark.adjustsFontSizeToFitWidth=YES;
_contacts=[UILabel new];_contacts.text=@"\u25AE \u25AE \u25AE \u25AE";_contacts.textColor=C(202,165,83);_contacts.font=[UIFont systemFontOfSize:8 weight:UIFontWeightHeavy];
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
- (void)layoutSubviews{[super layoutSubviews];[self.contentView layoutIfNeeded];CGRect b=_caseView.bounds;if(CGRectIsEmpty(b))return;
CGFloat w=b.size.width,h=b.size.height;
UIBezierPath *p=[UIBezierPath bezierPath];[p moveToPoint:CGPointMake(12,0)];
[p addLineToPoint:CGPointMake(w-26,0)];[p addLineToPoint:CGPointMake(w-26,7)];[p addLineToPoint:CGPointMake(w-8,7)];
[p addQuadCurveToPoint:CGPointMake(w,15) controlPoint:CGPointMake(w,7)];[p addLineToPoint:CGPointMake(w,h-13)];
[p addQuadCurveToPoint:CGPointMake(w-13,h) controlPoint:CGPointMake(w,h)];[p addLineToPoint:CGPointMake(13,h)];
[p addQuadCurveToPoint:CGPointMake(0,h-13) controlPoint:CGPointMake(0,h)];[p addLineToPoint:CGPointMake(0,12)];
[p addQuadCurveToPoint:CGPointMake(12,0) controlPoint:CGPointMake(0,0)];[p closePath];
_shellMask.frame=b;_shellMask.path=p.CGPath;_shellEdge.frame=b;_shellEdge.path=p.CGPath;}
@end
// The test polls without replacing handlers or consuming library navigation.
#include "pad_apple.h"
#include "../../Sources/DmControllerPolicy.h"
#include "input_map.h"
@interface TTControllerSettingsView:UITableViewController
@property(nonatomic,copy)NSString *titleID;
@property(nonatomic,strong)NSTimer *testTimer;
@property(nonatomic,strong)UILabel *testLabel;
@end
@implementation TTControllerSettingsView
- (void)viewDidLoad {
    [super viewDidLoad];self.title=self.titleID.length?@"\u672C\u6E38\u620F\u624B\u67C4\u6309\u952E":@"\u5168\u5C40\u624B\u67C4\u6309\u952E";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:self.titleID.length?@"\u7EE7\u627F\u5168\u5C40":@"\u91CD\u7F6E" style:UIBarButtonItemStylePlain target:self action:@selector(resetMapping)];
    self.tableView.rowHeight=54;
    self.testLabel=[[UILabel alloc]initWithFrame:CGRectMake(16,0,300,120)];self.testLabel.numberOfLines=0;self.testLabel.textAlignment=NSTextAlignmentCenter;self.testLabel.font=[UIFont systemFontOfSize:15];
    self.tableView.tableHeaderView=self.testLabel;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];__weak TTControllerSettingsView *weakSelf=self;
    self.testTimer=[NSTimer scheduledTimerWithTimeInterval:1.0/30.0 repeats:YES block:^(__unused NSTimer *timer){[weakSelf pollController];}];[self pollController];
}
- (void)viewDidDisappear:(BOOL)animated {[super viewDidDisappear:animated];[self.testTimer invalidate];self.testTimer=nil;}
- (void)dealloc {[self.testTimer invalidate];}
- (void)resetMapping {[NSUserDefaults.standardUserDefaults removeObjectForKey:TTControlKey(self.titleID)];[self.tableView reloadData];[self pollController];}
- (void)storeButton:(NSString *)button output:(NSString *)output {
    NSMutableDictionary *mapping=[TTControlValidated([NSUserDefaults.standardUserDefaults objectForKey:TTControlKey(self.titleID)]) mutableCopy];
    if(output)mapping[button]=output;else [mapping removeObjectForKey:button];
    [NSUserDefaults.standardUserDefaults setObject:mapping forKey:TTControlKey(self.titleID)];[self.tableView reloadData];[self pollController];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {(void)tableView;(void)section;return TTControlButtons().count+1;}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;(void)section;return @"\u5B9E\u65F6\u6D4B\u8BD5\u663E\u793A\u5F53\u524D\u624B\u67C4\u7684\u8F93\u5165\u53CA\u6620\u5C04\u7ED3\u679C\u3002\u6309\u952E\u540D\u79F0\u6CBF\u7528\u6E38\u620F\u5185\u73B0\u6709\u89C4\u5219\uFF1B\u6447\u6746\u3001\u89E6\u63A7\u3001\u952E\u76D8\u548C\u6E38\u620F\u5217\u8868\u5BFC\u822A\u4E0D\u53D7\u6620\u5C04\u5F71\u54CD\u3002\u66F4\u6539\u5728\u4E0B\u6B21\u542F\u52A8\u6E38\u620F\u65F6\u751F\u6548\u3002";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"controller.mapping"];
    if(!cell)cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"controller.mapping"];
    cell.textLabel.numberOfLines=2;cell.detailTextLabel.numberOfLines=2;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    if(!path.row){cell.textLabel.text=@"\u4EA4\u6362 A / B";cell.detailTextLabel.text=nil;return cell;}
    NSString *button=TTControlButtons()[path.row-1];NSDictionary *own=TTControlValidated([NSUserDefaults.standardUserDefaults objectForKey:TTControlKey(self.titleID)]);
    NSString *value=TTControlMerged(NSUserDefaults.standardUserDefaults,self.titleID)[button]?:button;
    cell.textLabel.text=TTControlLabel(button);cell.detailTextLabel.text=[NSString stringWithFormat:@"%@%@",self.titleID.length&&!own[button]?@"\u7EE7\u627F\uFF1A":@"",TTControlLabel(value)];return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if(!path.row){[self storeButton:@"A" output:@"B"];[self storeButton:@"B" output:@"A"];return;}
    NSString *button=TTControlButtons()[path.row-1];
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:[@"\u6309\u4E0B " stringByAppendingString:TTControlLabel(button)] message:@"\u9009\u62E9\u6E38\u620F\u6536\u5230\u7684\u6309\u952E" preferredStyle:UIAlertControllerStyleAlert];
    if(self.titleID.length)[sheet addAction:[UIAlertAction actionWithTitle:@"\u7EE7\u627F\u5168\u5C40" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self storeButton:button output:nil];}]];
    for(NSString *output in [TTControlButtons() arrayByAddingObject:@"none"])[sheet addAction:[UIAlertAction actionWithTitle:TTControlLabel(output) style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self storeButton:button output:output];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"\u53D6\u6D88" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:sheet animated:YES completion:nil];
}
- (void)pollController {
    if(!self.view.window)return;
    GCController *controller=GCController.current;
    if(![GCController.controllers containsObject:controller]||!controller.extendedGamepad)controller=nil;
    if(!controller)for(GCController *candidate in GCController.controllers)if(candidate.extendedGamepad){controller=candidate;break;}
    GCExtendedGamepad *g=controller.extendedGamepad;
    if(!g){self.testLabel.text=@"\u5B9E\u65F6\u6309\u952E\u6D4B\u8BD5\n\u8FDE\u63A5\u624B\u67C4\u540E\u6309\u4EFB\u610F\u952E";return;}
    uint64_t raw=dm_pad_face(g);
    if(dm_controller_is_backbone(controller.vendorName.UTF8String)||dm_controller_is_backbone(controller.productCategory.UTF8String))raw=dm_controller_face_buttons(g.buttonA.isPressed,g.buttonB.isPressed,g.buttonX.isPressed,g.buttonY.isPressed,1);
    #define TTTEST(input,bit) if(input.isPressed)raw|=bit
    TTTEST(g.leftShoulder,DM_BTN_L);TTTEST(g.rightShoulder,DM_BTN_R);TTTEST(g.leftTrigger,DM_BTN_ZL);TTTEST(g.rightTrigger,DM_BTN_ZR);
    TTTEST(g.buttonMenu,DM_BTN_PLUS);TTTEST(g.buttonOptions,DM_BTN_MINUS);TTTEST(g.leftThumbstickButton,DM_BTN_LS);TTTEST(g.rightThumbstickButton,DM_BTN_RS);
    TTTEST(g.dpad.left,DM_BTN_LEFT);TTTEST(g.dpad.up,DM_BTN_UP);TTTEST(g.dpad.right,DM_BTN_RIGHT);TTTEST(g.dpad.down,DM_BTN_DOWN);
    #undef TTTEST
    pad_map map;pad_map_default(&map);pad_map_parse(&map,TTControlEnvironment(TTControlMerged(NSUserDefaults.standardUserDefaults,self.titleID)).UTF8String);
    uint64_t mapped=pad_map_apply(&map,raw);NSMutableArray *before=[NSMutableArray new],*after=[NSMutableArray new];
    for(NSUInteger index=0;index<TTControlButtons().count;index++){NSString *label=TTControlLabel(TTControlButtons()[index]);if(raw&(1ull<<index))[before addObject:label];if(mapped&(1ull<<index))[after addObject:label];}
    self.testLabel.text=[NSString stringWithFormat:@"%@\n\u8F93\u5165\uFF1A%@\n\u8F93\u51FA\uFF1A%@\n\u5DE6\u6447\u6746 %.2f / %.2f   \u53F3\u6447\u6746 %.2f / %.2f",controller.vendorName?:@"\u624B\u67C4",before.count?[before componentsJoinedByString:@" \uFF0B "]:@"\u2014",after.count?[after componentsJoinedByString:@" \uFF0B "]:@"\u2014",g.leftThumbstick.xAxis.value,g.leftThumbstick.yAxis.value,g.rightThumbstick.xAxis.value,g.rightThumbstick.yAxis.value];
}
@end
static UIViewController *TTControllerSettings(NSString *title) {
    TTControllerSettingsView *view=[[TTControllerSettingsView alloc]initWithStyle:UITableViewStyleInsetGrouped];view.titleID=title;return view;
}

#if defined(DM_LIBRARY_HOST)
@interface TTCloudSavesView : UITableViewController<UIDocumentPickerDelegate>
@end
@implementation TTCloudSavesView
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.title = @"\u5B58\u6863\u540C\u6B65";
    return self;
}
- (NSInteger)tableView:(UITableView *)view numberOfRowsInSection:(NSInteger)section {
    (void)view; (void)section; return 2;
}
- (NSString *)tableView:(UITableView *)view titleForFooterInSection:(NSInteger)section {
    (void)view; (void)section;
    return @"\u5728 iPhone\u3001iPad \u548C Mac \u4E0A\u9009\u540C\u4E00\u4E2A iCloud \u4E91\u76D8\u5171\u4EAB\u6587\u4EF6\u5939\u3002\u539F\u751F\u6E38\u620F\u6309\u6E38\u620F ID \u5206\u5F00\u4FDD\u5B58\uFF0C\u53EA\u540C\u6B65\u6E38\u620F\u5DF2\u4FDD\u5B58\u7684\u8FDB\u5EA6\u3002\u53D1\u751F\u51B2\u7A81\u65F6\uFF0C\u8FD0\u884C\u65F6\u4F1A\u5148\u4FDD\u7559\u88AB\u66FF\u6362\u7684\u5B58\u6863\u3002Apple TV \u548C\u5176\u4ED6\u5F15\u64CE\u7684\u6E38\u620F\u6682\u4E0D\u901A\u8FC7\u6B64\u6587\u4EF6\u5939\u540C\u6B65\u3002";
}
- (UITableViewCell *)tableView:(UITableView *)view cellForRowAtIndexPath:(NSIndexPath *)path {
    (void)view;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    BOOL stale = NO;
    NSString *folder = dm_cloud_saves_path(&stale);
    cell.textLabel.text = path.row ? @"\u5173\u95ED\u6587\u4EF6\u5939\u540C\u6B65" : @"\u9009\u62E9 iCloud \u4E91\u76D8\u6587\u4EF6\u5939";
    cell.detailTextLabel.text = path.row ? @"\u4FDD\u7559\u672C\u5730\u548C\u4E91\u7AEF\u5DF2\u6709\u5B58\u6863" :
        folder.lastPathComponent ?: (stale ? @"\u7B7E\u540D\u5DF2\u53D8\u5316\uFF0C\u8BF7\u91CD\u65B0\u9009\u62E9" : @"\u5C1A\u672A\u9009\u62E9");
    cell.detailTextLabel.numberOfLines = 0;
    cell.accessoryType = path.row ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)view didSelectRowAtIndexPath:(NSIndexPath *)path {
    [view deselectRowAtIndexPath:path animated:YES];
    if (path.row) {
        dm_clear_cloud_saves();
        [view reloadData];
        return;
    }
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)picker;
    NSURL *folder = urls.firstObject;
    if (!folder) return;
    NSString *name = folder.lastPathComponent;
    NSCharacterSet *other = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
    BOOL titleFolder = name.length == 16 && [name rangeOfCharacterFromSet:other].location == NSNotFound;
    if (!titleFolder && dm_store_cloud_saves(folder)) { [self.tableView reloadData]; return; }
    UIAlertController *notice = [UIAlertController alertControllerWithTitle:@"\u65E0\u6CD5\u4F7F\u7528\u8FD9\u4E2A\u6587\u4EF6\u5939"
        message:titleFolder ? @"\u8BF7\u9009\u62E9\u6E38\u620F\u5B58\u6863\u76EE\u5F55\u7684\u4E0A\u4E00\u7EA7\u5171\u4EAB\u6587\u4EF6\u5939\u3002" : @"\u8BF7\u5728 iCloud \u4E91\u76D8\u4E2D\u9009\u62E9\u53EF\u5199\u7684\u6587\u4EF6\u5939\u540E\u91CD\u8BD5\u3002"
        preferredStyle:UIAlertControllerStyleAlert];
    [notice addAction:[UIAlertAction actionWithTitle:@"\u597D" style:UIAlertActionStyleCancel handler:nil]];
    dispatch_async(dispatch_get_main_queue(), ^{ [self presentViewController:notice animated:YES completion:nil]; });
}
@end
#endif
@interface LibrarySettingsView:UITableViewController
@end
static BOOL ttAirPaidCloud(void) { return [NSBundle.mainBundle objectForInfoDictionaryKey:@"DMCloudSaveContainer"] != nil; }
@implementation LibrarySettingsView
- (instancetype)init{self=[super initWithStyle:UITableViewStyleInsetGrouped];if(self)self.title=@"\u5168\u5C40\u8BBE\u7F6E";return self;}
- (void)viewDidLoad{
    [super viewDidLoad];
    self.tableView.backgroundColor=UIColor.systemGroupedBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"\u5B8C\u6210" style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"\u91CD\u7F6E" style:UIBarButtonItemStylePlain target:self action:@selector(resetChoices)];
}
- (void)close{[self dismissViewControllerAnimated:YES completion:nil];}
- (void)resetChoices{for(NSDictionary *spec in libraryPreferences())[NSUserDefaults.standardUserDefaults removeObjectForKey:libraryPreferenceKey(spec[@"key"])];[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{(void)tableView;return 2;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{(void)tableView;if(section!=1)return libraryPreferences().count;
#if defined(DM_LIBRARY_HOST)
    return 2;
#else
    return 1;
#endif
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{
    (void)tableView;if(section==1)return @"\u624B\u67C4\u6309\u952E\u53EF\u4EE5\u5168\u5C40\u914D\u7F6E\uFF0C\u4E5F\u53EF\u4EE5\u5728\u6BCF\u6B3E\u6E38\u620F\u4E2D\u5355\u72EC\u8986\u76D6\u3002";return @"\u8FD9\u4E9B\u8BBE\u7F6E\u4F1A\u5728\u4E0B\u6B21\u6253\u5F00\u6E38\u620F\u65F6\u751F\u6548\u3002\u6E38\u620F\u4E0D\u652F\u6301\u7684\u9009\u9879\u4F1A\u4FDD\u6301\u8BE5\u6E38\u620F\u539F\u6765\u7684\u8BBE\u7F6E\uFF1B\u6E38\u620F\u8BED\u8A00\u4F18\u5148\u4F7F\u7528\u6E38\u620F\u81EA\u5E26\u7684\u4E2D\u6587\u3002\u4E0D\u9650\u5236\u4F1A\u53D6\u6D88\u5BBF\u4E3B\u9650\u5E27\uFF1B\u6E38\u620F\u5185\u7F6E\u9650\u5E27\u4E0E\u56FA\u5B9A\u6B65\u957F\u4ECD\u9700\u9010\u6B3E\u9002\u914D\uFF0C\u5B9E\u9645\u5E27\u7387\u53D6\u51B3\u4E8E\u8BBE\u5907\u6027\u80FD\u3002";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    if(indexPath.section==1){UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];cell.textLabel.text=indexPath.row==0?@"\u624B\u67C4\u6309\u952E\u4E0E\u5B9E\u65F6\u6D4B\u8BD5":(ttAirPaidCloud()?@"iCloud \u5B58\u6863\uFF1A\u81EA\u52A8\u540C\u6B65":@"\u5B58\u6863\u540C\u6B65");cell.accessoryType=(indexPath.row==1&&ttAirPaidCloud())?UITableViewCellAccessoryNone:UITableViewCellAccessoryDisclosureIndicator;return cell;}
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"choice"];
    if(!cell)cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"choice"];
    NSDictionary *spec=libraryPreferences()[indexPath.row];
    NSString *selected=[NSUserDefaults.standardUserDefaults stringForKey:libraryPreferenceKey(spec[@"key"])]?:(spec[@"default"]?:@"auto");
    NSString *label=@"\u6E38\u620F\u9ED8\u8BA4";
    for(NSArray *choice in spec[@"choices"])if([choice[0] isEqual:selected]){label=choice[1];break;}
    cell.textLabel.text=spec[@"title"];cell.detailTextLabel.text=label;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    if(indexPath.section==1){
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
#if defined(DM_LIBRARY_HOST)
        if(indexPath.row==1){if(!ttAirPaidCloud())[self.navigationController pushViewController:[TTCloudSavesView new] animated:YES];return;}
#endif
        [self.navigationController pushViewController:TTControllerSettings(nil) animated:YES];return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *spec=libraryPreferences()[indexPath.row];
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:spec[@"title"] message:nil preferredStyle:UIAlertControllerStyleAlert];
    for(NSArray *choice in spec[@"choices"]){
        [sheet addAction:[UIAlertAction actionWithTitle:choice[1] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
            NSString *key=libraryPreferenceKey(spec[@"key"]);
            if([choice[0] isEqual:@"auto"]&&!spec[@"default"])[NSUserDefaults.standardUserDefaults removeObjectForKey:key];
            else [NSUserDefaults.standardUserDefaults setObject:choice[0] forKey:key];
            [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"\u53D6\u6D88" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}
@end
@interface TTGameSettingsView:UITableViewController
@property(nonatomic,copy)NSString *titleID,*gameName;
@property(nonatomic,copy)NSArray *specs;
@end
@implementation TTGameSettingsView
- (void)viewDidLoad {
    [super viewDidLoad];self.title=self.gameName?:@"\u672C\u6E38\u620F\u8BBE\u7F6E";
    self.specs=TTGameSettingSpecs(self.titleID);
    if(@available(iOS 26.0,*)){}else{NSMutableArray *supported=[NSMutableArray new];for(NSDictionary *spec in self.specs)if(![@[@"DM_PSO_MTL4",@"DM_PSO_PREBUILD",@"DM_FRAMEGEN"] containsObject:spec[@"env"]])[supported addObject:spec];self.specs=supported;}
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"\u5B8C\u6210" style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"\u7EE7\u627F\u5168\u5C40" style:UIBarButtonItemStylePlain target:self action:@selector(resetChoices)];
    self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=56;
}
- (void)close{[self dismissViewControllerAnimated:YES completion:nil];}
- (void)resetChoices {
    for(NSDictionary *spec in self.specs)[NSUserDefaults.standardUserDefaults removeObjectForKey:TTGamePreferenceKey(self.titleID,spec[@"env"])];
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)view{(void)view;return self.titleID.length!=16?1:2;}
- (NSInteger)tableView:(UITableView *)view numberOfRowsInSection:(NSInteger)section{(void)view;return section==1?(librarySetting(self.titleID,@"DM_PAD_MAP")?1:2):self.specs.count;}
- (NSString *)tableView:(UITableView *)view titleForFooterInSection:(NSInteger)section {
    (void)view;(void)section;
    if(section==1)return @"\u865A\u62DF\u5E03\u5C40\u53EA\u5F71\u54CD\u8FD9\u6B3E\u6E38\u620F\uFF1B\u6CA1\u6539\u8FC7\u7684\u6E38\u620F\u4F7F\u7528\u81EA\u5DF1\u7684\u9ED8\u8BA4\u5E03\u5C40\u3002";
    if(!self.specs.count)return @"\u8FD9\u6B3E\u6E38\u620F\u8BF7\u4F7F\u7528\u6E38\u620F\u5185\u7684\u8BBE\u7F6E\u83DC\u5355\u3002";
    return @"\u53EA\u4FEE\u6539\u8FD9\u6B3E\u6E38\u620F\uFF0C\u4E0B\u6B21\u542F\u52A8\u751F\u6548\u3002\u672A\u5355\u72EC\u4FEE\u6539\u7684\u9009\u9879\u7EE7\u627F\u5168\u5C40\u8BBE\u7F6E\uFF1B\u201C\u6E38\u620F\u9ED8\u8BA4\u201D\u4F7F\u7528\u8FD9\u6B3E\u6E38\u620F\u7684\u9ED8\u8BA4\u503C\u3002\u66F4\u9AD8\u753B\u8D28\u4E0E\u5206\u8FA8\u7387\u4F1A\u589E\u52A0\u5185\u5B58\u548C\u53D1\u70ED\u3002";
}
- (UITableViewCell *)tableView:(UITableView *)view cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if(indexPath.section==1){UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];cell.textLabel.text=indexPath.row==0?@"\u672C\u6E38\u620F\u865A\u62DF\u624B\u67C4\u5E03\u5C40":@"\u672C\u6E38\u620F\u624B\u67C4\u6309\u952E\u4E0E\u5B9E\u65F6\u6D4B\u8BD5";cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;}
    UITableViewCell *cell=[view dequeueReusableCellWithIdentifier:@"game.setting"];
    if(!cell)cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"game.setting"];
    NSDictionary *spec=self.specs[indexPath.row];
    NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:TTGamePreferenceKey(self.titleID,spec[@"env"])];
    cell.textLabel.text=TTSettingTitle(spec);cell.textLabel.numberOfLines=2;
    cell.detailTextLabel.text=[saved isEqual:@"__defaults__"]?@"\u6E38\u620F\u9ED8\u8BA4":TTSettingAccepts(spec,saved)?TTSettingValueLabel(spec,saved):@"\u7EE7\u627F\u5168\u5C40";
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;
}
- (void)store:(NSString *)value spec:(NSDictionary *)spec {
    NSString *key=TTGamePreferenceKey(self.titleID,spec[@"env"]);
    if(!value)[NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    else if([value isEqual:@"__defaults__"]||TTSettingAccepts(spec,value))[NSUserDefaults.standardUserDefaults setObject:value forKey:key];
    [self.tableView reloadData];
}
- (void)tableView:(UITableView *)view didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if(indexPath.section==1){[view deselectRowAtIndexPath:indexPath animated:YES];[self.navigationController pushViewController:indexPath.row==0?[[TTPadLayoutEditor alloc] initWithTitleID:self.titleID]:TTControllerSettings(self.titleID) animated:YES];return;}
    [view deselectRowAtIndexPath:indexPath animated:YES];NSDictionary *spec=self.specs[indexPath.row];
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:TTSettingTitle(spec) message:nil preferredStyle:UIAlertControllerStyleAlert];
    [sheet addAction:[UIAlertAction actionWithTitle:@"\u7EE7\u627F\u5168\u5C40\u8BBE\u7F6E" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){[self store:nil spec:spec];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:[@"\u6E38\u620F\u9ED8\u8BA4\uFF1A" stringByAppendingString:TTSettingValueLabel(spec,spec[@"default"])] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){[self store:@"__defaults__" spec:spec];}]];
    if([spec[@"kind"] isEqual:@"range"]){
        sheet.message=[NSString stringWithFormat:@"\u8F93\u5165 %.0f%% \u81F3 %.0f%%\uFF0C\u6BCF\u6863 %.0f%%",[spec[@"min"] doubleValue]*100,[spec[@"max"] doubleValue]*100,[spec[@"step"] doubleValue]*100];
        [sheet addTextFieldWithConfigurationHandler:^(UITextField *field){field.keyboardType=UIKeyboardTypeDecimalPad;field.placeholder=@"\u767E\u5206\u6BD4\uFF0C\u4F8B\u5982 100";}];
        __weak UIAlertController *weakSheet=sheet;
        [sheet addAction:[UIAlertAction actionWithTitle:@"\u4FDD\u5B58\u767E\u5206\u6BD4" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
            NSString *text=weakSheet.textFields.firstObject.text;NSScanner *scan=[NSScanner scannerWithString:text?:@""];double number;
            NSString *value=[scan scanDouble:&number]&&scan.isAtEnd?[NSString stringWithFormat:@"%.8g",number/100]:nil;
            if(TTSettingAccepts(spec,value)){[self store:value spec:spec];return;}
            UIAlertController *error=[UIAlertController alertControllerWithTitle:@"\u6570\u503C\u65E0\u6548" message:@"\u8BF7\u8F93\u5165\u8303\u56F4\u5185\u4E14\u7B26\u5408\u6863\u4F4D\u7684\u767E\u5206\u6BD4\u3002" preferredStyle:UIAlertControllerStyleAlert];
            [error addAction:[UIAlertAction actionWithTitle:@"\u597D" style:UIAlertActionStyleCancel handler:nil]];
            dispatch_async(dispatch_get_main_queue(),^{[self presentViewController:error animated:YES completion:nil];});
        }]];
    }else{
        NSArray *choices=[spec[@"kind"] isEqual:@"toggle"]?@[@[spec[@"on"]?:@"1",@"\u5F00\u542F"],@[spec[@"off"]?:@"0",@"\u5173\u95ED"]]:spec[@"options"];
        for(NSArray *option in choices)[sheet addAction:[UIAlertAction actionWithTitle:TTSettingValueLabel(spec,option[0]) style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){[self store:option[0] spec:spec];}]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"\u53D6\u6D88" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}
@end
UIViewController *TonTonGameSettingsController(NSString *titleID,NSString *name){
    TTGameSettingsView *settings=[[TTGameSettingsView alloc]initWithStyle:UITableViewStyleInsetGrouped];settings.titleID=titleID.lowercaseString;settings.gameName=name;
    UINavigationController *navigation=[[UINavigationController alloc]initWithRootViewController:settings];navigation.modalPresentationStyle=UIModalPresentationPageSheet;return navigation;
}

@interface LibraryView:UIViewController<UICollectionViewDataSource,UICollectionViewDelegateFlowLayout,UIDocumentPickerDelegate>
@property(nonatomic,strong)UICollectionView *grid;
@property(nonatomic,strong)UILabel *status,*countLabel;
@property(nonatomic,strong)NSSet<NSString *> *installed;
@property(nonatomic,copy)NSArray<NSDictionary *> *catalog;
@property(nonatomic,assign)CGSize lastGridSize;
@property(nonatomic,assign)BOOL refreshInProgress;
@property(nonatomic,assign)BOOL removalInProgress;
@property(nonatomic,strong)NSTimer *resourceRefreshTimer;
@property(nonatomic,strong)NSTimer *controllerTimer;
@property(nonatomic,strong)GCController *menuController;
@property(nonatomic,strong)UILabel *controllerHintLabel;
@property(nonatomic,assign)TTMenuInput menuInput;
@property(nonatomic,assign)NSUInteger controllerIndex;
@property(nonatomic,copy)NSString *controllerTitleID;
@property(nonatomic,copy)void (^startGame)(NSString *titleID);
@end
@implementation LibraryView
// Called only with a live security scope on the old library's Games folder.
- (void)ttMigrateGamesFrom:(NSURL *)source {
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    if (!documents.length) { [source stopAccessingSecurityScopedResource]; return; }
    NSString *destination=[documents stringByAppendingPathComponent:@"Games"];
    NSString *receipt=[documents stringByAppendingPathComponent:@"TonTonMigrationReceipt.json"];
    self.status.text=@"\u6B63\u5728\u79FB\u52A8\u65E7\u6E38\u620F\u4E0E\u5B58\u6863\u2026";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSFileManager *fm=NSFileManager.defaultManager;
        NSMutableArray *moved=[NSMutableArray array], *held=[NSMutableArray array];
        NSError *coordError=nil;
        NSFileCoordinator *coord=[[NSFileCoordinator alloc]initWithFilePresenter:nil];
        [coord coordinateWritingItemAtURL:source options:NSFileCoordinatorWritingForMoving
            error:&coordError byAccessor:^(NSURL *old) {
            struct stat a,b;
            if (lstat(old.fileSystemRepresentation,&a) || !S_ISDIR(a.st_mode) ||
                ![fm createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:nil] ||
                lstat(destination.fileSystemRepresentation,&b) || !S_ISDIR(b.st_mode) ||
                a.st_dev!=b.st_dev || a.st_ino==b.st_ino) {
                [held addObject:@{@"name":@"Games",@"reason":@"source_not_distinct_local_directory"}]; return;
            }
            NSError *listingError=nil;
            NSArray<NSString *> *names=[fm contentsOfDirectoryAtPath:old.path error:&listingError];
            if (!names) { [held addObject:@{@"name":@"Games",@"reason":listingError.localizedDescription?:@"list_failed"}]; return; }
            for (NSString *title in [names sortedArrayUsingSelector:@selector(compare:)]) {
                BOOL native=[@[@"gta5",@"redalert2",@"yurisrevenge"] containsObject:title];
                if (!native && [title rangeOfString:@"^[0-9a-fA-F]{16}$" options:NSRegularExpressionSearch].location==NSNotFound) continue;
                NSURL *from=[old URLByAppendingPathComponent:title isDirectory:YES];
                NSURL *to=[NSURL fileURLWithPath:[destination stringByAppendingPathComponent:title.lowercaseString] isDirectory:YES];
                struct stat original,after;
                if (lstat(from.fileSystemRepresentation,&original) || !S_ISDIR(original.st_mode) || original.st_dev!=b.st_dev) {
                    [held addObject:@{@"name":title,@"reason":@"invalid_source"}]; continue;
                }
                if (renamex_np(from.fileSystemRepresentation,to.fileSystemRepresentation,RENAME_EXCL)) {
                    int reason=errno;
                    [held addObject:@{@"name":title,@"reason":@(reason)}]; continue;
                }
                BOOL same=!lstat(to.fileSystemRepresentation,&after) &&
                    original.st_dev==after.st_dev && original.st_ino==after.st_ino;
                [coord itemAtURL:from didMoveToURL:to];
                [moved addObject:@{@"name":title,@"same_file_identity":@(same)}];
                if (!same) break;
            }
        }];
        [source stopAccessingSecurityScopedResource];
        if (coordError) [held addObject:@{@"name":@"Games",@"reason":coordError.localizedDescription}];
        NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"moved":moved,@"held":held,@"date":@([NSDate date].timeIntervalSince1970)} options:NSJSONWritingPrettyPrinted error:nil];
        [json writeToFile:receipt atomically:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self refresh];
            [self showNotice:@"\u65E7\u6E38\u620F\u5323\u8FC1\u79FB" detail:[NSString stringWithFormat:@"\u5DF2\u79FB\u52A8 %lu \u9879\uFF0C\u4FDD\u7559\u5F85\u5904\u7406 %lu \u9879\u3002\u9047\u5230\u540C\u540D\u9879\u76EE\u65F6\u4E0D\u4F1A\u8986\u76D6\u3002",(unsigned long)moved.count,(unsigned long)held.count]];
        });
    });
}


- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone ? UIInterfaceOrientationMaskAllButUpsideDown : UIInterfaceOrientationMaskLandscape;
}
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone ? UIInterfaceOrientationPortrait : UIInterfaceOrientationLandscapeRight;
}
- (void)viewDidLoad{[super viewDidLoad];self.view.backgroundColor=D(242,240,235,16,19,24);self.installed=[NSSet set];
UIView *header=[UIView new];header.backgroundColor=D(255,255,252,31,37,45);header.layer.cornerRadius=24;header.layer.borderWidth=1;header.layer.borderColor=C(190,194,197).CGColor;
UIView *red=[UIView new];red.backgroundColor=C(224,49,54);red.layer.cornerRadius=4;
UILabel *eyebrow=[UILabel new];eyebrow.text=@"T O N T O N   /   G A M E   C A R D S";eyebrow.textColor=C(203,54,59);eyebrow.font=[UIFont systemFontOfSize:10 weight:UIFontWeightHeavy];
UILabel *title=[UILabel new];title.text=@"TonTon\u6E38\u620F\u5323";title.textColor=UIColor.labelColor;title.font=[UIFont systemFontOfSize:32 weight:UIFontWeightHeavy];
UILabel *sub=[UILabel new];self.controllerHintLabel=sub;sub.text=@"\u957F\u6309\u5361\u5E26\u53EF\u8BBE\u7F6E\u6216\u5220\u9664";sub.textColor=UIColor.secondaryLabelColor;sub.font=[UIFont systemFontOfSize:14];
UILabel *count=[UILabel new];count.text=@"\u2014\n\u6B3E\u5361\u5E26";count.numberOfLines=2;count.textAlignment=NSTextAlignmentCenter;count.textColor=UIColor.labelColor;count.font=[UIFont systemFontOfSize:15 weight:UIFontWeightBold];count.backgroundColor=D(238,239,238,45,51,59);count.layer.cornerRadius=14;count.layer.masksToBounds=YES;self.countLabel=count;
_status=[UILabel new];_status.text=@"\u6B63\u5728\u8BFB\u53D6\u5361\u5E26\u2026";_status.textColor=UIColor.secondaryLabelColor;_status.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
UIButton *add=[UIButton buttonWithType:UIButtonTypeSystem];UIImageSymbolConfiguration *cfg=[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightSemibold];[add setImage:[UIImage systemImageNamed:@"plus" withConfiguration:cfg] forState:UIControlStateNormal];add.imageView.contentMode=UIViewContentModeCenter;add.accessibilityLabel=@"\u6DFB\u52A0 Switch \u6E38\u620F";add.tintColor=UIColor.whiteColor;add.backgroundColor=C(218,50,56);add.layer.cornerRadius=27;add.layer.shadowColor=UIColor.blackColor.CGColor;add.layer.shadowOpacity=0.25;add.layer.shadowRadius=10;add.layer.shadowOffset=CGSizeMake(0,5);[add addTarget:self action:@selector(addGame) forControlEvents:UIControlEventTouchUpInside];
UIButton *settingsButton=[UIButton buttonWithType:UIButtonTypeSystem];
[settingsButton setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
settingsButton.accessibilityLabel=@"\u5168\u5C40\u8BBE\u7F6E";settingsButton.tintColor=UIColor.labelColor;
[settingsButton addTarget:self action:@selector(showSettings) forControlEvents:UIControlEventTouchUpInside];
UICollectionViewFlowLayout *flow=[UICollectionViewFlowLayout new];flow.minimumInteritemSpacing=15;flow.minimumLineSpacing=10;flow.sectionInset=UIEdgeInsetsMake(4,0,68,0);
_grid=[[UICollectionView alloc]initWithFrame:CGRectZero collectionViewLayout:flow];_grid.backgroundColor=UIColor.clearColor;_grid.dataSource=self;_grid.delegate=self;[_grid registerClass:CoverCard.class forCellWithReuseIdentifier:@"card"];
for(UIView *v in @[header,_status,_grid,add]){v.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:v];}
for(UIView *v in @[red,eyebrow,title,sub,count,settingsButton]){v.translatesAutoresizingMaskIntoConstraints=NO;[header addSubview:v];}
UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
[NSLayoutConstraint activateConstraints:@[[header.topAnchor constraintEqualToAnchor:safe.topAnchor constant:6],[header.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:18],[header.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-18],[header.heightAnchor constraintEqualToConstant:86],
[red.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:18],[red.topAnchor constraintEqualToAnchor:header.topAnchor constant:14],[red.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-14],[red.widthAnchor constraintEqualToConstant:5],
[eyebrow.topAnchor constraintEqualToAnchor:header.topAnchor constant:11],[eyebrow.leadingAnchor constraintEqualToAnchor:red.trailingAnchor constant:14],
[title.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:3],[title.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],[title.trailingAnchor constraintLessThanOrEqualToAnchor:settingsButton.leadingAnchor constant:-8],
[sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:1],[sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
[settingsButton.trailingAnchor constraintEqualToAnchor:count.leadingAnchor constant:-5],[settingsButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],[settingsButton.widthAnchor constraintEqualToConstant:40],[settingsButton.heightAnchor constraintEqualToConstant:44],
[count.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-17],[count.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],[count.widthAnchor constraintEqualToConstant:68],[count.heightAnchor constraintEqualToConstant:62],
[_status.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],[_status.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:4],
[_grid.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:7],[_grid.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:18],[_grid.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-18],[_grid.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
[add.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-22],[add.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],[add.widthAnchor constraintEqualToConstant:54],[add.heightAnchor constraintEqualToConstant:54]]];[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:UIApplicationDidBecomeActiveNotification object:nil];[self refresh];}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];if(!CGSizeEqualToSize(self.lastGridSize,self.grid.bounds.size)){self.lastGridSize=self.grid.bounds.size;[self.grid.collectionViewLayout invalidateLayout];}}
- (void)updateControllerSelection {
    NSArray *catalog=self.displayGames;
    NSUInteger index=NSNotFound;
    if(self.controllerTitleID.length)for(NSUInteger i=0;i<catalog.count;i++)if([catalog[i][@"id"] isEqual:self.controllerTitleID]){index=i;break;}
    if(index==NSNotFound&&catalog.count)index=self.controllerIndex==NSNotFound?0:MIN(self.controllerIndex,catalog.count-1);
    self.controllerIndex=index;
    self.controllerTitleID=index!=NSNotFound?catalog[index][@"id"]:nil;
    for(NSIndexPath *path in self.grid.indexPathsForVisibleItems){
        CoverCard *card=(CoverCard *)[self.grid cellForItemAtIndexPath:path];
        card.controllerFocused=self.menuController!=nil&&path.item==index;
    }
}
- (void)pollMenuController {
    if(!self.view.window||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||self.presentedViewController||self.removalInProgress){self.menuInput=(TTMenuInput){0};return;}
    NSArray<GCController *> *controllers=GCController.controllers;
    GCController *controller=GCController.current;
    if(![controllers containsObject:controller]||(!controller.extendedGamepad&&!controller.microGamepad))controller=nil;
    if(!controller&&[controllers containsObject:self.menuController])controller=self.menuController;
    if(!controller)for(GCController *candidate in controllers)if(candidate.extendedGamepad||candidate.microGamepad){controller=candidate;break;}
    if(controller!=self.menuController){
        self.menuController=controller;self.menuInput=(TTMenuInput){0};
        self.controllerHintLabel.text=controller?@"\u65B9\u5411\u952E/\u5DE6\u6447\u6746\u9009\u62E9 \u00B7 A\u6253\u5F00 \u00B7 X\u8BBE\u7F6E":@"\u957F\u6309\u5361\u5E26\u53EF\u8BBE\u7F6E\u6216\u5220\u9664";
        NSLog(@"TonTon library controller %@",controller?@"connected":@"disconnected");
        [self updateControllerSelection];
    }
    if(!controller)return;
    float dx=0,dy=0,sx=0,sy=0;unsigned buttons=0;
    GCExtendedGamepad *pad=controller.extendedGamepad;
    if(pad){
        dx=pad.dpad.xAxis.value;dy=pad.dpad.yAxis.value;sx=pad.leftThumbstick.xAxis.value;sy=pad.leftThumbstick.yAxis.value;
        if(pad.buttonA.isPressed)buttons|=TTMenuOpen;
        if(pad.buttonX.isPressed)buttons|=TTMenuSettings;
    }else{
        GCMicroGamepad *micro=controller.microGamepad;dx=micro.dpad.xAxis.value;dy=micro.dpad.yAxis.value;
        if(micro.buttonA.isPressed)buttons|=TTMenuOpen;
        if(micro.buttonX.isPressed)buttons|=TTMenuSettings;
    }
    TTMenuInput input=self.menuInput;
    TTMenuDirection direction=TTMenuReadDirection(dx,dy,sx,sy,input.direction);
    TTMenuEvent event=TTMenuStep(&input,direction,buttons,NSProcessInfo.processInfo.systemUptime);self.menuInput=input;
    [self updateControllerSelection];
    if(!self.displayGames.count)return;
    if(event.move!=TTMenuNone){
        [self.grid layoutIfNeeded];NSUInteger count=self.displayGames.count;TTMenuPoint points[count];
        for(NSUInteger i=0;i<count;i++){
            UICollectionViewLayoutAttributes *a=[self.grid.collectionViewLayout layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]];
            if(!a)return;points[i]=(TTMenuPoint){a.center.x,a.center.y};
        }
        self.controllerIndex=TTMenuNavigate(points,count,self.controllerIndex,event.move);
        self.controllerTitleID=self.displayGames[self.controllerIndex][@"id"];[self updateControllerSelection];
        [self.grid scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:self.controllerIndex inSection:0] atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:YES];
    }
    NSIndexPath *path=[NSIndexPath indexPathForItem:self.controllerIndex inSection:0];NSDictionary *game=self.displayGames[path.item];
    // Poll only while the library is visible; never replace the game's handlers.
    if(event.pressed&TTMenuSettings){
        if(![game[@"id"] hasPrefix:@"import:"])[self presentViewController:TonTonGameSettingsController(game[@"id"],game[@"name"]) animated:YES completion:nil];
    }else if(event.pressed&TTMenuOpen){
        [self collectionView:self.grid didSelectItemAtIndexPath:path];
    }
}

- (void)showNotice:(NSString *)title detail:(NSString *)detail{UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"\u597D" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)showSettings{if(self.presentedViewController)return;UINavigationController *nav=[[UINavigationController alloc]initWithRootViewController:[LibrarySettingsView new]];nav.modalPresentationStyle=UIModalPresentationPageSheet;[self presentViewController:nav animated:YES completion:nil];}
- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)view contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    (void)view;(void)point;NSDictionary *game=self.displayGames[indexPath.item];
    return [UIContextMenuConfiguration configurationWithIdentifier:game[@"id"] previewProvider:nil actionProvider:^UIMenu *(NSArray *suggested){
        (void)suggested;UIAction *settings=[UIAction actionWithTitle:@"\u672C\u6E38\u620F\u8BBE\u7F6E" image:[UIImage systemImageNamed:@"slider.horizontal.3"] identifier:nil handler:^(__unused UIAction *action){
            if(!self.presentedViewController)[self presentViewController:TonTonGameSettingsController(game[@"id"],game[@"name"]) animated:YES completion:nil];
        }];
        UIAction *remove=[UIAction actionWithTitle:@"\u5220\u9664\u6E38\u620F" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(__unused UIAction *action){[self confirmDeleteGame:game];}];remove.attributes=UIMenuElementAttributesDestructive;
        NSArray *items=[game[@"id"] hasPrefix:@"import:"]?@[remove]:@[settings,remove];
        return [UIMenu menuWithTitle:game[@"name"] children:items];
    }];
}
- (void)confirmDeleteGame:(NSDictionary *)game {
    if(self.presentedViewController||self.removalInProgress)return;
    NSString *title=game[@"id"],*name=game[@"name"];BOOL pending=[title hasPrefix:@"import:"];
    NSString *detail=pending?@"\u5C06\u5220\u9664\u6E38\u620F\u5323\u5185\u8FD9\u4E2A\u5C1A\u672A\u8F6C\u6362\u7684\u5B89\u88C5\u6587\u4EF6\u3002":@"\u5220\u9664\u6B64\u6E38\u620F\u7684\u72EC\u7ACB\u8D44\u6E90\u548C\u5BFC\u5165\u5206\u5757\uFF0C\u4FDD\u7559\u5B58\u6863\u3001\u4E2A\u4EBA\u8BBE\u7F6E\u3001\u539F\u59CB\u5B89\u88C5\u6587\u4EF6\u548C\u5171\u7528\u8D44\u6E90\u3002\u4EE5\u540E\u53EF\u4ECE\u53F3\u4E0B\u89D2\u201C\u6DFB\u52A0\u201D\u6062\u590D\u5361\u7247\u3002";
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"\u5220\u9664\u300A%@\u300B\uFF1F",name] message:detail preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53D6\u6D88" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u5220\u9664\u6E38\u620F" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){
        self.removalInProgress=YES;self.view.userInteractionEnabled=NO;self.status.text=@"\u6B63\u5728\u5220\u9664\u6E38\u620F\u8D44\u6E90\uFF0C\u5B58\u6863\u4F1A\u4FDD\u7559\u2026";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            NSString *doc=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;NSError *error=nil;BOOL ok=NO;
            if(pending){NSString *file=[title substringFromIndex:7];
                if(file.length&&[file isEqual:file.lastPathComponent]&&![file isEqual:@"."]&&![file isEqual:@".."])@synchronized(TTGameDataGuard()){ok=TTRemoveRelative(doc,[@"Imports" stringByAppendingPathComponent:file],&error);}
            }else ok=TTDeleteGame(doc,title,name,&error);
            dispatch_async(dispatch_get_main_queue(),^{
                self.removalInProgress=NO;self.view.userInteractionEnabled=YES;self.catalog=games();[self.grid reloadData];self.refreshInProgress=NO;[self refresh];TonTonWriteStorageStatus();
                if(!ok)[self showNotice:@"\u5220\u9664\u672A\u5B8C\u6210" detail:error.localizedDescription?:@"\u539F\u6570\u636E\u5DF2\u4FDD\u7559\uFF0C\u8BF7\u7A0D\u540E\u518D\u8BD5\u3002"];
            });
        });
    }]];[self presentViewController:alert animated:YES completion:nil];
}
- (void)showRemovedGames {
    NSString *doc=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;NSDictionary *records=TTDeletedGames(doc,NULL);
    if(!records.count)return;
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"\u6062\u590D\u5DF2\u5220\u9664\u7684\u5361\u7247" message:@"\u5B58\u6863\u548C\u4E2A\u4EBA\u8BBE\u7F6E\u4F1A\u7EE7\u7EED\u4FDD\u7559\u3002\u5DF2\u5220\u9664\u7684\u6E38\u620F\u8D44\u6E90\u9700\u8981\u91CD\u65B0\u5BFC\u5165\u3002" preferredStyle:UIAlertControllerStyleActionSheet];
    for(NSString *title in [[records allKeys] sortedArrayUsingSelector:@selector(compare:)]){
        NSString *name=[records[title][@"name"] isKindOfClass:NSString.class]?records[title][@"name"]:title;
        [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){NSError *error=nil;if(!TTRestoreGameCard(doc,title,&error))[self showNotice:@"\u65E0\u6CD5\u6062\u590D\u5361\u7247" detail:error.localizedDescription];else [self refresh];}]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"\u53D6\u6D88" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView=self.view;sheet.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width-50,self.view.bounds.size.height-40,1,1);
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)addGame {
    if(self.presentedViewController||self.removalInProgress)return;
    NSString *doc=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    if(!TTDeletedGames(doc,NULL).count){[self chooseGameFile];return;}
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"\u6DFB\u52A0\u6E38\u620F" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"\u6DFB\u52A0\u6E38\u620F\u6587\u4EF6" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self chooseGameFile];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"\u6062\u590D\u5DF2\u5220\u9664\u7684\u5361\u7247" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self showRemovedGames];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"\u53D6\u6D88" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView=self.view;sheet.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width-50,self.view.bounds.size.height-40,1,1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)chooseGameFile{
    if(self.presentedViewController)return;
    self.status.text=@"\u6B63\u5728\u6253\u5F00\u6587\u4EF6\u9009\u62E9\u5668\u2026";
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypeFolder,UTTypeData] asCopy:NO];
    picker.delegate=self;picker.allowsMultipleSelection=NO;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)picker{(void)picker;[self refresh];}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
    (void)picker;NSURL *source=urls.firstObject;if(!source)return;
    BOOL scoped=[source startAccessingSecurityScopedResource];
    NSString *name=source.lastPathComponent;
    if(ttAirPaidCloud() && scoped && [name isEqualToString:@"Games"]){ [self ttMigrateGamesFrom:source]; return; }
    BOOL folder=NO;[NSFileManager.defaultManager fileExistsAtPath:source.path isDirectory:&folder];
    NSString *ext=name.pathExtension.lowercaseString;
    if(!folder && ![@[@"nsp",@"xci",@"nsz",@"nca"] containsObject:ext]){
        if(scoped)[source stopAccessingSecurityScopedResource];
        [self showNotice:@"\u65E0\u6CD5\u6DFB\u52A0" detail:@"\u8BF7\u9009\u62E9 Switch \u6E38\u620F\u6587\u4EF6\uFF08NSP\u3001XCI\u3001NSZ\uFF09\u6216\u6E38\u620F\u6587\u4EF6\u5939\u3002"];return;
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
        [self showNotice:@"\u5DF2\u5B58\u5728" detail:@"\u6E38\u620F\u5323\u91CC\u5DF2\u6709\u540C\u540D\u6587\u4EF6\uFF1B\u6CA1\u6709\u8986\u76D6\u539F\u6570\u636E\u3002"];return;
    }
    __block NSString *failure=nil;__block BOOL moved=NO;
    NSURL *target=[NSURL fileURLWithPath:destination];
    NSFileCoordinator *coordinator=[[NSFileCoordinator alloc]initWithFilePresenter:nil];NSError *coordinateError=nil;
    [coordinator coordinateWritingItemAtURL:source options:NSFileCoordinatorWritingForMoving error:&coordinateError byAccessor:^(NSURL *coordinated){
        struct stat a,b,c;
        if(stat(coordinated.fileSystemRepresentation,&a)||stat(target.URLByDeletingLastPathComponent.fileSystemRepresentation,&b)){
            failure=@"\u65E0\u6CD5\u8BFB\u53D6\u6587\u4EF6\u6216\u76EE\u6807\u76EE\u5F55\u3002";return;
        }
        if(a.st_dev!=b.st_dev){failure=@"\u6587\u4EF6\u548C\u6E38\u620F\u5323\u4E0D\u5728\u540C\u4E00\u4E2A\u78C1\u76D8\uFF1B\u8BF7\u5148\u79FB\u5230\u201C\u6211\u7684 iPad\u201D\u540E\u518D\u6DFB\u52A0\u3002";return;}
        if(rename(coordinated.fileSystemRepresentation,target.fileSystemRepresentation)){
            failure=[NSString stringWithFormat:@"\u79FB\u52A8\u5931\u8D25\uFF08%s\uFF09\u3002\u539F\u6587\u4EF6\u4ECD\u4FDD\u7559\u3002",strerror(errno)];return;
        }
        if(stat(target.fileSystemRepresentation,&c)||c.st_dev!=a.st_dev||c.st_ino!=a.st_ino){
            failure=@"\u79FB\u52A8\u540E\u7684\u6587\u4EF6\u8EAB\u4EFD\u672A\u901A\u8FC7\u6838\u5BF9\uFF0C\u8BF7\u4E0D\u8981\u91CD\u590D\u5BFC\u5165\u3002";return;
        }
        [coordinator itemAtURL:coordinated didMoveToURL:target];moved=YES;
    }];
    if(scoped)[source stopAccessingSecurityScopedResource];
    if(coordinateError && !failure)failure=coordinateError.localizedDescription;
    if(!moved){[self showNotice:@"\u65E0\u6CD5\u6DFB\u52A0" detail:failure?:@"\u6587\u4EF6\u5C1A\u672A\u79FB\u52A8\uFF0C\u8BF7\u518D\u8BD5\u4E00\u6B21\u3002"];return;}
    [self refresh];
    [self showNotice:prepared?@"\u5361\u5E26\u5DF2\u52A0\u5165":@"\u6587\u4EF6\u5DF2\u52A0\u5165\u6E38\u620F\u5323" detail:prepared?@"\u53EF\u4EE5\u4ECE\u5361\u5E26\u5C01\u9762\u6253\u5F00\u3002":@"\u6587\u4EF6\u5DF2\u76F4\u63A5\u79FB\u52A8\u5230\u6E38\u620F\u5323\u3002\u8F6C\u6362\u7A0B\u5E8F\u5B8C\u6210\u540E\uFF0C\u8FD9\u5F20\u5361\u5E26\u624D\u80FD\u542F\u52A8\u3002"];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    __weak LibraryView *weakSelf=self;
    self.menuInput=(TTMenuInput){0};
    self.controllerTimer=[NSTimer scheduledTimerWithTimeInterval:1.0/30.0 repeats:YES block:^(__unused NSTimer *timer){[weakSelf pollMenuController];}];
    [self pollMenuController];
    self.resourceRefreshTimer=[NSTimer scheduledTimerWithTimeInterval:20 repeats:YES block:^(NSTimer *timer){
        (void)timer; LibraryView *owner=weakSelf;
        if(owner.view.window && UIApplication.sharedApplication.applicationState==UIApplicationStateActive)[owner refresh];
    }];
    [self refresh];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.controllerTimer invalidate];self.controllerTimer=nil;self.menuInput=(TTMenuInput){0};
    [self.resourceRefreshTimer invalidate];self.resourceRefreshTimer=nil;
}
- (void)dealloc {
    [self.controllerTimer invalidate];
    [self.resourceRefreshTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}
- (void)publishCatalogWhileImporting:(BOOL)importing {
    // Called on the import queue. Publish current cards before a large image
    // assembly, and again after each receipt, rather than hiding the catalogue.
    NSArray *catalog=games();NSSet *ids=availableGames(catalog,YES);
    dispatch_async(dispatch_get_main_queue(),^{
        self.catalog=catalog;self.installed=ids;
        NSUInteger playable=0;for(NSDictionary *g in catalog)if([ids containsObject:bundleForGame(g)])playable++;
        self.countLabel.text=[NSString stringWithFormat:@"%02lu\n\u6B3E\u5361\u5E26",(unsigned long)catalog.count];
        NSString *summary=catalog.count?[NSString stringWithFormat:@"%lu \u6B3E\u5DF2\u6536\u5F55 \u00B7 %lu \u6B3E\u53EF\u6253\u5F00",(unsigned long)catalog.count,(unsigned long)playable]:@"\u70B9\u53F3\u4E0B\u89D2\u6DFB\u52A0\u6E38\u620F";
        self.status.text=importing?[summary stringByAppendingString:@" \u00B7 \u6B63\u5728\u5BFC\u5165\u8D44\u6E90"]:summary;
        if(!importing)self.refreshInProgress=NO;
        [self.grid reloadData];[self updateControllerSelection];
    });
}
- (void)refresh {
    if(self.refreshInProgress||self.removalInProgress)return;
    self.refreshInProgress=YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        [self publishCatalogWhileImporting:YES];
        NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        TTEnforceGameRemovals(documents,NULL);
        TonTonImportPendingResourcesWithProgress(NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject,
            ^(NSDictionary *result){(void)result;[self publishCatalogWhileImporting:YES];});
        excludeGameResourcesFromBackup();
        [self publishCatalogWhileImporting:NO];
    });
}
- (NSArray<NSDictionary *> *)displayGames{return self.catalog?:@[];}
- (NSInteger)collectionView:(UICollectionView *)v numberOfItemsInSection:(NSInteger)s{(void)v;(void)s;return self.displayGames.count;}
- (UICollectionViewCell *)collectionView:(UICollectionView *)v cellForItemAtIndexPath:(NSIndexPath *)p{CoverCard *c=(CoverCard *)[v dequeueReusableCellWithReuseIdentifier:@"card" forIndexPath:p];NSDictionary *g=self.displayGames[p.item];NSString *b=bundleForGame(g);BOOL installed=[self.installed containsObject:b];c.controllerFocused=self.menuController!=nil&&[g[@"id"] isEqual:self.controllerTitleID];c.art.image=coverForGame(g);c.placeholder.text=g[@"name"];c.placeholder.hidden=c.art.image!=nil;c.art.backgroundColor=C(37,48,66);c.title.text=g[@"name"];c.sizeLabel.text=[NSString stringWithFormat:@"%@  \u00B7  %@",g[@"size"],g[@"version"]];c.badge.text=installed?@"\u25B6":@"\u2026";c.badge.backgroundColor=installed?[UIColor colorWithWhite:0 alpha:0.72]:[UIColor colorWithWhite:0 alpha:0.45];c.badge.textColor=UIColor.whiteColor;return c;}
- (CGSize)collectionView:(UICollectionView *)v layout:(UICollectionViewLayout *)l sizeForItemAtIndexPath:(NSIndexPath *)p{(void)l;(void)p;CGFloat w=v.bounds.size.width;NSInteger n=w>=700?4:w>=500?3:2;NSInteger rows=(self.displayGames.count+n-1)/n;CGFloat byWidth=floor((w-(n-1)*15)/n);CGFloat byHeight=rows==2?floor((v.bounds.size.height-4-68-10)/2-60):300;CGFloat side=MIN(300,MIN(byWidth,MAX(120,byHeight)));return CGSizeMake(side,side+60);}
- (void)collectionView:(UICollectionView *)v didSelectItemAtIndexPath:(NSIndexPath *)p{(void)v;self.controllerIndex=p.item;self.controllerTitleID=self.displayGames[p.item][@"id"];[self updateControllerSelection];NSDictionary *g=self.displayGames[p.item];NSString *b=bundleForGame(g);
#ifdef DM_LIBRARY_HOST
    // A transfer may have finished since refresh, or an old refresh may still be
    // queued. Validate the selected cartridge now, rather than trusting a UI set.
    NSSet *current=availableGames(@[g],NO);
    if(![current containsObject:b]){
        NSString *doc=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
        NSDictionary *status=TonTonGameReadiness(g[@"id"],[doc stringByAppendingPathComponent:@"Games"],[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"GameResources"]);
        [self showNotice:@"\u5361\u5E26\u5C1A\u672A\u5C31\u7EEA" detail:status[@"detail"]];return;
    }
#else
    if(![self.installed containsObject:b]){[self showNotice:@"\u5361\u5E26\u5C1A\u672A\u5C31\u7EEA" detail:@"\u8FD9\u6B3E\u6E38\u620F\u7684\u7A0B\u5E8F\u6216\u8D44\u6E90\u5C1A\u672A\u5B8C\u6210\u6574\u5408\u3002"];return;}
#endif
#ifdef DM_LIBRARY_HOST
    if(self.startGame)self.startGame(g[@"id"]);
#else
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{if(!NXOpenInstalledGame(b))dispatch_async(dispatch_get_main_queue(),^{UIAlertController *a=[UIAlertController alertControllerWithTitle:@"\u542F\u52A8\u5931\u8D25" message:@"\u8BF7\u4FDD\u6301 MCP \u670D\u52A1\u8FD0\u884C\u540E\u5237\u65B0\uFF0C\u518D\u8BD5\u4E00\u6B21\u3002" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"\u597D" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];});});
#endif
}
@end
#if defined(DM_LIBRARY_HOST)
@interface TTInGameCatalog : UITableViewController
@property(nonatomic, copy) NSArray<NSDictionary *> *cards;
@property(nonatomic, copy) dispatch_block_t returned;
@property(nonatomic, strong) NSTimer *returnPoll;
@property(nonatomic) BOOL waitingForBRelease;
@end
@implementation TTInGameCatalog
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"\u6E38\u620F\u5E93";
    self.cards = games();
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"\u8FD4\u56DE\u6E38\u620F"
        style:UIBarButtonItemStyleDone target:self action:@selector(back)];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.waitingForBRelease = YES;
    __weak TTInGameCatalog *weakSelf = self;
    self.returnPoll = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
        TTInGameCatalog *view = weakSelf;
        if (!view) { [timer invalidate]; return; }
        if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
            view.waitingForBRelease = YES;
            return;
        }
        BOOL held = NO;
        for (GCController *pad in GCController.controllers) if (pad.extendedGamepad.buttonB.isPressed) { held = YES; break; }
        if (!held) view.waitingForBRelease = NO;
        else if (!view.waitingForBRelease) [view back];
    }];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.returnPoll invalidate];
    self.returnPoll = nil;
}
- (void)back {
    [self.returnPoll invalidate];
    self.returnPoll = nil;
    [self dismissViewControllerAnimated:YES completion:self.returned];
}
- (NSInteger)tableView:(UITableView *)view numberOfRowsInSection:(NSInteger)section {
    (void)view; (void)section; return self.cards.count;
}
- (NSString *)tableView:(UITableView *)view titleForHeaderInSection:(NSInteger)section {
    (void)view; (void)section; return @"\u5F53\u524D\u6E38\u620F\u4ECD\u5728\u8FD0\u884C\u3002\u6B64\u5904\u53EF\u6D4F\u89C8\uFF0C\u6682\u4E0D\u80FD\u5207\u6362\u6E38\u620F\u3002";
}
- (UITableViewCell *)tableView:(UITableView *)view cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [view dequeueReusableCellWithIdentifier:@"browse"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"browse"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = self.cards[path.row][@"name"];
    return cell;
}
@end
UIViewController *TonTonInGameCatalogController(dispatch_block_t returned) {
    TTInGameCatalog *catalog = [TTInGameCatalog new];
    catalog.returned = returned;
    return [[UINavigationController alloc] initWithRootViewController:catalog];
}
#endif
#import "LibraryAppearance16.h"
UIViewController *TonTonLibraryController(void (^startGame)(NSString *titleID)){
    TonTonWriteStorageStatus();
    TTLibrary16 *view=[TTLibrary16 new];view.startGame=startGame;return view;
}
#ifndef DM_LIBRARY_HOST
@interface LibraryDelegate:UIResponder<UIApplicationDelegate>
@property(nonatomic,strong)UIWindow *window;
@end
@implementation LibraryDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)app; (void)options;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    // The library and presented games share a window and read GameController profiles.
    // Request delivery through those profiles even when UIKit holds the current responder.
    if (@available(iOS 18.0, *)) {
        GCEventInteraction *gamepadEvents = [GCEventInteraction new];
        gamepadEvents.handledEventTypes = GCUIEventTypeGamepad;
        [self.window addInteraction:gamepadEvents];
    }
    self.window.rootViewController = [LibraryView new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(LibraryDelegate.class));}}
#endif

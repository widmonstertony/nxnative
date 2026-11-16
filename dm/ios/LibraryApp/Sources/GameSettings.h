#pragma once
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdlib.h>
// Each game owns only its preference namespace. Missing values inherit global
// choices; the explicit default token selects the game's tested default.
static NSString *TTGamePreferenceKey(NSString *title, NSString *env) {
    return [NSString stringWithFormat:@"tonton.game.%@.%@",title.lowercaseString,env];
}
static BOOL TTSettingAccepts(NSDictionary *spec, NSString *value) {
    if(![value isKindOfClass:NSString.class]||!value.length)return NO;
    if([spec[@"kind"] isEqual:@"toggle"])
        return [value isEqual:spec[@"on"]?:@"1"]||[value isEqual:spec[@"off"]?:@"0"];
    if([spec[@"kind"] isEqual:@"range"]){
        NSScanner *scan=[NSScanner scannerWithString:value];double v;
        if(![scan scanDouble:&v]||!scan.isAtEnd||!isfinite(v))return NO;
        double low=[spec[@"min"] doubleValue],high=[spec[@"max"] doubleValue],step=[spec[@"step"] doubleValue];
        if(v<low-1e-6||v>high+1e-6||step<=0)return NO;
        return fabs((v-low)/step-round((v-low)/step))<1e-4;
    }
    for(NSArray *option in spec[@"options"])
        if([option isKindOfClass:NSArray.class]&&option.count==2&&[option[0] isEqual:value])return YES;
    return NO;
}
static NSString *TTGameOverride(NSUserDefaults *prefs,NSString *title,NSDictionary *spec){
    NSString *saved=[prefs stringForKey:TTGamePreferenceKey(title,spec[@"env"])];
    if([saved isEqual:@"__defaults__"])saved=spec[@"default"];
    return TTSettingAccepts(spec,saved)?saved:nil;
}
static NSDictionary *TTChoice(NSString *env,NSString *label,NSString *def,NSArray *options){
    return @{@"env":env,@"label":label,@"default":def,@"kind":@"choice",@"section":@"Game",@"options":options};
}
// Signed Switch frameworks can arrive with a data-only import and no
// launcher.json. Both controls are implemented by the native host.
static NSString *TTNativeSwitchFramework(NSString *title){
    NSString *upper=title.uppercaseString;
    if(upper.length!=16||(![upper hasPrefix:@"01"]&&![upper hasPrefix:@"04"]))return nil;
    if([upper rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEF"] invertedSet]].location!=NSNotFound)return nil;
    NSString *name=[NSString stringWithFormat:@"DmGame%@.framework",upper];
    NSString *framework=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:name];
    return [NSFileManager.defaultManager fileExistsAtPath:[framework stringByAppendingPathComponent:@"DmGame"]]?framework:nil;
}
// Show a real scene cap only with a contract for this exact signed build.
static NSString *TTResolutionContract(NSString *title){
    NSString *framework=TTNativeSwitchFramework(title);
    if(!framework)return nil;
    NSString *fixups=[NSString stringWithContentsOfFile:[framework stringByAppendingPathComponent:@"dm/main.fixups.tsv"] encoding:NSUTF8StringEncoding error:nil];
    NSString *doc=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSString *relative=[NSString stringWithFormat:@"Games/%@/Resources/dm/resolution_levels.tsv",title.lowercaseString];
    NSString *bundled=[NSString stringWithFormat:@"GameResources/%@/Resources/dm/resolution_levels.tsv",title.lowercaseString];
    for(NSString *path in @[[doc stringByAppendingPathComponent:relative],[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:bundled]]){
        NSString *text=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        for(NSString *line in [text componentsSeparatedByString:@"\n"]){
            NSArray *parts=[line componentsSeparatedByString:@"\t"];
            if(parts.count==2&&[parts[0] isEqual:@"build"]&&[parts[1] length]==32&&[fixups containsString:parts[1]])return path;
        }
    }
    return nil;
}
static NSDictionary *TTNativeGraphicsSetting(NSString *title,NSString *key){
    NSString *framework=TTNativeSwitchFramework(title);
    if(!framework)return nil;
    if([key isEqual:@"DM_OPMODE"])return TTChoice(key,@"\u8FD0\u884C\u6A21\u5F0F",@"0",@[@[@"0",@"\u638C\u673A"],@[@"1",@"\u5E95\u5EA7"]]);
    if([key isEqual:@"DM_PRESENT_UPSCALE"])return TTChoice(key,@"\u753B\u9762\u8D85\u5206",@"metalfx",@[@[@"off",@"\u5173\u95ED"],@[@"metalfx",@"MetalFX"]]);
    if([key isEqual:@"DM_WINDOW_SIZE"] && TTResolutionContract(title))
        return TTChoice(key,@"\u5185\u90e8 3D \u5206\u8fa8\u7387\u4e0a\u9650",@"1280x720",@[@[@"1280x720",@"720p"],@[@"960x540",@"540p"],@[@"original",@"\u6e38\u620f\u539f\u59cb\u8bbe\u7f6e"]]);
    if(![@[@"DM_RENDER_SCALE",@"DM_DYNAMIC_RESOLUTION"] containsObject:key])return nil;
    NSString *fixups=[NSString stringWithContentsOfFile:[framework stringByAppendingPathComponent:@"dm/main.fixups.tsv"]
                                               encoding:NSUTF8StringEncoding error:nil];
    if([key isEqual:@"DM_RENDER_SCALE"]&&[title.lowercaseString isEqual:@"0100f2c0115b6000"]&&
       [fixups containsString:@"\n# RENDER_SCALE\t1\n"])
        return @{@"env":key,@"label":@"3D \u6E32\u67D3\u6BD4\u4F8B",@"kind":@"range",@"section":@"Game",@"default":@"0.75",@"min":@0.50,@"max":@1.00,@"step":@0.05};
    if([key isEqual:@"DM_DYNAMIC_RESOLUTION"]&&[title.lowercaseString isEqual:@"0100b8e016f76000"]&&
       [fixups containsString:@"\n# DYNAMIC_RESOLUTION\t1\n"])
        return @{@"env":key,@"label":@"\u52A8\u6001\u5206\u8FA8\u7387",@"kind":@"toggle",@"section":@"Game",@"default":@"1",@"on":@"1",@"off":@"0"};
    return nil;
}
static NSArray *TTGTASettingSpecs(void){
    return @[
        TTChoice(@"GTA_FPS",@"\u5E27\u7387\u9650\u5236",@"0",@[@[@"0",@"\u4E0D\u9650\u5236"],@[@"30",@"30 \u5E27"],@[@"60",@"60 \u5E27"]]),
        TTChoice(@"GTA_HEIGHT",@"\u6E32\u67D3\u5206\u8FA8\u7387",@"720",@[@[@"480",@"480p"],@[@"540",@"540p"],@[@"640",@"640p"],@[@"720",@"720p"],@[@"900",@"900p"],@[@"1080",@"1080p"]]),
        TTChoice(@"GTA_TEXTURE_QUALITY",@"\u7EB9\u7406\u8D28\u91CF",@"0",@[@[@"0",@"\u666E\u901A"],@[@"1",@"\u9AD8"],@[@"2",@"\u975E\u5E38\u9AD8"]]),
        TTChoice(@"GTA_SHADOW_QUALITY",@"\u9634\u5F71",@"-1",@[@[@"-1",@"\u5173\u95ED"],@[@"0",@"\u666E\u901A"],@[@"1",@"\u9AD8"],@[@"2",@"\u975E\u5E38\u9AD8"]]),
        TTChoice(@"GTA_REFLECTION_QUALITY",@"\u53CD\u5C04\u8D28\u91CF",@"0",@[@[@"0",@"\u666E\u901A"],@[@"1",@"\u9AD8"],@[@"2",@"\u975E\u5E38\u9AD8"]]),
        TTChoice(@"GTA_PARTICLE_QUALITY",@"\u7C92\u5B50\u6548\u679C",@"0",@[@[@"0",@"\u666E\u901A"],@[@"1",@"\u9AD8"],@[@"2",@"\u975E\u5E38\u9AD8"]]),
        TTChoice(@"GTA_GRASS_QUALITY",@"\u8349\u5730\u8D28\u91CF",@"0",@[@[@"0",@"\u666E\u901A"],@[@"1",@"\u9AD8"],@[@"2",@"\u975E\u5E38\u9AD8"]])
    ];
}
static NSArray *TTGameSettingSpecs(NSString *title){
    if([title isEqual:@"gta5"])return TTGTASettingSpecs();
    if([@[@"redalert2",@"yurisrevenge"] containsObject:title])return @[];
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    NSArray *paths=@[[documents stringByAppendingPathComponent:[NSString stringWithFormat:@"Games/%@/Resources/dm/launcher.json",title.lowercaseString]],
        [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:[NSString stringWithFormat:@"GameResources/%@/Resources/dm/launcher.json",title.lowercaseString]]];
    NSMutableArray *out=[NSMutableArray arrayWithArray:@[
        TTChoice(@"DM_FRAME_LIMIT",@"\u5E27\u7387\u9650\u5236",@"game",@[@[@"unlimited",@"\u4E0D\u9650\u5236"],@[@"game",@"\u6E38\u620F\u539F\u59CB\u8BBE\u7F6E"]]),
        TTChoice(@"DM_PRESENT_ASPECT",@"\u753B\u9762\u9002\u914D",@"auto",@[@[@"auto",@"\u6E38\u620F\u9ED8\u8BA4"],@[@"fit",@"\u4FDD\u6301\u539F\u6BD4\u4F8B"],@[@"fill",@"\u94FA\u6EE1\u5C4F\u5E55"]]),
        TTChoice(@"DM_TOUCH_SIZE",@"\u865A\u62DF\u6309\u952E\u5927\u5C0F",@"medium",@[@[@"small",@"\u5C0F"],@[@"medium",@"\u4E2D"],@[@"large",@"\u5927"]]),
        TTChoice(@"DM_TOUCH_STICK",@"\u865A\u62DF\u5DE6\u6447\u6746\u4F4D\u7F6E",@"corner",@[@[@"corner",@"\u5DE6\u4E0B"],@[@"higher",@"\u9760\u4E0A"],@[@"inward",@"\u9760\u5185"]])]];
    for(NSString *path in paths){
        NSData *data=[NSData dataWithContentsOfFile:path];if(!data)continue;
        id schema=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if(![schema isKindOfClass:NSDictionary.class]||![schema[@"schema"] isEqual:@1]||![schema[@"settings"] isKindOfClass:NSArray.class])continue;
        for(id row in schema[@"settings"]){
            if(![row isKindOfClass:NSDictionary.class]||![row[@"env"] isKindOfClass:NSString.class]||![row[@"env"] hasPrefix:@"DM_"])continue;
            if(![@[@"choice",@"toggle",@"range"] containsObject:row[@"kind"]]||!TTSettingAccepts(row,row[@"default"]))continue;
            if(![@[@"DM_PRESENT_ASPECT",@"DM_TOUCH_SIZE",@"DM_TOUCH_STICK"] containsObject:row[@"env"]])[out addObject:row];
        }break;
    }
    for(NSString *key in @[@"DM_OPMODE",@"DM_PRESENT_UPSCALE",@"DM_RENDER_SCALE",@"DM_DYNAMIC_RESOLUTION",@"DM_WINDOW_SIZE"]){
        NSDictionary *native=TTNativeGraphicsSetting(title,key);
        if(!native)continue;
        BOOL hasSetting=NO;
        for(NSDictionary *spec in out)if([spec[@"env"] isEqual:key]){hasSetting=YES;break;}
        if(!hasSetting)[out addObject:native];
    }
    return out;
}
static NSString *TTSettingTitle(NSDictionary *spec){
    NSDictionary *names=@{@"DM_FPS_TARGET":@"\u6E38\u620F\u76EE\u6807\u5E27\u7387",@"DM_NFS_FPS":@"\u6E38\u620F\u76EE\u6807\u5E27\u7387",@"DM_ARCEUS_FPS":@"\u6E38\u620F\u76EE\u6807\u5E27\u7387",@"DM_FRAMEGEN":@"\u753B\u9762\u63D2\u5E27",@"DM_DYNAMIC_RESOLUTION":@"\u52A8\u6001\u5206\u8FA8\u7387",@"DM_RENDER_SCALE":@"\u6E32\u67D3\u6BD4\u4F8B",@"DM_OPMODE":@"\u8FD0\u884C\u6A21\u5F0F",@"DM_PRESENT_UPSCALE":@"\u753B\u9762\u8D85\u5206",@"DM_LANG":@"\u6E38\u620F\u8BED\u8A00",@"DM_SHOW_FPS":@"\u663E\u793A\u5E27\u7387",@"DM_TOUCH_HAPTICS":@"\u89E6\u63A7\u53CD\u9988",@"DM_RUMBLE":@"\u624B\u67C4\u632F\u52A8",@"DM_RUMBLE_GAIN":@"\u632F\u52A8\u5F3A\u5EA6",@"DM_RUMBLE_MIN":@"\u632F\u52A8\u9608\u503C",@"DM_PRESENT_SNAP":@"\u5E27\u7F13\u51B2",@"DM_PSO_MTL4":@"Metal 4 \u7BA1\u7EBF",@"DM_PSO_PREBUILD":@"\u9884\u5EFA\u56FE\u5F62\u7BA1\u7EBF",@"DM_NVN_ENC_THREAD":@"\u72EC\u7ACB\u56FE\u5F62\u7F16\u7801\u7EBF\u7A0B",@"DM_FPS_HOLD":@"\u4FDD\u7559\u5EF6\u8FDF\u5E27",@"DM_METAL_HUD":@"\u6027\u80FD\u76D1\u89C6\u5668"};
    return names[spec[@"env"]]?:spec[@"label"]?:spec[@"env"];
}
static NSString *TTSettingValueLabel(NSDictionary *spec,NSString *value){
    if([spec[@"kind"] isEqual:@"toggle"])return [value isEqual:spec[@"on"]?:@"1"]?@"\u5F00\u542F":@"\u5173\u95ED";
    if([spec[@"kind"] isEqual:@"range"])return [NSString stringWithFormat:@"%.0f%%",value.doubleValue*100];
    if([spec[@"env"] isEqual:@"DM_LANG"]){NSDictionary *languages=@{@"zh-Hans":@"\u7B80\u4F53\u4E2D\u6587",@"zh-Hant":@"\u7E41\u4F53\u4E2D\u6587",@"zh-CN":@"\u7B80\u4F53\u4E2D\u6587",@"zh-TW":@"\u7E41\u4F53\u4E2D\u6587",@"en-US":@"\u82F1\u8BED\uFF08\u7F8E\u56FD\uFF09",@"en-GB":@"\u82F1\u8BED\uFF08\u82F1\u56FD\uFF09",@"ja":@"\u65E5\u8BED",@"ko":@"\u97E9\u8BED",@"fr":@"\u6CD5\u8BED",@"de":@"\u5FB7\u8BED",@"es":@"\u897F\u73ED\u7259\u8BED",@"it":@"\u610F\u5927\u5229\u8BED",@"ru":@"\u4FC4\u8BED"};if(languages[value])return languages[value];}
    NSDictionary *translations=@{@"Docked":@"\u5E95\u5EA7",@"Handheld":@"\u638C\u673A",@"Standard":@"\u6807\u51C6",@"Off":@"\u5173\u95ED",@"Optical flow (experimental)":@"\u5149\u6D41\uFF08\u5B9E\u9A8C\u6027\uFF09",@"Original 30 fps":@"\u539F\u59CB 30 \u5E27",@"30 fps":@"30 \u5E27",@"60 fps":@"60 \u5E27",@"120 fps":@"120 \u5E27",@"Unavailable pending shader fix":@"\u6682\u4E0D\u53EF\u7528"};
    for(NSArray *option in spec[@"options"])if([option[0] isEqual:value])return translations[option[1]]?:option[1];
    return value?:@"\u6E38\u620F\u9ED8\u8BA4";
}
static void TTApplyGameOverrides(NSString *title){
    NSString *contract=TTResolutionContract(title);
    if(contract)setenv("DM_RESOLUTION_LEVELS_PATH",contract.UTF8String,1);
    else unsetenv("DM_RESOLUTION_LEVELS_PATH");
    for(NSDictionary *spec in TTGameSettingSpecs(title)){
        NSString *env=spec[@"env"],*value=TTGameOverride(NSUserDefaults.standardUserDefaults,title,spec);
        if(value&&[env hasPrefix:@"DM_"])setenv(env.UTF8String,value.UTF8String,1);
    }
}
static NSString *TTGTAValue(NSString *env,NSString *fallback){
    for(NSDictionary *spec in TTGTASettingSpecs())if([spec[@"env"] isEqual:env])return TTGameOverride(NSUserDefaults.standardUserDefaults,@"gta5",spec)?:fallback;
    return fallback;
}

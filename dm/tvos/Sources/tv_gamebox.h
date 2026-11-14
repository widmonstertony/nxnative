#pragma once
#import <UIKit/UIKit.h>

static inline NSString *TVGamePreference(NSString *titleID, NSString *key) {
    return [NSString stringWithFormat:@"TVGamebox.%@.%@",titleID,key];
}

static inline NSString *TVGameResourceRoot(NSString *titleID) {
    NSString *cache = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    return [[cache stringByAppendingPathComponent:@"TonTonGames"] stringByAppendingPathComponent:titleID.uppercaseString];
}

static inline void TVShowSwitchRequired(UIViewController *presenter) {
    UIAlertController *dialog = [UIAlertController alertControllerWithTitle:@"另一个游戏正在暂停"
        message:@"请先保存进度并重新打开游戏匣，再启动其他游戏。" preferredStyle:UIAlertControllerStyleAlert];
    [dialog addAction:[UIAlertAction actionWithTitle:@"返回游戏库" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:dialog animated:YES completion:nil];
}

static inline UIImage *TVGameArtwork(NSString *titleID, BOOL primary) {
    NSString *cache = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject;
    NSString *folder = [cache stringByAppendingPathComponent:[@"LibraryArtwork/" stringByAppendingString:titleID.lowercaseString]];
    for (NSString *file in @[@"hero.jpg",@"banner.jpg",@"thumbnail.jpg"]) {
        UIImage *image = [UIImage imageWithContentsOfFile:[folder stringByAppendingPathComponent:file]];
        if (image) return image;
    }
    UIImage *art = [UIImage imageNamed:[@"GameboxTitle-" stringByAppendingString:titleID.lowercaseString]];
    return art ?: (primary ? [UIImage imageNamed:@"GameboxFeature"] : nil);
}

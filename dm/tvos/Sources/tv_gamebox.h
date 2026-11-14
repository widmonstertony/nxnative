#pragma once
#import <UIKit/UIKit.h>

static inline NSString *TVGamePreference(NSString *titleID, NSString *key) {
    return [NSString stringWithFormat:@"TVGamebox.%@.%@",titleID,key];
}

static inline UIImage *TVGameArtwork(NSString *titleID, BOOL primary) {
    NSString *cache = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject;
    NSString *folder = [cache stringByAppendingPathComponent:[@"LibraryArtwork/" stringByAppendingString:titleID.lowercaseString]];
    for (NSString *file in @[@"hero.jpg",@"banner.jpg",@"thumbnail.jpg"]) {
        UIImage *image = [UIImage imageWithContentsOfFile:[folder stringByAppendingPathComponent:file]];
        if (image) return image;
    }
    return [UIImage imageNamed:primary ? @"GameboxFeature" : [@"GameboxTitle-" stringByAppendingString:titleID.lowercaseString]];
}

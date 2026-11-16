#pragma once
#import <Foundation/Foundation.h>

// Export only capacity metadata. Delivery preflight must use real free space,
// rather than the hardware capacity reported by CoreDevice.
static void TonTonWriteStorageStatus(void) {
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    if(!documents)return;
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfFileSystemForPath:documents error:nil];
    NSNumber *free=attributes[NSFileSystemFreeSize],*total=attributes[NSFileSystemSize];
    if(!free||!total)return;
    NSDictionary *status=@{@"schema":@1,@"free_bytes":free,@"total_bytes":total,
        @"version":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"]?:@"",
        @"measured_at":@([NSDate.date timeIntervalSince1970])};
    NSData *data=[NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
    [data writeToFile:[documents stringByAppendingPathComponent:@"TonTonStorageStatus.json"]
             options:NSDataWritingAtomic error:nil];
}

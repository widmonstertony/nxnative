#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <limits.h>

// Called at boot, before rotating logs. Content-addressed hard links survive
// later removal of log.prev.txt and the bounded ordinary launch history.
static inline BOOL dm_archive_crash_log(NSString *path, NSString *history) {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:path]) return YES;
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data) return NO;
    NSData *marker = [@"[dm] CRASH" dataUsingEncoding:NSUTF8StringEncoding];
    if ([data rangeOfData:marker options:0 range:NSMakeRange(0, data.length)].location == NSNotFound) return YES;
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    const unsigned char *bytes = data.bytes;
    for (NSUInteger at = 0; at < data.length;) {
        CC_LONG count = (CC_LONG)MIN(data.length - at, (NSUInteger)UINT_MAX);
        CC_SHA256_Update(&ctx, bytes + at, count);
        at += count;
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    NSMutableString *name = [NSMutableString stringWithString:@"crash-"];
    for (NSUInteger i = 0; i < sizeof digest; i++) [name appendFormat:@"%02x", digest[i]];
    [name appendString:@".txt"];
    NSString *directory = [history stringByAppendingPathComponent:@"Crashes"];
    if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
    NSString *archive = [directory stringByAppendingPathComponent:name];
    if ([fm fileExistsAtPath:archive]) return [fm contentsEqualAtPath:path andPath:archive];
    if ([fm linkItemAtPath:path toPath:archive error:nil]) return YES;
    NSString *temporary = [archive stringByAppendingFormat:@".%@.partial", NSUUID.UUID.UUIDString];
    BOOL copied = [fm copyItemAtPath:path toPath:temporary error:nil];
    BOOL moved = copied && [fm moveItemAtPath:temporary toPath:archive error:nil];
    if (!moved) [fm removeItemAtPath:temporary error:nil];
    return moved;
}

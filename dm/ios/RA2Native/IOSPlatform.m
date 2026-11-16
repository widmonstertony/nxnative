#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "IOSPlatform.h"

static _Thread_local char font_path[4096];
static char settings_executable[4096];
static pthread_mutex_t settings_lock = PTHREAD_MUTEX_INITIALIZER;

const char *ra2_ios_font_file(const char *face, int bold, int italic) {
    @autoreleasepool {
        NSString *requested = face ? [NSString stringWithUTF8String:face] : nil;
        if (!requested) requested = @"Arial";
        NSString *lower = requested.lowercaseString;
        NSString *family = @"ArialMT";
        BOOL cjk = [lower containsString:@"simsun"] || [lower containsString:@"simhei"] ||
                   [lower containsString:@"mingliu"] || [lower containsString:@"gothic"] ||
                   [lower containsString:@"宋"] || [lower containsString:@"黑体"];
        if (cjk) family = @"PingFangSC-Regular";
        else if ([lower containsString:@"times"] || [lower isEqual:@"ms serif"] || [lower isEqual:@"georgia"])
            family = @"TimesNewRomanPSMT";
        else if ([lower containsString:@"courier"] || [lower isEqual:@"fixedsys"] || [lower isEqual:@"terminal"])
            family = @"CourierNewPSMT";
        CTFontRef base = CTFontCreateWithName((__bridge CFStringRef)family, 14, NULL);
        if (!base) return NULL;
        CTFontSymbolicTraits traits = (bold ? kCTFontBoldTrait : 0) | (italic ? kCTFontItalicTrait : 0);
        CTFontRef styled = traits ? CTFontCreateCopyWithSymbolicTraits(base, 14, NULL, traits, traits) : NULL;
        CFTypeRef attribute = CTFontCopyAttribute(styled ?: base, kCTFontURLAttribute);
        BOOL ok = attribute && CFGetTypeID(attribute) == CFURLGetTypeID() &&
                  CFURLGetFileSystemRepresentation((CFURLRef)attribute, true,
                                                  (UInt8 *)font_path, sizeof font_path);
        if (attribute) CFRelease(attribute);
        if (styled) CFRelease(styled);
        CFRelease(base);
        struct stat st;
        return ok && access(font_path, R_OK) == 0 && stat(font_path, &st) == 0 && S_ISREG(st.st_mode)
               ? font_path : NULL;
    }
}

int ra2_ios_set_user_directory(const char *directory, char *error, size_t capacity) {
    @autoreleasepool {
        NSString *input = directory ? [NSString stringWithUTF8String:directory] : nil;
        if (!input.length || !input.isAbsolutePath) {
            if (error && capacity) snprintf(error, capacity, "Expected an absolute app-owned UserData directory");
            return 0;
        }
        NSString *home = NSHomeDirectory().stringByResolvingSymlinksInPath;
        NSString *path = input.stringByStandardizingPath.stringByResolvingSymlinksInPath;
        if (![path hasPrefix:[home stringByAppendingString:@"/"]]) {
            if (error && capacity) snprintf(error, capacity, "UserData directory is outside this app container");
            return 0;
        }
        NSError *failure = nil;
        if (![NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&failure]) {
            if (error && capacity) snprintf(error, capacity, "%s", failure.localizedDescription.UTF8String);
            return 0;
        }
        NSString *host = [path stringByAppendingPathComponent:@"ra2-native-host"];
        if (strlen(host.fileSystemRepresentation) >= sizeof settings_executable || access(path.fileSystemRepresentation, W_OK) != 0) {
            if (error && capacity) snprintf(error, capacity, "UserData directory is not writable or its path is too long");
            return 0;
        }
        pthread_mutex_lock(&settings_lock);
        snprintf(settings_executable, sizeof settings_executable, "%s", host.fileSystemRepresentation);
        pthread_mutex_unlock(&settings_lock);
        if (error && capacity) error[0] = 0;
        return 1;
    }
}

int ra2_ios_settings_executable_path(char *out, size_t capacity) {
    if (!out || !capacity) return 0;
    pthread_mutex_lock(&settings_lock);
    int ok = settings_executable[0] && strlen(settings_executable) < capacity;
    if (ok) memcpy(out, settings_executable, strlen(settings_executable) + 1);
    pthread_mutex_unlock(&settings_lock);
    return ok;
}

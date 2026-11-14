#pragma once
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <string.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <dirent.h>
#include <unistd.h>
#include <errno.h>

static NSObject *TTGameDataGuard(void) {
    static NSObject *guard;static dispatch_once_t once;dispatch_once(&once,^{guard=[NSObject new];});return guard;
}
static BOOL TTGameIDValid(NSString *title) {
    if(![title isKindOfClass:NSString.class]||!title.length||title.length>64)return NO;
    NSCharacterSet *bad=[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_-"] invertedSet];
    return [title rangeOfCharacterFromSet:bad].location==NSNotFound &&
        [[NSCharacterSet alphanumericCharacterSet] characterIsMember:[title characterAtIndex:0]];
}
static BOOL TTRemovalError(NSError **error,NSString *message) {
    if(error)*error=[NSError errorWithDomain:@"TonTonGameRemoval" code:1 userInfo:@{NSLocalizedDescriptionKey:message?:@"\u65E0\u6CD5\u5220\u9664\u8D44\u6E90"}];return NO;
}
static NSString *TTRemovalFile(NSString *doc){return [doc stringByAppendingPathComponent:@"TonTonDeletedGames.json"];}
static NSDictionary *TTDeletedGames(NSString *doc,NSError **error) {
    NSString *path=TTRemovalFile(doc);struct stat s;
    if(lstat(path.fileSystemRepresentation,&s)){
        if(errno==ENOENT)return @{};
        TTRemovalError(error,@"\u65E0\u6CD5\u8BFB\u53D6\u5DF2\u5220\u9664\u6E38\u620F\u8BB0\u5F55\u3002");return nil;
    }
    if(!S_ISREG(s.st_mode)||s.st_size>(1<<20)){TTRemovalError(error,@"\u5DF2\u5220\u9664\u6E38\u620F\u8BB0\u5F55\u65E0\u6548\u3002");return nil;}
    NSData *data=[NSData dataWithContentsOfFile:path options:0 error:error];if(!data)return nil;
    id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if(![value isKindOfClass:NSDictionary.class]){TTRemovalError(error,@"\u5DF2\u5220\u9664\u6E38\u620F\u8BB0\u5F55\u65E0\u6548\u3002");return nil;}
    for(id key in value)if(!TTGameIDValid(key)||![value[key] isKindOfClass:NSDictionary.class]||![value[key][@"removed"] isEqual:@YES]){
        TTRemovalError(error,@"\u5DF2\u5220\u9664\u6E38\u620F\u8BB0\u5F55\u65E0\u6548\u3002");return nil;
    }
    return value;
}
static BOOL TTGameRemoved(NSString *doc,NSString *title){return TTGameIDValid(title)&&TTDeletedGames(doc,NULL)[title]!=nil;}
static BOOL TTStoreDeletedGames(NSString *doc,NSDictionary *records,NSError **error) {
    struct stat s;if(lstat(doc.fileSystemRepresentation,&s)||!S_ISDIR(s.st_mode))return TTRemovalError(error,@"\u6E38\u620F\u5323\u76EE\u5F55\u4E0D\u53EF\u7528\u3002");
    NSString *path=TTRemovalFile(doc);
    if(!lstat(path.fileSystemRepresentation,&s)&&!S_ISREG(s.st_mode))return TTRemovalError(error,@"\u5220\u9664\u8BB0\u5F55\u8DEF\u5F84\u4E0D\u662F\u666E\u901A\u6587\u4EF6\u3002");
    NSData *data=[NSJSONSerialization dataWithJSONObject:records options:NSJSONWritingPrettyPrinted error:error];
    return data&&[data writeToFile:path options:NSDataWritingAtomic error:error];
}
// unlinkat never traverses a symlink. Directory descriptors keep every child
// operation anchored below the app's Documents directory, including on races.
static BOOL TTRemoveAt(int parent,const char *name,dev_t device,NSError **error) {
    struct stat s;if(fstatat(parent,name,&s,AT_SYMLINK_NOFOLLOW)){
        if(errno==ENOENT)return YES;return TTRemovalError(error,@"\u65E0\u6CD5\u8BFB\u53D6\u5F85\u5220\u9664\u8D44\u6E90\u3002");
    }
    if(S_ISDIR(s.st_mode)){
        int fd=openat(parent,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);if(fd<0)return TTRemovalError(error,@"\u8D44\u6E90\u76EE\u5F55\u6B63\u5728\u6539\u53D8\uFF0C\u8BF7\u7A0D\u540E\u518D\u8BD5\u3002");
        struct stat actual;BOOL ok=fstat(fd,&actual)==0&&actual.st_dev==device&&actual.st_ino==s.st_ino;
        if(!ok){close(fd);return TTRemovalError(error,@"\u8D44\u6E90\u76EE\u5F55\u8EAB\u4EFD\u5DF2\u6539\u53D8\uFF0C\u672A\u7EE7\u7EED\u5220\u9664\u3002");}
        DIR *dir=fdopendir(fd);if(!dir){close(fd);return TTRemovalError(error,@"\u65E0\u6CD5\u6253\u5F00\u8D44\u6E90\u76EE\u5F55\u3002");}
        struct dirent *entry;errno=0;
        while((entry=readdir(dir))){
            if(!strcmp(entry->d_name,".")||!strcmp(entry->d_name,".."))continue;
            if(!TTRemoveAt(fd,entry->d_name,device,error)){closedir(dir);return NO;}
            errno=0;
        }
        int scanError=errno;closedir(dir);if(scanError)return TTRemovalError(error,@"\u8D44\u6E90\u76EE\u5F55\u8BFB\u53D6\u672A\u5B8C\u6210\u3002");
        struct stat now;if(fstatat(parent,name,&now,AT_SYMLINK_NOFOLLOW))return errno==ENOENT?YES:TTRemovalError(error,@"\u8D44\u6E90\u76EE\u5F55\u5DF2\u6539\u53D8\u3002");
        if(!S_ISDIR(now.st_mode)||now.st_dev!=s.st_dev||now.st_ino!=s.st_ino)return TTRemovalError(error,@"\u8D44\u6E90\u76EE\u5F55\u5DF2\u6539\u53D8\uFF0C\u672A\u7EE7\u7EED\u5220\u9664\u3002");
        if(unlinkat(parent,name,AT_REMOVEDIR)&&errno!=ENOENT)return TTRemovalError(error,@"\u90E8\u5206\u8D44\u6E90\u4ECD\u5728\u5199\u5165\uFF0C\u56DE\u5230\u5217\u8868\u540E\u4F1A\u7EE7\u7EED\u6E05\u7406\u3002");
        return YES;
    }
    return unlinkat(parent,name,0)==0||errno==ENOENT?YES:TTRemovalError(error,@"\u65E0\u6CD5\u5220\u9664\u90E8\u5206\u6E38\u620F\u8D44\u6E90\u3002");
}
static BOOL TTRemoveRelative(NSString *doc,NSString *relative,NSError **error) {
    NSArray *parts=[relative componentsSeparatedByString:@"/"];for(NSString *p in parts)if(!p.length||[p isEqual:@"."]||[p isEqual:@".."])return TTRemovalError(error,@"\u5220\u9664\u8DEF\u5F84\u65E0\u6548\u3002");
    int fd=open(doc.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);if(fd<0)return TTRemovalError(error,@"\u65E0\u6CD5\u6253\u5F00\u6E38\u620F\u5323\u76EE\u5F55\u3002");
    struct stat st;if(fstat(fd,&st)){close(fd);return TTRemovalError(error,@"\u65E0\u6CD5\u8BFB\u53D6\u6E38\u620F\u5323\u76EE\u5F55\u3002");}
    for(NSUInteger i=0;i+1<parts.count;i++){
        int next=openat(fd,[parts[i] fileSystemRepresentation],O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);int code=errno;close(fd);
        if(next<0)return code==ENOENT?YES:TTRemovalError(error,@"\u8D44\u6E90\u8DEF\u5F84\u5305\u542B\u94FE\u63A5\u6216\u4E0D\u53EF\u8BBF\u95EE\u7684\u76EE\u5F55\uFF0C\u5DF2\u4FDD\u7559\u539F\u6570\u636E\u3002");
        struct stat child;if(fstat(next,&child)||child.st_dev!=st.st_dev){close(next);return TTRemovalError(error,@"\u8D44\u6E90\u8DEF\u5F84\u4F4D\u4E8E\u5176\u4ED6\u78C1\u76D8\uFF0C\u5DF2\u4FDD\u7559\u539F\u6570\u636E\u3002");}fd=next;
    }
    BOOL ok=TTRemoveAt(fd,[parts.lastObject fileSystemRepresentation],st.st_dev,error);close(fd);return ok;
}
static NSDictionary *TTReadSmallRemovalJSON(NSString *path) {
    struct stat s;if(lstat(path.fileSystemRepresentation,&s)||!S_ISREG(s.st_mode)||s.st_size>(8<<20))return nil;
    NSData *data=[NSData dataWithContentsOfFile:path];if(!data)return nil;
    id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];return [value isKindOfClass:NSDictionary.class]?value:nil;
}
static BOOL TTCleanRemovedGame(NSString *doc,NSString *title,NSError **error) {
    BOOL ok=YES;NSString *slot=[@"Games/" stringByAppendingString:title];
    // UserData is retained. The legacy web payload is read-only game content;
    // GTA's native saves live separately in UserData/EngineFiles/userdata.
    for(NSString *part in @[@"Resources",@"UserData/playgta5-offline"])
        if(!TTRemoveRelative(doc,[slot stringByAppendingPathComponent:part],error))ok=NO;
    NSString *incoming=[doc stringByAppendingPathComponent:@"TonTonIncoming"];
    for(NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:incoming error:nil]){
        if(!name.length||name.length>255||[name isEqual:@"."]||[name isEqual:@".."]||[name rangeOfString:@"/"].location!=NSNotFound)continue;
        NSString *folder=[incoming stringByAppendingPathComponent:name];struct stat st;
        if(lstat(folder.fileSystemRepresentation,&st)||!S_ISDIR(st.st_mode))continue;
        NSDictionary *task=TTReadSmallRemovalJSON([folder stringByAppendingPathComponent:@"ImportTask.json"]);
        if(!task)task=TTReadSmallRemovalJSON([folder stringByAppendingPathComponent:@"TransferOwner.json"]);
        if([task[@"game_id"] isEqual:title]&&!TTRemoveRelative(doc,[@"TonTonIncoming" stringByAppendingPathComponent:name],error))ok=NO;
    }
    return ok;
}
static BOOL TTEnforceGameRemovals(NSString *doc,NSError **error) {
    @synchronized(TTGameDataGuard()){
        NSDictionary *records=TTDeletedGames(doc,error);if(!records)return NO;
        for(NSString *title in records)if(!TTCleanRemovedGame(doc,title,error))return NO;
        return YES;
    }
}
static BOOL TTDeleteGame(NSString *doc,NSString *title,NSString *name,NSError **error) {
    if(!TTGameIDValid(title))return TTRemovalError(error,@"\u6E38\u620F\u6807\u8BC6\u65E0\u6548\u3002");
    @synchronized(TTGameDataGuard()){
        NSDictionary *old=TTDeletedGames(doc,error);if(!old)return NO;
        NSMutableDictionary *records=[old mutableCopy];records[title]=@{@"removed":@YES,@"name":name?:title,@"deleted_at":@([NSDate.date timeIntervalSince1970])};
        if(!TTStoreDeletedGames(doc,records,error))return NO;
        return TTCleanRemovedGame(doc,title,error);
    }
}
static BOOL TTRestoreGameCard(NSString *doc,NSString *title,NSError **error) {
    if(!TTGameIDValid(title))return TTRemovalError(error,@"\u6E38\u620F\u6807\u8BC6\u65E0\u6548\u3002");
    @synchronized(TTGameDataGuard()){
        NSDictionary *old=TTDeletedGames(doc,error);if(!old)return NO;NSMutableDictionary *records=[old mutableCopy];[records removeObjectForKey:title];return TTStoreDeletedGames(doc,records,error);
    }
}

#import "TonTonRedAlert.h"
#import <CommonCrypto/CommonDigest.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

typedef int (*TTNativePrepare)(const char *, const char *, const char *, const char *, char *, size_t);
typedef int (*TTNativeMain)(int, char **);
typedef void (*TTNativePump)(int);
static void *engineHandle;
static NSString *loadedEdition;
static BOOL nativeActive;
static NSMutableDictionary<NSString *, NSString *> *verifiedRevisions;

BOOL TonTonRedAlertTitle(NSString *title) {
    return [title isEqual:@"redalert2"] || [title isEqual:@"yurisrevenge"];
}
BOOL TonTonRedAlertIsActive(void) { return nativeActive; }
static NSString *editionForTitle(NSString *title) { return [title isEqual:@"redalert2"] ? @"ra2" : @"yr"; }
static NSString *frameworkName(NSString *title) { return [title isEqual:@"redalert2"] ? @"RedAlertBase" : @"RedAlertYR"; }
static NSDictionary *readJSON(NSString *path) {
    NSData *data=[NSData dataWithContentsOfFile:path];
    id value=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
static NSString *fileSHA(NSString *path) {
    int fd=open(path.fileSystemRepresentation, O_RDONLY|O_CLOEXEC|O_NOFOLLOW);
    if(fd<0)return nil;
    struct stat before, after;
    if(fstat(fd,&before)||!S_ISREG(before.st_mode)){close(fd);return nil;}
    CC_SHA256_CTX context; CC_SHA256_Init(&context);
    unsigned char buffer[128*1024], result[CC_SHA256_DIGEST_LENGTH]; ssize_t n;
    while((n=read(fd,buffer,sizeof buffer))>0)CC_SHA256_Update(&context,buffer,(CC_LONG)n);
    BOOL stable=n==0&&!fstat(fd,&after)&&before.st_size==after.st_size&&
        before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec&&before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec;
    close(fd);if(!stable)return nil;
    CC_SHA256_Final(result,&context);NSMutableString *hex=[NSMutableString stringWithCapacity:64];
    for(size_t i=0;i<sizeof result;i++)[hex appendFormat:@"%02x",result[i]];
    return hex;
}
static BOOL regularFile(NSString *path, unsigned long long size) {
    struct stat s;return !lstat(path.fileSystemRepresentation,&s)&&S_ISREG(s.st_mode)&&
        (unsigned long long)s.st_size==size;
}
static NSString *safeRetailFile(NSString *root, NSString *relative) {
    if(![relative isKindOfClass:NSString.class]||!relative.length||relative.isAbsolutePath)return nil;
    NSArray *parts=[relative componentsSeparatedByString:@"/"];NSString *path=root;
    for(NSUInteger i=0;i<parts.count;i++){
        NSString *part=parts[i];
        if(!part.length||[part isEqual:@"."]||[part isEqual:@".."]||[part containsString:@"\\"])return nil;
        path=[path stringByAppendingPathComponent:part];struct stat s;
        if(lstat(path.fileSystemRepresentation,&s)||S_ISLNK(s.st_mode))return nil;
        if(i+1<parts.count&&!S_ISDIR(s.st_mode))return nil;
    }
    return path;
}
static NSDictionary *engineSpec(NSString *title) {
    return readJSON([NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"NativeEngines.json"])[editionForTitle(title)];
}
static NSString *retailRevision(void) {
    id revision=[NSBundle.mainBundle objectForInfoDictionaryKey:@"TonTonNativeRetailRevision"];
    return [revision isKindOfClass:NSString.class]&&[revision length]==64 ? revision : nil;
}
static NSString *nativeUserData(NSString *title) {
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    return [documents stringByAppendingPathComponent:[NSString stringWithFormat:@"Games/%@/UserData",title]];
}
static NSString *verifiedWorkspace(NSString *title, NSString *revision) {
    if(!revision)return nil;
    NSString *user=nativeUserData(title);
    NSString *edition=editionForTitle(title);
    NSString *parent=[NSString stringWithFormat:@"ra2-native-%@",edition];
    NSString *marker=safeRetailFile(user,[parent stringByAppendingPathComponent:@"workspace.version"]);
    NSString *engine=safeRetailFile(user,[parent stringByAppendingPathComponent:@"EngineFiles"]);
    NSString *expected=[NSString stringWithFormat:@"TonTon-RA2-private-workspace-v1\n%@\n%@\n",edition,revision];
    struct stat st;
    if(!marker||!engine||lstat(engine.fileSystemRepresentation,&st)||!S_ISDIR(st.st_mode)||
       !regularFile(marker,[expected lengthOfBytesUsingEncoding:NSUTF8StringEncoding]))return nil;
    return [[NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:NULL] isEqual:expected] ? engine : nil;
}
static NSString *bundledRetail(NSString *resource) {
    NSString *path=[resource stringByAppendingPathComponent:@"NativeRetail"];
    struct stat st;
    return !lstat(path.fileSystemRepresentation,&st)&&S_ISDIR(st.st_mode) ? path : nil;
}
NSDictionary *TonTonRedAlertReadiness(NSString *title, NSString *frameworksRoot) {
    NSDictionary *spec=engineSpec(title);NSString *name=frameworkName(title);
    NSString *binary=[[frameworksRoot stringByAppendingPathComponent:[name stringByAppendingString:@".framework"]] stringByAppendingPathComponent:name];
    NSString *root=bundledRetail(NSBundle.mainBundle.resourcePath)?:verifiedWorkspace(title,retailRevision());
    NSString *exe=[root stringByAppendingPathComponent:[title isEqual:@"redalert2"]?@"game.exe":@"gamemd.exe"];
    BOOL ready=root&&[spec isKindOfClass:NSDictionary.class]&&regularFile(binary,[spec[@"bytes"] unsignedLongLongValue])&&
        regularFile(exe,[title isEqual:@"redalert2"]?5077608:5286504)&&
        [NSFileManager.defaultManager fileExistsAtPath:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"NativeRetailManifest.json"]];
    return @{@"ready":@(ready),@"code":ready?@"native_installed_pending_playtest":@"native_install_incomplete",
             @"detail":ready?@"\u5df2\u5b89\u88c5\u539f\u751f\u7248\uff0c\u9996\u6b21\u542f\u52a8\u9700\u51c6\u5907\u8d44\u6e90\u3002":@"\u539f\u751f\u7a0b\u5e8f\u6216\u5b8c\u6574\u8d44\u6e90\u5c1a\u672a\u5b89\u88c5\u3002",
             @"gameplay_verified":@NO,@"metal4_verified":@NO};
}

@interface TTNativeRedAlertController:UIViewController
@property(nonatomic,copy)NSString *titleID;
@property(nonatomic,copy)void (^finished)(void);
@property(nonatomic,strong)UILabel *status;
@property(nonatomic,strong)UIButton *back;
@property(nonatomic)BOOL started;
@property(nonatomic)BOOL cancelled;
@end
@implementation TTNativeRedAlertController
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.blackColor;
    UIActivityIndicatorView *spinner=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    [spinner startAnimating];spinner.color=UIColor.whiteColor;
    self.status=[UILabel new];self.status.textColor=UIColor.whiteColor;self.status.numberOfLines=0;self.status.textAlignment=NSTextAlignmentCenter;
    self.status.text=@"\u6b63\u5728\u6821\u9a8c\u5e76\u51c6\u5907\u539f\u751f\u6e38\u620f\u8d44\u6e90\uff0c\u8bf7\u4fdd\u6301\u5e94\u7528\u6253\u5f00\u3002";
    self.back=[UIButton buttonWithType:UIButtonTypeSystem];[self.back setTitle:@"\u8fd4\u56de\u6e38\u620f\u5323" forState:UIControlStateNormal];
    [self.back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[spinner,self.status,self.back]];
    stack.axis=UILayoutConstraintAxisVertical;stack.spacing=24;stack.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.widthAnchor constant:-48]]];
}
- (void)goBack { self.cancelled=YES;if(self.finished)self.finished(); }
- (void)fail:(NSString *)detail {
    NSLog(@"[RED] native Red Alert %@: %@",self.titleID,detail);
    self.status.text=[@"\u542f\u52a8\u672a\u5b8c\u6210\uff1a" stringByAppendingString:detail?:@"Unknown native entry error"];
    self.back.enabled=YES;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];if(self.started)return;self.started=YES;
    if(loadedEdition&&![loadedEdition isEqual:editionForTitle(self.titleID)]){
        [self fail:@"\u5207\u6362\u7ea2\u8b662\u4e0e\u5c24\u91cc\u7684\u590d\u4ec7\u9700\u5148\u5173\u95ed\u5e76\u91cd\u65b0\u6253\u5f00\u6e38\u620f\u5323\u3002"];return;
    }
    self.back.enabled=NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        @autoreleasepool {
            NSString *resource=NSBundle.mainBundle.resourcePath;
            NSString *manifestPath=[resource stringByAppendingPathComponent:@"NativeRetailManifest.json"];
            NSString *revision=retailRevision();
            NSDictionary *spec=engineSpec(self.titleID);
            NSString *name=frameworkName(self.titleID);
            NSString *binary=[[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:[name stringByAppendingString:@".framework"]] stringByAppendingPathComponent:name];
            NSString *failure=nil;
            if(revision.length!=64||![fileSHA(manifestPath) isEqual:revision])failure=@"Native retail manifest identity mismatch";
            if(!failure&&![fileSHA(binary) isEqual:spec[@"sha256"]])failure=@"Native framework identity mismatch";
            NSString *full=bundledRetail(resource);
            NSString *workspace=full?nil:verifiedWorkspace(self.titleID,revision);
            NSString *retail=full?:workspace;
            NSString *seed=workspace?[resource stringByAppendingPathComponent:@"NativeWorkspaceOnly"]:retail;
            BOOL useWorkspace=workspace!=nil;
            if(!failure&&!retail)failure=@"Verified native workspace is missing";
            NSString *mutableIni=[self.titleID isEqual:@"redalert2"]?@"RA2.INI":@"RA2MD.INI";
            if(!failure&&![verifiedRevisions[retail] isEqual:revision]){
                NSDictionary *manifest=readJSON(manifestPath);
                NSArray *files=manifest[@"files"];NSMutableSet *seen=[NSMutableSet set];
                if(![manifest[@"format"] isEqual:@"TonTon-native-retail-v1"]||![files isKindOfClass:NSArray.class]||files.count<20)failure=@"Invalid full retail manifest";
                for(NSDictionary *row in failure?@[]:files){
                    NSString *relative=[row isKindOfClass:NSDictionary.class]?row[@"path"]:nil;
                    NSString *file=safeRetailFile(retail,relative);
                    // The edition's INI is saved by the game in its prepared workspace.
                    // All immutable retail inputs still require the signed manifest hash.
                    BOOL mutableConfig=useWorkspace&&[relative isEqual:mutableIni];
                    struct stat st;
                    BOOL matches=file&&(mutableConfig?(!lstat(file.fileSystemRepresentation,&st)&&S_ISREG(st.st_mode)):
                        (regularFile(file,[row[@"bytes"] unsignedLongLongValue])&&[fileSHA(file) isEqual:row[@"sha256"]]));
                    if(!matches||[seen containsObject:relative]){failure=@"Full retail file verification failed";break;}
                    [seen addObject:relative];
                }
                if(!failure&&(![seen containsObject:@"game.exe"]||![seen containsObject:@"gamemd.exe"]))failure=@"Missing compiled edition executable";
                if(!failure){
                    if(!verifiedRevisions)verifiedRevisions=[NSMutableDictionary new];
                    verifiedRevisions[retail]=revision;
                }
            }
            dispatch_async(dispatch_get_main_queue(),^{
                if(self.cancelled)return;
                if(failure){[self fail:failure];return;}
                [self loadNative:binary revision:revision seed:seed expectedWorkspace:workspace];
            });
        }
    });
}
- (void)loadNative:(NSString *)binary revision:(NSString *)revision seed:(NSString *)retail expectedWorkspace:(NSString *)workspace {
    if(!engineHandle){
        engineHandle=dlopen(binary.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
        if(!engineHandle){const char *error=dlerror();[self fail:error?[NSString stringWithUTF8String:error]:@"Cannot load native framework"];return;}
        loadedEdition=editionForTitle(self.titleID);
    }
    TTNativePrepare prepare=(TTNativePrepare)dlsym(engineHandle,"TonTonRedAlertPrepareFiles");
    TTNativeMain entry=(TTNativeMain)dlsym(engineHandle,"TonTonRedAlertMain");
    TTNativePump pump=(TTNativePump)dlsym(engineHandle,"SDL_iPhoneSetEventPump");
    if(!prepare||!entry||!pump){[self fail:@"Native entry API is incomplete"];return;}
    NSString *user=nativeUserData(self.titleID);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        @autoreleasepool {
            char error[1024]={0};
            // In a retained-only package this seed contains no retail data and
            // includes a link the engine's workspace copier refuses to follow.
            // Never ask the engine to set up a new workspace from that seed.
            if(workspace&&![verifiedWorkspace(self.titleID,revision) isEqual:workspace]){
                dispatch_async(dispatch_get_main_queue(),^{if(!self.cancelled)[self fail:@"Existing native workspace no longer matches"];});
                return;
            }
            int ready=prepare(retail.fileSystemRepresentation,user.fileSystemRepresentation,
                              editionForTitle(self.titleID).UTF8String,revision.UTF8String,error,sizeof error);
            NSString *failure=ready?nil:[NSString stringWithUTF8String:error];
            dispatch_async(dispatch_get_main_queue(),^{
                if(self.cancelled)return;
                if(!ready){[self fail:failure];return;}
                self.back.enabled=NO;nativeActive=YES;
                setenv("SDL_RENDER_DRIVER","metal",1);
                setenv("SDL_TOUCH_MOUSE_EVENTS","1",1);
                pump(1);
                char *argv[]={"TonTonRedAlert","--run","--fullscreen",NULL};
                NSLog(@"Native Red Alert entering %@ from verified private workspace",self.titleID);
                int result=entry(3,argv);
                pump(0);nativeActive=NO;
                [self fail:[NSString stringWithFormat:@"Native engine returned %d",result]];
                [self.view.window makeKeyAndVisible];
            });
        }
    });
}
@end
UIViewController *TonTonRedAlertController(NSString *title, void (^finished)(void)) {
    if(!TonTonRedAlertTitle(title))return nil;
    TTNativeRedAlertController *controller=[TTNativeRedAlertController new];controller.titleID=title;controller.finished=finished;
    return controller;
}

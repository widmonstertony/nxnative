#import "TonTonWebRuntime.h"
#import <WebKit/WebKit.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>
#include <string.h>

static BOOL TTWebFile(NSString *path) {
    NSDictionary *a=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    return [a[NSFileType] isEqual:NSFileTypeRegular] && [a[NSFileSize] unsignedLongLongValue]>0;
}
static NSString *TTRuntimeRoot(void) {
    return [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"Runtimes/RedAlert2"];
}
BOOL TonTonWebRuntimeAvailable(NSString *title, NSString *slot) {
    if (![title isEqual:@"redalert2"]) return NO;
    NSString *root=TTRuntimeRoot();
    for (NSString *file in @[@"boxedwine.html",@"boxedwine.js",@"boxedwine.wasm",@"boxedwine-shell.js",@"boxedwine.zip"])
        if (!TTWebFile([root stringByAppendingPathComponent:file])) return NO;
    return TTWebFile([slot stringByAppendingPathComponent:@"Resources/ra2-ea-full.zip"]);
}

// Use HTTP rather than file:// or a private WebKit preference: the runtime's
// ZIP/WASM requests require normal fetch, MIME and byte-range semantics.
@interface TTLocalRuntimeServer : NSObject
@property int listener;
@property unsigned short port;
@property(copy) NSString *slot;
- (BOOL)start;
- (void)stop;
@end
@implementation TTLocalRuntimeServer
- (instancetype)init { if ((self=[super init])) _listener=-1; return self; }
- (void)stop { @synchronized(self) { if(_listener>=0){shutdown(_listener,SHUT_RDWR);close(_listener);_listener=-1;} } }
- (void)dealloc { [self stop]; }
- (void)serve:(int)client {
    int noPipe=1;setsockopt(client,SOL_SOCKET,SO_NOSIGPIPE,&noPipe,sizeof(noPipe));
    struct timeval timeout={15,0};setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
    @try {
        NSMutableData *request=[NSMutableData new];char bytes[4096];
        while(request.length<16384){ssize_t n=recv(client,bytes,sizeof(bytes),0);if(n<=0)return;
            [request appendBytes:bytes length:(NSUInteger)n];
            if([request rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0,request.length)].location!=NSNotFound)break;}
        NSString *text=[[NSString alloc] initWithData:request encoding:NSUTF8StringEncoding];
        NSArray *lines=[text componentsSeparatedByString:@"\r\n"];
        NSArray *first=[lines.firstObject componentsSeparatedByString:@" "];
        if(first.count!=3 || (![@"GET" isEqual:first[0]] && ![@"HEAD" isEqual:first[0]]))return;
        NSString *path=[[[first[1] componentsSeparatedByString:@"?"] firstObject] stringByRemovingPercentEncoding];
        if(!path || ![path hasPrefix:@"/"] ||
           [path lengthOfBytesUsingEncoding:NSUTF8StringEncoding]!=strlen(path.UTF8String))return;
        NSString *base=TTRuntimeRoot();
        NSString *relative=[path substringFromIndex:1];
        if([relative isEqual:@"ra2-ea-full.zip"]){base=[self.slot stringByAppendingPathComponent:@"Resources"];}
        if(!relative.length)relative=@"boxedwine.html";
        base=base.stringByResolvingSymlinksInPath;
        NSString *file=[[base stringByAppendingPathComponent:relative] stringByStandardizingPath].stringByResolvingSymlinksInPath;
        if(![file hasPrefix:[base stringByAppendingString:@"/"]])return;
        NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:file error:nil];
        BOOL exists=[attributes[NSFileType] isEqual:NSFileTypeRegular];
        unsigned long long size=[attributes[NSFileSize] unsignedLongLongValue],start=0,end=size?size-1:0;
        BOOL partial=NO,badRange=NO;
        for(NSString *line in lines) if([line.lowercaseString hasPrefix:@"range: bytes="]){
            NSString *range=[line substringFromIndex:13];NSArray *parts=[range componentsSeparatedByString:@"-"];
            NSCharacterSet *bad=[[NSCharacterSet decimalDigitCharacterSet] invertedSet];
            if(parts.count!=2 || ![parts[0] length] || [parts[0] rangeOfCharacterFromSet:bad].location!=NSNotFound ||
               [parts[1] rangeOfCharacterFromSet:bad].location!=NSNotFound){badRange=YES;break;}
            start=[parts[0] longLongValue];if([parts[1] length])end=MIN(end,[parts[1] longLongValue]);
            badRange=!size||start>end||start>=size;partial=YES;
        }
        int status=!exists?404:badRange?416:partial?206:200;
        unsigned long long length=status<300&&size?end-start+1:0;
        NSDictionary *mime=@{@"html":@"text/html; charset=utf-8",@"js":@"application/javascript",@"wasm":@"application/wasm",@"css":@"text/css",@"json":@"application/json",@"zip":@"application/zip"};
        NSMutableString *header=[NSMutableString stringWithFormat:@"HTTP/1.1 %d %@\r\nContent-Type: %@\r\nContent-Length: %llu\r\nConnection: close\r\nAccept-Ranges: bytes\r\nCross-Origin-Opener-Policy: same-origin\r\nCross-Origin-Embedder-Policy: require-corp\r\nCache-Control: no-store\r\n",status,status==200?@"OK":status==206?@"Partial Content":status==416?@"Range Not Satisfiable":@"Not Found",mime[file.pathExtension]?:@"application/octet-stream",length];
        if(status==206)[header appendFormat:@"Content-Range: bytes %llu-%llu/%llu\r\n",start,end,size];
        if(status==416)[header appendFormat:@"Content-Range: bytes */%llu\r\n",size];
        [header appendString:@"\r\n"];NSData *head=[header dataUsingEncoding:NSUTF8StringEncoding];
        const uint8_t *cursor=head.bytes;NSUInteger remaining=head.length;
        while(remaining){ssize_t n=send(client,cursor,remaining,0);if(n<=0)return;cursor+=n;remaining-=n;}
        if([first[0] isEqual:@"HEAD"]||!length)return;
        FILE *input=fopen(file.fileSystemRepresentation,"rb");if(!input)return;
        fseeko(input,(off_t)start,SEEK_SET);char block[65536];
        while(length){size_t n=fread(block,1,(size_t)MIN(length,sizeof(block)),input);if(!n)break;
            size_t at=0;while(at<n){ssize_t written=send(client,block+at,n-at,0);if(written<=0){fclose(input);return;}at+=(size_t)written;}length-=n;}
        fclose(input);
    } @finally { close(client); }
}
- (BOOL)start {
    int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0)return NO;
    int reuse=1;setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&reuse,sizeof(reuse));
    struct sockaddr_in address={0};address.sin_len=sizeof(address);address.sin_family=AF_INET;
    // IndexedDB is keyed by origin. A random port would hide Wine saves on
    // each launch; retain a stable local origin and fail visibly on conflict.
    address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);address.sin_port=htons(49682);
    if(bind(fd,(struct sockaddr *)&address,sizeof(address))||listen(fd,8)){close(fd);return NO;}
    socklen_t length=sizeof(address);if(getsockname(fd,(struct sockaddr *)&address,&length)){close(fd);return NO;}
    self.listener=fd;self.port=ntohs(address.sin_port);
    __weak TTLocalRuntimeServer *weak=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        while(YES){int client=accept(fd,NULL,NULL);if(client<0)break;
            TTLocalRuntimeServer *owner=weak;if(!owner){close(client);break;}
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{@autoreleasepool{[owner serve:client];}});}
    });return YES;
}
@end

// WKUserContentController retains its handler. Keep that ownership from
// retaining the whole game controller and its listening socket indefinitely.
@interface TTWeakRuntimeHandler : NSObject<WKScriptMessageHandler>
@property(weak) id<WKScriptMessageHandler> target;
@end
@implementation TTWeakRuntimeHandler
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    [self.target userContentController:controller didReceiveScriptMessage:message];
}
@end

@interface TTWebRuntimeController : UIViewController<WKScriptMessageHandler,WKNavigationDelegate>
@property(copy) NSString *slot;
@property(strong) TTLocalRuntimeServer *server;
@property(strong) WKWebView *web;
@property(strong) NSFileHandle *log;
@property(strong) UILabel *failureLabel;
@property(copy) void (^returnToLibrary)(void);
@property(assign) BOOL leaving;
@end
@implementation TTWebRuntimeController
- (void)stopRuntime {
    WKWebView *web=self.web;self.web=nil;
    web.navigationDelegate=nil;
    [web.configuration.userContentController removeScriptMessageHandlerForName:@"tontonRuntime"];
    [web stopLoading];[web removeFromSuperview];
    [self.server stop];self.server=nil;
    [self.log closeFile];self.log=nil;
}
- (void)dealloc {
    [self.web.configuration.userContentController removeScriptMessageHandlerForName:@"tontonRuntime"];
    [self.server stop];
    [self.log closeFile];
}
- (void)confirmReturn {
    if(self.leaving||self.presentedViewController)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"\u8FD4\u56DE\u6E38\u620F\u5323"
        message:@"\u8BF7\u5148\u5728\u6E38\u620F\u4E2D\u4FDD\u5B58\u3002\u672A\u4FDD\u5B58\u7684\u8FDB\u5EA6\u5C06\u4E22\u5931\u3002"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53D6\u6D88" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:@"\u9000\u51FA\u6E38\u620F" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        typeof(self) owner=weakSelf;
        if(!owner||owner.leaving)return;
        owner.leaving=YES;
        [owner writeLog:@"Returning to TonTon after the player's confirmation."];
        [owner stopRuntime];
        void (^returned)(void)=owner.returnToLibrary;owner.returnToLibrary=nil;
        if(returned)returned();
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (void)writeLog:(NSString *)text {
    NSData *data=[[[NSDate.date description] stringByAppendingFormat:@" %@\n",text] dataUsingEncoding:NSUTF8StringEncoding];
    @try{[self.log writeData:data];[self.log synchronizeFile];}@catch(NSException *e){}
}
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.systemBackgroundColor;
    NSString *folder=[self.slot stringByAppendingPathComponent:@"UserData/Logs"];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path=[folder stringByAppendingPathComponent:[NSString stringWithFormat:@"runtime-%.0f.log",NSDate.date.timeIntervalSince1970*1000]];
    [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];self.log=[NSFileHandle fileHandleForWritingAtPath:path];
    self.server=[TTLocalRuntimeServer new];self.server.slot=self.slot;
    if(![self.server start]){
        [self writeLog:@"loopback listener failed"];
        UILabel *error=[UILabel new];error.frame=CGRectInset(self.view.bounds,32,32);
        error.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        error.numberOfLines=0;error.textAlignment=NSTextAlignmentCenter;
        error.text=@"运行层启动失败，请关闭游戏匣后重试。游戏与存档已保留。";
        [self.view addSubview:error];return;
    }
    WKWebViewConfiguration *config=[WKWebViewConfiguration new];config.allowsInlineMediaPlayback=YES;
    config.mediaTypesRequiringUserActionForPlayback=WKAudiovisualMediaTypeNone;
    // Persistent WebKit data is retained by the same app; never use a throwaway
    // store for Wine's writable prefix or saves.
    config.websiteDataStore=WKWebsiteDataStore.defaultDataStore;
    TTWeakRuntimeHandler *handler=[TTWeakRuntimeHandler new];handler.target=self;
    [config.userContentController addScriptMessageHandler:handler name:@"tontonRuntime"];
    NSString *trace=@"(()=>{const send=(kind,args)=>{try{window.webkit.messageHandlers.tontonRuntime.postMessage({kind,text:Array.from(args).map(x=>String(x)).join(' ').slice(0,12000)})}catch(e){}};for(const k of ['log','warn','error']){const old=console[k];console[k]=function(...a){send(k,a);old.apply(console,a)}};window.addEventListener('error',e=>send('exception',[e.message,e.filename,e.lineno,e.colno,e.error&&e.error.stack]),true);window.addEventListener('unhandledrejection',e=>send('rejection',[e.reason&&e.reason.stack||e.reason]));})();";
    [config.userContentController addUserScript:[[WKUserScript alloc] initWithSource:trace injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
    self.web=[[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.web.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;self.web.navigationDelegate=self;
    [self.view addSubview:self.web];
    if(self.returnToLibrary){
        UIButton *back=[UIButton buttonWithType:UIButtonTypeSystem];
        back.configuration=[UIButtonConfiguration tintedButtonConfiguration];
        back.configuration.image=[UIImage systemImageNamed:@"rectangle.portrait.and.arrow.right"];
        back.accessibilityLabel=@"\u8FD4\u56DE\u6E38\u620F\u5323";
        [back addTarget:self action:@selector(confirmReturn) forControlEvents:UIControlEventTouchUpInside];
        back.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:back];
        UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [back.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
            [back.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
            [back.widthAnchor constraintEqualToConstant:44],[back.heightAnchor constraintEqualToConstant:44]]];
    }
    NSURLComponents *url=[NSURLComponents componentsWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/boxedwine.html",self.server.port]];
    NSMutableArray *query=[NSMutableArray new];
    // The owned ZIP is mounted as C:\\files. Register its COM server in Wine's
    // normal persistent prefix before starting; a successful ZIP import alone
    // does not install this dependency. Stop if registration fails.
    NSDictionary *options=@{@"root":@"boxedwine",@"app":@"ra2-ea-full",@"p":@"cmd.exe",@"args":@"/c regsvr32.exe /s Blowfish.dll && gamemd.exe",@"app-range":@"true",@"resolution":@"1024x768",@"bpp":@"16",@"auto":@"true",@"env":@"WINEDLLOVERRIDES:ddraw=n,b;dsound,wsock32,wined3d=b"};
    for(NSString *key in options)[query addObject:[NSURLQueryItem queryItemWithName:key value:options[key]]];
    url.queryItems=query;[self writeLog:@"Starting bundled BoxedWine with owned full EA resources; runtime compatibility remains experimental."];
    [self.web loadRequest:[NSURLRequest requestWithURL:url.URL]];
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    if([message.body isKindOfClass:NSDictionary.class])[self writeLog:[NSString stringWithFormat:@"%@: %@",message.body[@"kind"],message.body[@"text"]]];
}
- (void)showRuntimeFailure {
    // Keep the persistent Wine store and the diagnostic report. A terminated
    // content process must not leave an unexplained blank view or reload loop.
    [self.web stopLoading];self.web.hidden=YES;
    if(self.failureLabel)return;
    UILabel *label=[UILabel new];label.frame=CGRectInset(self.view.bounds,32,32);
    label.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    label.numberOfLines=0;label.textAlignment=NSTextAlignmentCenter;label.textColor=UIColor.labelColor;
    label.text=@"运行层已停止，日志已保留。\n请关闭并重新打开游戏匣。";
    self.failureLabel=label;[self.view addSubview:label];
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [self writeLog:@"WebKit content process terminated; inspect memory/crash report. No automatic reload."];
    [self showRuntimeFailure];
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self writeLog:error.description];if(error.code!=NSURLErrorCancelled)[self showRuntimeFailure];
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self writeLog:error.description];if(error.code!=NSURLErrorCancelled)[self showRuntimeFailure];
}
@end
UIViewController *TonTonWebRuntimeController(NSString *title,NSString *slot) {
    return TonTonWebRuntimeControllerWithReturn(title,slot,nil);
}
UIViewController *TonTonWebRuntimeControllerWithReturn(NSString *title,NSString *slot,void (^returnToLibrary)(void)) {
    if(!TonTonWebRuntimeAvailable(title,slot))return nil;
    TTWebRuntimeController *controller=[TTWebRuntimeController new];controller.slot=slot;controller.returnToLibrary=returnToLibrary;return controller;
}

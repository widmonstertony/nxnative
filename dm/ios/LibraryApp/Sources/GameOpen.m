#import "GameOpen.h"
// Preview bridge to the owner's already-running on-device MCP service.
// The final single-bundle runtime will select game data directly and will not
// need this bridge. It never installs/removes or modifies a game.
static NSDictionary *call(NSString *name, NSDictionary *arguments) {
    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:8090/mcp"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 8;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json, text/event-stream" forHTTPHeaderField:@"Accept"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{ @"jsonrpc": @"2.0", @"id": @1,
        @"method": @"tools/call", @"params": @{ @"name": name, @"arguments": arguments } } options:0 error:nil];
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    __block NSDictionary *reply;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)response;
        if (!error && data) reply = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        dispatch_semaphore_signal(finished);
    }];
    [task resume];
    if (dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 9 * NSEC_PER_SEC))) { [task cancel]; return nil; }
    NSDictionary *result = [reply[@"result"] isKindOfClass:NSDictionary.class] ? reply[@"result"] : nil;
    if ([result[@"isError"] boolValue] || reply[@"error"]) return nil;
    return [result[@"structuredContent"] isKindOfClass:NSDictionary.class] ? result[@"structuredContent"] : result;
}
NSSet<NSString *> *NXInstalledGames(void) {
    NSDictionary *result = call(@"list_apps", @{});
    NSMutableSet *ids = [NSMutableSet set];
    for (NSDictionary *app in result[@"apps"]) {
        NSString *bundle = app[@"bundleId"];
        if ([bundle isKindOfClass:NSString.class]) [ids addObject:bundle];
    }
    return ids;
}
BOOL NXOpenInstalledGame(NSString *bundleID) {
    NSDictionary *result = call(@"launch_app", @{ @"bundle_id": bundleID });
    return result != nil;
}

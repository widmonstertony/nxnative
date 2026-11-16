#import <UIKit/UIKit.h>

// Local, bundled browser runtimes run inside TonTon. No separate application
// or LAN server is used. A slot owns its game files and persistent web data.
BOOL TonTonWebRuntimeAvailable(NSString *title, NSString *slot);
UIViewController *TonTonWebRuntimeController(NSString *title, NSString *slot);
UIViewController *TonTonWebRuntimeControllerWithReturn(NSString *title, NSString *slot, void (^returnToLibrary)(void));

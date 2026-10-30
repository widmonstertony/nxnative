#import <UIKit/UIKit.h>

// Embedded host variant: only profiles whose resources are in Documents/Games
// appear. The callback is invoked before guest preload in the same app process.
UIViewController *TonTonLibraryController(void (^startGame)(NSString *titleID));

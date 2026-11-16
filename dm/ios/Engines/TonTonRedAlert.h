#import <UIKit/UIKit.h>

BOOL TonTonRedAlertTitle(NSString *title);
BOOL TonTonRedAlertIsActive(void);
NSDictionary *TonTonRedAlertReadiness(NSString *title, NSString *frameworksRoot);
UIViewController *TonTonRedAlertController(NSString *title, void (^finished)(void));

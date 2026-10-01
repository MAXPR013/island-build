// TestMini - barebones launch test for iOS 6 (armv7, SDK-free)
#include "dschat_mini.h"

@interface MiniDelegate : NSObject <UIApplicationDelegate> {
    UIWindow *_w;
}
@end

@implementation MiniDelegate
- (BOOL)application:(id)app didFinishLaunchingWithOptions:(id)opts {
    CGRect b = [[UIScreen mainScreen] bounds];
    _w = [[UIWindow alloc] initWithFrame:b];
    _w.backgroundColor = [UIColor whiteColor];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(20, 220, 280, 40)];
    l.text = @"MINI OK - launch works";
    l.textAlignment = UITextAlignmentCenter;
    [_w addSubview:l];
    [_w makeKeyAndVisible];
    return YES;
}
- (void)dealloc { [_w release]; [super dealloc]; }
@end

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int ret = UIApplicationMain(argc, argv, nil, @"MiniDelegate");
    [pool release];
    return ret;
}

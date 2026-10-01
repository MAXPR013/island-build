// TestMini D: table with custom delegate/datasource + plain field (armv7, SDK-free)
#include "dschat_mini.h"

@interface MiniDelegate : NSObject <UIApplicationDelegate, UITableViewDataSource, UITableViewDelegate> {
    UIWindow *_w;
    UITableView *_t;
}
@end

@implementation MiniDelegate
- (BOOL)application:(id)app didFinishLaunchingWithOptions:(id)opts {
    CGRect b = [[UIScreen mainScreen] bounds];
    _w = [[UIWindow alloc] initWithFrame:b];
    _w.backgroundColor = [UIColor whiteColor];
    _t = [[UITableView alloc] initWithFrame:CGRectMake(0, 20, b.size.width, 200) style:UITableViewStylePlain];
    _t.dataSource = self;
    _t.delegate = self;
    [_w addSubview:_t];
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(20, 260, 280, 32)];
    f.borderStyle = UITextBorderStyleRoundedRect;
    f.placeholder = @"tap me";
    [_w addSubview:f];
    [_w makeKeyAndVisible];
    return YES;
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return 1; }
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip { return 44.0f; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"c";
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid] autorelease];
    return cell;
}
- (void)dealloc { [_w release]; [_t release]; [super dealloc]; }
@end

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int ret = UIApplicationMain(argc, argv, nil, @"MiniDelegate");
    [pool release];
    return ret;
}

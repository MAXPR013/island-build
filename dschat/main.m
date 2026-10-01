// DSChat - DeepSeek chat client for iOS 6 (armv7)
// No ARC, NSURLConnection, single-file build, SDK-free (mini headers + dynamic_lookup).
#include "dschat_mini.h"
#include <signal.h>

// ---- 坠机记录仪 ----
static void writeCrashTo(id text, NSString *fname) {
    @autoreleasepool {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString *p = [docs stringByAppendingPathComponent:fname];
        [text writeToFile:p atomically:YES encoding:4 error:NULL];
    }
}

static void writeCrash(id text) {
    writeCrashTo(text, @"crash.txt");
}

static void exHandler(NSException *e) {
    writeCrashTo([NSString stringWithFormat:@"EXCEPTION: %@ / %@\n%@", [e name], [e reason], [[e callStackSymbols] description]], @"exception.txt");
}

extern void NSSetUncaughtExceptionHandler(void *h);
extern int backtrace(void **buffer, int size);
extern char **backtrace_symbols(void *const *buffer, int size);
extern void free(void *ptr);

static void sigHandler2(int sig) {
    void *bt[40];
    int n = backtrace(bt, 40);
    char **syms = backtrace_symbols(bt, n);
    NSMutableString *s = [[NSMutableString alloc] initWithFormat:@"SIGNAL %d\n", sig];
    if (syms) {
        for (int i = 0; i < n; i++) [s appendFormat:@"%s\n", syms[i]];
        free(syms);
    }
    writeCrash(s);
    [s release];
    signal(sig, SIG_DFL);
    raise(sig);
}

#pragma mark - Bubble cell

@interface ChatCell : UITableViewCell {
    UILabel *_bubble;
}
- (void)setMessage:(NSString *)text isUser:(BOOL)isUser width:(CGFloat)width;
+ (CGFloat)heightFor:(NSString *)text width:(CGFloat)width;
@end

#define kBubbleFont [UIFont systemFontOfSize:15.0f]

@implementation ChatCell

- (id)initWithStyle:(NSInteger)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _bubble = [[UILabel alloc] initWithFrame:CGRectZero];
        _bubble.font = kBubbleFont;
        _bubble.numberOfLines = 0;
        _bubble.lineBreakMode = UILineBreakModeWordWrap;
        _bubble.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_bubble];
    }
    return self;
}

+ (CGFloat)heightFor:(NSString *)text width:(CGFloat)width {
    CGSize s = [text sizeWithFont:kBubbleFont constrainedToSize:CGSizeMake(width - 100.0f, 9999.0f) lineBreakMode:UILineBreakModeWordWrap];
    return s.height + 24.0f;
}

- (void)setMessage:(NSString *)text isUser:(BOOL)isUser width:(CGFloat)width {
    CGSize s = [text sizeWithFont:kBubbleFont constrainedToSize:CGSizeMake(width - 100.0f, 9999.0f) lineBreakMode:UILineBreakModeWordWrap];
    CGFloat x = isUser ? (width - s.width - 26.0f) : 16.0f;
    _bubble.frame = CGRectMake(x, 8.0f, s.width + 10.0f, s.height + 8.0f);
    _bubble.text = text;
    _bubble.textColor = isUser ? [UIColor whiteColor] : [UIColor blackColor];
    _bubble.backgroundColor = isUser ? [UIColor colorWithRed:0.20f green:0.45f blue:0.95f alpha:1.0f]
                                     : [UIColor colorWithWhite:0.88f alpha:1.0f];
    _bubble.layer.cornerRadius = 10.0f;
    _bubble.layer.masksToBounds = YES;
    _bubble.textAlignment = UITextAlignmentLeft;
}

- (void)dealloc {
    [_bubble release];
    [super dealloc];
}

@end

#pragma mark - Chat view controller

@interface ChatViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, NSURLConnectionDelegate> {
    UITableView *_table;
    UIView *_inputBar;
    UITextField *_field;
    UIButton *_sendBtn;
    UIActivityIndicatorView *_spin;
    NSMutableArray *_msgs;       // dicts: role, content
    NSMutableData *_buf;
    NSURLConnection *_conn;
    NSString *_apiKey;
    BOOL _waiting;
}
@end

@implementation ChatViewController

static void MARK(const char *stage) {
    @autoreleasepool {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString *p = [docs stringByAppendingPathComponent:@"stage.txt"];
        [[NSString stringWithFormat:@"%s", stage] writeToFile:p atomically:YES encoding:4 error:NULL];
    }
}

- (void)loadView {
    MARK("10_loadView_begin");
    CGRect f = [UIScreen mainScreen].applicationFrame;
    UIView *v = [[UIView alloc] initWithFrame:f];
    v.backgroundColor = [UIColor whiteColor];
    self.view = [v autorelease];
    MARK("11_view_set");

    _table = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, f.size.width, f.size.height - 48.0f) style:UITableViewStylePlain];
    _table.dataSource = self;
    _table.delegate = self;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.allowsSelection = NO;
    [self.view addSubview:_table];
    MARK("12_table_added");

    _inputBar = [[UIView alloc] initWithFrame:CGRectMake(0, f.size.height - 48.0f, f.size.width, 48.0f)];
    _inputBar.backgroundColor = [UIColor colorWithWhite:0.95f alpha:1.0f];
    _field = [[UITextField alloc] initWithFrame:CGRectMake(8, 8, f.size.width - 92, 32)];
    _field.borderStyle = UITextBorderStyleRoundedRect;
    _field.placeholder = @"说点什么…";
    _field.returnKeyType = UIReturnKeySend;
    [_field addTarget:self action:@selector(fieldBegan) forControlEvents:UIControlEventEditingDidBegin];
    [_field addTarget:self action:@selector(fieldEnded) forControlEvents:UIControlEventEditingDidEnd];
    [_field addTarget:self action:@selector(sendPressed) forControlEvents:UIControlEventEditingDidEndOnExit];
    [_inputBar addSubview:_field];
    MARK("13_field_added");
    _sendBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _sendBtn.frame = CGRectMake(f.size.width - 78, 8, 70, 32);
    [_sendBtn setTitle:@"发送" forState:UIControlStateNormal];
    [_sendBtn addTarget:self action:@selector(sendPressed) forControlEvents:UIControlEventTouchUpInside];
    [_inputBar addSubview:_sendBtn];
    _spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spin.center = CGPointMake(f.size.width - 96, 24);
    _spin.hidesWhenStopped = YES;
    [_inputBar addSubview:_spin];
    [self.view addSubview:_inputBar];
    MARK("14_inputbar_done");
}

- (void)slideInputUp:(BOOL)up {
    CGFloat kh = up ? 216.0f : 0.0f;   // iOS 6 竖屏键盘固定高
    CGRect f = self.view.frame;
    _table.frame = CGRectMake(0, 0, f.size.width, f.size.height - 48.0f - kh);
    _inputBar.frame = CGRectMake(0, f.size.height - 48.0f - kh, f.size.width, 48.0f);
}

- (void)fieldBegan {
    [self slideInputUp:YES];
}

- (void)fieldEnded {
    [self slideInputUp:NO];
}

- (void)scrollViewWillBeginDragging:(id)sv {
    [_field resignFirstResponder];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    MARK("20_vdl_begin");
    _msgs = [[NSMutableArray alloc] init];
    _buf = [[NSMutableData alloc] init];

    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *keyPath = [docs stringByAppendingPathComponent:@"apikey.txt"];
    _apiKey = [[[NSString stringWithContentsOfFile:keyPath encoding:NSUTF8StringEncoding error:NULL]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] retain];
    MARK("21_key_loaded");

    if ([_apiKey length] == 0) {
        [_msgs addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"assistant", @"role",
            @"没有读到 apikey.txt，请检查注入是否成功。", @"content", nil]];
    } else {
        [_msgs addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"assistant", @"role",
            @"你好，我是 DeepSeek，跑在 2011 年的 iPhone 4S 上。有何贵干？", @"content", nil]];
    }
    MARK("22_msgs_ready");
}

- (void)kbShow:(NSNotification *)n {
    CGRect kr = [[[n userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat kh = kr.size.height;
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.25];
    CGRect f = self.view.frame;
    _table.frame = CGRectMake(0, 0, f.size.width, f.size.height - 48.0f - kh);
    _inputBar.frame = CGRectMake(0, f.size.height - 48.0f - kh, f.size.width, 48.0f);
    [UIView commitAnimations];
    [self scrollToBottom];
}

- (void)kbHide:(NSNotification *)n {
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:0.25];
    CGRect f = self.view.frame;
    _table.frame = CGRectMake(0, 0, f.size.width, f.size.height - 48.0f);
    _inputBar.frame = CGRectMake(0, f.size.height - 48.0f, f.size.width, 48.0f);
    [UIView commitAnimations];
}

- (void)scrollToBottom {
    NSInteger n = [_msgs count];
    if (n > 0) {
        [_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:n - 1 inSection:0]
                      atScrollPosition:UITableViewScrollPositionBottom animated:YES];
    }
}

- (void)sendPressed {
    NSString *text = [_field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text length] == 0 || _waiting) return;
    if ([_apiKey length] == 0) return;
    [_field resignFirstResponder];
    _field.text = @"";
    [_msgs addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"user", @"role", text, @"content", nil]];
    [_table reloadData];
    [self scrollToBottom];
    _waiting = YES;
    _sendBtn.enabled = NO;
    [_spin startAnimating];

    // build messages array for API (history + new)
    NSMutableArray *apiMsgs = [NSMutableArray array];
    [apiMsgs addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"system", @"role",
        @"你是 DeepSeek，一个乐于助人的 AI 助手。请用简体中文回答，回答尽量简洁。", @"content", nil]];
    for (NSDictionary *m in _msgs) {
        NSString *r = [m objectForKey:@"role"];
        if ([r isEqualToString:@"user"] || [r isEqualToString:@"assistant"]) {
            [apiMsgs addObject:m];
        }
    }
    NSDictionary *body = [NSDictionary dictionaryWithObjectsAndKeys:
        @"deepseek-chat", @"model",
        apiMsgs, @"messages",
        [NSNumber numberWithBool:NO], @"stream",
        nil];
    NSData *json = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://api.deepseek.com/chat/completions"]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 90.0;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", _apiKey] forHTTPHeaderField:@"Authorization"];
    req.HTTPBody = json;

    [_buf setLength:0];
    [_conn release];
    _conn = [[NSURLConnection alloc] initWithRequest:req delegate:self startImmediately:YES];
}

#pragma mark UITableView

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [_msgs count]; }

- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *m = [_msgs objectAtIndex:ip.row];
    return [ChatCell heightFor:[m objectForKey:@"content"] width:t.frame.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    static int laid = 0;
    if (!laid) { laid = 1; MARK("30_first_cell"); }
    static NSString *cid = @"c";
    ChatCell *cell = [t dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[[ChatCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid] autorelease];
    NSDictionary *m = [_msgs objectAtIndex:ip.row];
    [cell setMessage:[m objectForKey:@"content"] isUser:[[m objectForKey:@"role"] isEqualToString:@"user"] width:t.frame.size.width];
    return cell;
}

#pragma mark UITextField

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [self sendPressed];
    return YES;
}

#pragma mark NSURLConnection

- (void)connection:(NSURLConnection *)c didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)ch {
    // iOS 6 (2012) root store may not know the CA of api.deepseek.com; trust anyway.
    if ([ch.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        [[ch sender] useCredential:[NSURLCredential credentialForTrust:ch.protectionSpace.serverTrust]
        forAuthenticationChallenge:ch];
    } else {
        [[ch sender] continueWithoutCredentialForAuthenticationChallenge:ch];
    }
}

- (BOOL)connection:(NSURLConnection *)c canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)space {
    return YES;
}

- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)data {
    [_buf appendData:data];
}

- (void)finishWaiting {
    _waiting = NO;
    _sendBtn.enabled = YES;
    [_spin stopAnimating];
}

- (void)appendAssistant:(NSString *)text {
    [_msgs addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"assistant", @"role", text, @"content", nil]];
    [_table reloadData];
    [self scrollToBottom];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)c {
    [self finishWaiting];
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:_buf options:0 error:&err];
    NSString *reply = nil;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSArray *choices = [obj objectForKey:@"choices"];
        if ([choices count] > 0) {
            reply = [[[choices objectAtIndex:0] objectForKey:@"message"] objectForKey:@"content"];
        } else if ([obj objectForKey:@"error"]) {
            reply = [NSString stringWithFormat:@"API 报错：%@", [[obj objectForKey:@"error"] objectForKey:@"message"]];
        }
    }
    if (!reply) reply = [NSString stringWithFormat:@"（解析失败，原始返回 %u 字节）", (unsigned int)[_buf length]];
    [self appendAssistant:reply];
}

- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)error {
    [self finishWaiting];
    [self appendAssistant:[NSString stringWithFormat:@"网络错误：%@（code %d）\n检查 WiFi 或告诉我截图。",
        [error localizedDescription], (int)[error code]]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_table release]; [_inputBar release]; [_field release]; [_spin release];
    [_msgs release]; [_buf release]; [_conn release]; [_apiKey release];
    [super dealloc];
}

@end

#pragma mark - App delegate

@interface AppDelegate : NSObject <UIApplicationDelegate> {
    UIWindow *_window;
}
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    MARK("01_appdelegate_begin");
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    MARK("02_window_made");
    ChatViewController *vc = [[[ChatViewController alloc] init] autorelease];
    MARK("03_vc_made");
    [_window addSubview:vc.view];
    MARK("04_vc_view_added");
    [_window makeKeyAndVisible];
    MARK("05_visible");
    return YES;
}
- (void)dealloc { [_window release]; [super dealloc]; }
@end

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSSetUncaughtExceptionHandler((void *)exHandler);
    signal(SIGABRT, sigHandler2);
    signal(SIGSEGV, sigHandler2);
    int ret = UIApplicationMain(argc, argv, nil, @"AppDelegate");
    [pool release];
    return ret;
}

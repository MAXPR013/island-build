// DSChat v14 - DeepSeek chat client for iOS 6 (armv7)
// 架构：TestMini 验证过的安全区 —— NSObject AppDelegate 直管一切
// 无 UIViewController、无 UITableView、无自定义 delegate（这台 iOS 6 上的三大雷区）
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

static void exHandler(NSException *e) {
    writeCrashTo([NSString stringWithFormat:@"EXCEPTION: %@ / %@\n%@", [e name], [e reason], [[e callStackSymbols] description]], @"exception.txt");
}

static void MARK(const char *stage) {
    writeCrashTo([NSString stringWithFormat:@"%s", stage], @"stage.txt");
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
    writeCrashTo(s, @"crash.txt");
    [s release];
    signal(sig, SIG_DFL);
    raise(sig);
}

// ---- 主控（NSObject，直管窗口与全部控件）----
@interface AppDelegate : NSObject <UIApplicationDelegate, NSURLConnectionDelegate> {
    UIWindow *_window;
    UITextView *_log;
    UITextField *_field;
    UIButton *_sendBtn;
    UIActivityIndicatorView *_spin;
    NSMutableString *_history;
    NSMutableArray *_msgs;       // 给 API 用的角色化消息
    NSMutableData *_buf;
    NSURLConnection *_conn;
    NSString *_apiKey;
    BOOL _waiting;
}
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    MARK("01_start");
    CGRect b = [[UIScreen mainScreen] bounds];
    CGFloat w = b.size.width, h = b.size.height;
    _window = [[UIWindow alloc] initWithFrame:b];
    _window.backgroundColor = [UIColor whiteColor];
    MARK("02_window");

    _log = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, w, h - 48.0f)];
    MARK("03_tv_alloc");
    _log.editable = NO;
    _log.font = [UIFont systemFontOfSize:15.0f];
    [_window addSubview:_log];
    MARK("04_tv_added");

    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, h - 48.0f, w, 48.0f)];
    bar.backgroundColor = [UIColor colorWithWhite:0.95f alpha:1.0f];
    bar.tag = 4242;   // 用 tag 找它，不留额外 ivar 依赖
    [_window addSubview:bar];
    MARK("05_bar");

    _field = [[UITextField alloc] initWithFrame:CGRectMake(8, 8, w - 92, 32)];
    _field.borderStyle = UITextBorderStyleRoundedRect;
    _field.placeholder = @"说点什么…";
    _field.returnKeyType = UIReturnKeySend;
    MARK("06_field");
    [_field addTarget:self action:@selector(fieldBegan) forControlEvents:UIControlEventEditingDidBegin];
    [_field addTarget:self action:@selector(fieldEnded) forControlEvents:UIControlEventEditingDidEnd];
    [_field addTarget:self action:@selector(sendPressed) forControlEvents:UIControlEventEditingDidEndOnExit];
    [bar addSubview:_field];
    MARK("07_field_wired");

    _sendBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _sendBtn.frame = CGRectMake(w - 78, 8, 70, 32);
    [_sendBtn setTitle:@"发送" forState:UIControlStateNormal];
    [_sendBtn addTarget:self action:@selector(sendPressed) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:_sendBtn];
    MARK("08_button");

    _spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spin.center = CGPointMake(w - 96, 24);
    _spin.hidesWhenStopped = YES;
    [bar addSubview:_spin];
    MARK("09_spin");

    [_window makeKeyAndVisible];
    MARK("10_visible");

    _msgs = [[NSMutableArray alloc] init];
    _buf = [[NSMutableData alloc] init];
    _history = [[NSMutableString alloc] init];
    MARK("11_arrays");

    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *keyPath = [docs stringByAppendingPathComponent:@"apikey.txt"];
    _apiKey = [[[NSString stringWithContentsOfFile:keyPath encoding:NSUTF8StringEncoding error:NULL]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] retain];
    MARK("12_key");

    if ([_apiKey length] == 0) {
        [self appendLine:@"系统" text:@"没有读到 apikey.txt，请检查注入是否成功。"];
    } else {
        [self appendLine:@"DeepSeek" text:@"你好，我是 DeepSeek，跑在 2011 年的 iPhone 4S 上。有何贵干？"];
    }
    MARK("13_firstline");
    return YES;
}

- (void)appendLine:(NSString *)who text:(NSString *)text {
    if ([_history length] > 0) [_history appendString:@"\n\n"];
    [_history appendFormat:@"%@：%@", who, text];
    _log.text = _history;
    // 滚到底
    NSRange r; r.location = [_history length]; r.length = 0;
    [_log scrollRangeToVisible:r];
}

- (void)fieldBegan {
    CGRect b = _window.frame;
    CGFloat kh = 216.0f;   // iOS 6 竖屏键盘
    _log.frame = CGRectMake(0, 0, b.size.width, b.size.height - 48.0f - kh);
    UIView *bar = [_window viewWithTag:4242];
    bar.frame = CGRectMake(0, b.size.height - 48.0f - kh, b.size.width, 48.0f);
    NSRange r; r.location = [_history length]; r.length = 0;
    [_log scrollRangeToVisible:r];
}

- (void)fieldEnded {
    CGRect b = _window.frame;
    _log.frame = CGRectMake(0, 0, b.size.width, b.size.height - 48.0f);
    UIView *bar = [_window viewWithTag:4242];
    bar.frame = CGRectMake(0, b.size.height - 48.0f, b.size.width, 48.0f);
}

- (void)sendPressed {
    NSString *text = [_field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text length] == 0 || _waiting) return;
    if ([_apiKey length] == 0) return;
    [_field resignFirstResponder];
    _field.text = @"";
    [self appendLine:@"我" text:text];
    [_msgs addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"user", @"role", text, @"content", nil]];
    _waiting = YES;
    _sendBtn.enabled = NO;
    [_spin startAnimating];

    NSMutableArray *apiMsgs = [NSMutableArray array];
    [apiMsgs addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"system", @"role",
        @"你是 DeepSeek，一个乐于助人的 AI 助手。请用简体中文回答，回答尽量简洁。", @"content", nil]];
    for (NSDictionary *m in _msgs) {
        [apiMsgs addObject:m];
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

#pragma mark NSURLConnection

- (void)connection:(NSURLConnection *)c didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)ch {
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

- (void)connectionDidFinishLoading:(NSURLConnection *)c {
    _waiting = NO;
    _sendBtn.enabled = YES;
    [_spin stopAnimating];
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:_buf options:0 error:&err];
    NSString *reply = nil;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSArray *choices = [obj objectForKey:@"choices"];
        if ([choices count] > 0) {
            reply = [[[choices objectAtIndex:0] objectForKey:@"message"] objectForKey:@"content"];
            [_msgs addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"assistant", @"role", reply, @"content", nil]];
        } else if ([obj objectForKey:@"error"]) {
            reply = [NSString stringWithFormat:@"API 报错：%@", [[obj objectForKey:@"error"] objectForKey:@"message"]];
        }
    }
    if (!reply) reply = [NSString stringWithFormat:@"（解析失败，原始返回 %u 字节）", (unsigned int)[_buf length]];
    [self appendLine:@"DeepSeek" text:reply];
}

- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)error {
    _waiting = NO;
    _sendBtn.enabled = YES;
    [_spin stopAnimating];
    [self appendLine:@"系统" text:[NSString stringWithFormat:@"网络错误：%@（code %d）",
        [error localizedDescription], (int)[error code]]];
}

- (void)dealloc {
    [_window release]; [_log release]; [_field release]; [_spin release];
    [_history release]; [_msgs release]; [_buf release]; [_conn release]; [_apiKey release];
    [super dealloc];
}
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

// DSChat v16 - DeepSeek chat client for iOS 6 (armv7)
// 最终版：状态栏避让 + 真实键盘高度 + Markdown 渲染（带纯文本兜底）
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
    NSMutableAttributedString *_rich;
    NSMutableArray *_msgs;
    NSMutableData *_buf;
    NSURLConnection *_conn;
    NSString *_apiKey;
    CGFloat _kbHeight;
    BOOL _waiting;
    BOOL _editing;
}
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    CGRect bf = [[UIScreen mainScreen] applicationFrame];   // 自动刨掉状态栏
    CGFloat top = bf.origin.y;
    CGFloat w = bf.size.width, h = bf.size.height;

    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    _window.backgroundColor = [UIColor whiteColor];

    _log = [[UITextView alloc] initWithFrame:CGRectMake(0, top, w, h - 48.0f)];
    _log.editable = NO;
    _log.font = [UIFont systemFontOfSize:15.0f];
    [_window addSubview:_log];

    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, top + h - 48.0f, w, 48.0f)];
    bar.backgroundColor = [UIColor colorWithWhite:0.95f alpha:1.0f];
    bar.tag = 4242;
    [_window addSubview:bar];
    [bar release];

    _field = [[UITextField alloc] initWithFrame:CGRectMake(8, 8, w - 92, 32)];
    _field.borderStyle = UITextBorderStyleRoundedRect;
    _field.placeholder = @"说点什么…";
    _field.returnKeyType = UIReturnKeySend;
    [_field addTarget:self action:@selector(fieldBegan) forControlEvents:UIControlEventEditingDidBegin];
    [_field addTarget:self action:@selector(fieldEnded) forControlEvents:UIControlEventEditingDidEnd];
    [_field addTarget:self action:@selector(sendPressed) forControlEvents:UIControlEventEditingDidEndOnExit];
    [bar addSubview:_field];

    _sendBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _sendBtn.frame = CGRectMake(w - 78, 8, 70, 32);
    [_sendBtn setTitle:@"发送" forState:UIControlStateNormal];
    [_sendBtn addTarget:self action:@selector(sendPressed) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:_sendBtn];

    _spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spin.center = CGPointMake(w - 96, 24);
    _spin.hidesWhenStopped = YES;
    [bar addSubview:_spin];

    // 键盘通知只用来读真实高度（isa 冤案昭雪后它是安全的）
    _kbHeight = 252.0f;   // 兜底：216 键盘 + 中文联想栏
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbShow:) name:UIKeyboardWillShowNotification object:nil];

    [_window makeKeyAndVisible];

    _msgs = [[NSMutableArray alloc] init];
    _buf = [[NSMutableData alloc] init];
    _rich = [[NSMutableAttributedString alloc] initWithString:@""];

    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *keyPath = [docs stringByAppendingPathComponent:@"apikey.txt"];
    _apiKey = [[[NSString stringWithContentsOfFile:keyPath encoding:NSUTF8StringEncoding error:NULL]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] retain];

    if ([_apiKey length] == 0) {
        [self appendLine:@"系统" text:@"没有读到 apikey.txt，请检查注入是否成功。"];
    } else {
        [self appendLine:@"DeepSeek" text:@"你好，我是 DeepSeek，跑在 2011 年的 iPhone 4S 上。有何贵干？"];
    }
    return YES;
}

#pragma mark - Markdown 迷你渲染

- (void)appendStyled:(NSMutableAttributedString *)outStr text:(NSString *)t font:(UIFont *)fnt shaded:(BOOL)shaded {
    if ([t length] == 0) return;
    NSMutableAttributedString *seg = [[[NSMutableAttributedString alloc] initWithString:t] autorelease];
    NSRange rr; rr.location = 0; rr.length = [t length];
    [seg addAttribute:@"NSFont" value:fnt range:rr];
    if (shaded) [seg addAttribute:@"NSBackgroundColor" value:[UIColor colorWithWhite:0.92f alpha:1.0f] range:rr];
    [outStr appendAttributedString:seg];
}

- (id)renderMD:(NSString *)md {
    NSMutableAttributedString *outStr = [[[NSMutableAttributedString alloc] initWithString:@""] autorelease];
    UIFont *normal = [UIFont systemFontOfSize:15.0f];
    UIFont *bold = [UIFont boldSystemFontOfSize:15.0f];
    UIFont *header = [UIFont boldSystemFontOfSize:18.0f];
    UIFont *mono = [UIFont fontWithName:@"Courier" size:14.0f];
    if (!mono) mono = normal;
    NSArray *lines = [md componentsSeparatedByString:@"\n"];
    BOOL inCode = NO;
    NSUInteger i;
    for (i = 0; i < [lines count]; i++) {
        NSString *line = [lines objectAtIndex:i];
        if ([line hasPrefix:@"```"]) { inCode = !inCode; continue; }
        UIFont *base = normal;
        NSString *work = line;
        if (inCode) base = mono;
        else if ([line hasPrefix:@"#### "]) { base = header; work = [line substringFromIndex:5]; }
        else if ([line hasPrefix:@"### "]) { base = header; work = [line substringFromIndex:4]; }
        else if ([line hasPrefix:@"## "]) { base = header; work = [line substringFromIndex:3]; }
        else if ([line hasPrefix:@"# "]) { base = header; work = [line substringFromIndex:2]; }
        // 行内 **粗体** 与 `行内码`
        NSArray *parts = [work componentsSeparatedByString:@"**"];
        BOOL isB = NO;
        NSUInteger j;
        for (j = 0; j < [parts count]; j++) {
            NSString *p = [parts objectAtIndex:j];
            NSArray *cparts = [p componentsSeparatedByString:@"`"];
            BOOL isC = NO;
            NSUInteger k;
            for (k = 0; k < [cparts count]; k++) {
                NSString *cp = [cparts objectAtIndex:k];
                UIFont *fnt = isC ? mono : (isB ? bold : base);
                [self appendStyled:outStr text:cp font:fnt shaded:(inCode || isC)];
                isC = !isC;
            }
            isB = !isB;
        }
        [self appendStyled:outStr text:@"\n" font:normal shaded:NO];
    }
    return outStr;
}

#pragma mark - 对话记录

- (void)appendLine:(NSString *)who text:(NSString *)text {
    [self appendStyled:_rich text:[NSString stringWithFormat:@"%@：\n", who]
                font:[UIFont boldSystemFontOfSize:14.0f] shaded:NO];
    [_rich appendAttributedString:[self renderMD:text]];
    _log.attributedText = _rich;
    NSRange r; r.location = [_rich length]; r.length = 0;
    [_log scrollRangeToVisible:r];
}

#pragma mark - 键盘

- (void)slideInput:(BOOL)up {
    CGFloat kh = up ? _kbHeight : 0.0f;
    CGRect bf = [[UIScreen mainScreen] applicationFrame];
    CGFloat top = bf.origin.y;
    _log.frame = CGRectMake(0, top, bf.size.width, bf.size.height - 48.0f - kh);
    UIView *bar = [_window viewWithTag:4242];
    bar.frame = CGRectMake(0, top + bf.size.height - 48.0f - kh, bf.size.width, 48.0f);
    if (up) {
        NSRange r; r.location = [_rich length]; r.length = 0;
        [_log scrollRangeToVisible:r];
    }
}

- (void)kbShow:(NSNotification *)n {
    CGRect kr = [[[n userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    if (kr.size.height > 0) _kbHeight = kr.size.height;   // 读到真实高度（含联想栏）
    if (_editing) [self slideInput:YES];
}

- (void)fieldBegan {
    _editing = YES;
    [self slideInput:YES];
}

- (void)fieldEnded {
    _editing = NO;
    [self slideInput:NO];
}

- (void)scrollViewWillBeginDragging:(id)sv {
    [_field resignFirstResponder];
}

#pragma mark - 发送与网络

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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_window release]; [_log release]; [_field release]; [_spin release];
    [_rich release]; [_msgs release]; [_buf release]; [_conn release]; [_apiKey release];
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

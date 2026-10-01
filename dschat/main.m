// DSChat v17 - DeepSeek chat client for iOS 6 (armv7)
// 大满贯：深度思考 / 流式输出 / 会话管理 / 拍照识图
// 架构：AppDelegate(NSObject) 直管 + 原厂 UIViewController 当壳（isa 平反后 containment 安全）
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

// ---- base64（iOS 6 没有现成的）----
static NSString *b64encode(NSData *d) {
    static const char t[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const unsigned char *in = (const unsigned char *)[d bytes];
    NSUInteger len = [d length];
    NSMutableString *s = [NSMutableString string];
    NSUInteger i;
    for (i = 0; i + 3 <= len; i += 3) {
        unsigned v = ((unsigned)in[i] << 16) | ((unsigned)in[i+1] << 8) | in[i+2];
        [s appendFormat:@"%c%c%c%c", t[v >> 18], t[(v >> 12) & 63], t[(v >> 6) & 63], t[v & 63]];
    }
    if (i < len) {
        unsigned v = ((unsigned)in[i] << 16) | (i + 1 < len ? ((unsigned)in[i+1] << 8) : 0);
        [s appendFormat:@"%c%c", t[v >> 18], t[(v >> 12) & 63]];
        [s appendString:(i + 1 < len) ? [NSString stringWithFormat:@"%c=", t[(v >> 6) & 63]] : @"=="];
    }
    return s;
}

@interface AppDelegate : NSObject <UIApplicationDelegate, NSURLConnectionDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIActionSheetDelegate, UIAlertViewDelegate> {
    UIWindow *_window;
    UIViewController *_shell;
    UITextView *_log;
    UITextField *_field;
    UIButton *_sendBtn;
    UIButton *_thinkBtn;
    UIActivityIndicatorView *_spin;
    UIImageView *_thumb;
    NSMutableAttributedString *_rich;
    NSMutableArray *_msgs;
    NSMutableData *_buf;
    NSURLConnection *_conn;
    NSString *_apiKey;
    NSString *_pendingImage;   // data URL
    NSString *_sessionId;
    NSMutableString *_streamText;
    NSMutableString *_streamThink;
    NSString *_streamBase;
    NSTimer *_streamTimer;
    UIButton *_kbOverlay;
    CGFloat _kbHeight;
    BOOL _waiting;
    BOOL _editing;
    BOOL _deepThink;
    BOOL _httpError;
    BOOL _streamDirty;
    NSInteger _alertMode;
}
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    CGRect bf = [[UIScreen mainScreen] applicationFrame];
    CGFloat top = 0;   // 壳视图的本地坐标系，状态栏偏移系统已处理
    CGFloat w = bf.size.width, h = bf.size.height;

    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    _window.backgroundColor = [UIColor whiteColor];
    _shell = [[UIViewController alloc] init];
    _window.rootViewController = _shell;

    _log = [[UITextView alloc] initWithFrame:CGRectMake(0, top, w, h - 48.0f)];
    _log.editable = NO;
    _log.font = [UIFont systemFontOfSize:15.0f];
    [_shell.view addSubview:_log];

    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, top + h - 48.0f, w, 48.0f)];
    bar.backgroundColor = [UIColor colorWithWhite:0.95f alpha:1.0f];
    bar.tag = 4242;
    [_shell.view addSubview:bar];
    [bar release];

    // [≡][深思][输入框][📷][发送]
    UIButton *menuBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    menuBtn.frame = CGRectMake(0, 8, 28, 32);
    [menuBtn setTitle:@"≡" forState:UIControlStateNormal];
    [menuBtn addTarget:self action:@selector(menuPressed) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:menuBtn];

    _thinkBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _thinkBtn.frame = CGRectMake(28, 8, 40, 32);
    [_thinkBtn setTitle:@"深思" forState:UIControlStateNormal];
    [_thinkBtn addTarget:self action:@selector(thinkPressed) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:_thinkBtn];

    _field = [[UITextField alloc] initWithFrame:CGRectMake(70, 8, 146, 32)];
    _field.borderStyle = UITextBorderStyleRoundedRect;
    _field.placeholder = @"说点什么…";
    _field.returnKeyType = UIReturnKeySend;
    [_field addTarget:self action:@selector(fieldBegan) forControlEvents:UIControlEventEditingDidBegin];
    [_field addTarget:self action:@selector(fieldEnded) forControlEvents:UIControlEventEditingDidEnd];
    [_field addTarget:self action:@selector(sendPressed) forControlEvents:UIControlEventEditingDidEndOnExit];
    [bar addSubview:_field];

    UIButton *photoBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    photoBtn.frame = CGRectMake(218, 8, 34, 32);
    [photoBtn setTitle:@"📷" forState:UIControlStateNormal];
    [photoBtn addTarget:self action:@selector(photoPressed) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:photoBtn];

    _sendBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _sendBtn.frame = CGRectMake(254, 8, 60, 32);
    [_sendBtn setTitle:@"发送" forState:UIControlStateNormal];
    [_sendBtn addTarget:self action:@selector(sendPressed) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:_sendBtn];

    _spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spin.center = CGPointMake(w - 22, top + 18);
    _spin.hidesWhenStopped = YES;
    [_shell.view addSubview:_spin];

    _thumb = [[UIImageView alloc] initWithFrame:CGRectMake(w - 54, top + h - 48 - 52, 46, 46)];
    _thumb.hidden = YES;
    [_shell.view addSubview:_thumb];

    // 键盘开启时盖在对话区上的透明回收层（点键盘外收键盘）
    _kbOverlay = [UIButton buttonWithType:0];   // Custom，全透明
    _kbOverlay.frame = CGRectMake(0, 0, w, h - 48.0f);
    _kbOverlay.hidden = YES;
    [_kbOverlay addTarget:self action:@selector(overlayTapped) forControlEvents:UIControlEventTouchUpInside];
    [_shell.view insertSubview:_kbOverlay belowSubview:[_shell.view viewWithTag:4242]];

    _kbHeight = 252.0f;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbShow:) name:UIKeyboardWillShowNotification object:nil];

    [_window makeKeyAndVisible];

    _msgs = [[NSMutableArray alloc] init];
    _buf = [[NSMutableData alloc] init];
    _rich = [[NSMutableAttributedString alloc] initWithString:@""];
    _streamText = [[NSMutableString alloc] init];
    _streamThink = [[NSMutableString alloc] init];

    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *keyPath = [docs stringByAppendingPathComponent:@"apikey.txt"];
    _apiKey = [[[NSString stringWithContentsOfFile:keyPath encoding:NSUTF8StringEncoding error:NULL]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] retain];

    [[NSFileManager defaultManager] createDirectoryAtPath:[docs stringByAppendingPathComponent:@"sessions"]
                              withIntermediateDirectories:YES attributes:nil error:NULL];

    if ([_apiKey length] == 0) {
        [self appendLine:@"系统" text:@"没有读到 apikey.txt，请检查注入是否成功。" isUser:NO];
    } else if (![self loadLatestSession]) {
        [self appendLine:@"DeepSeek" text:@"你好，我是 DeepSeek，跑在 2011 年的 iPhone 4S 上。有何贵干？" isUser:NO];
    }
    return YES;
}

#pragma mark - Markdown 迷你渲染

- (void)appendStyled:(NSMutableAttributedString *)outStr text:(NSString *)t font:(UIFont *)fnt shaded:(BOOL)shaded gray:(BOOL)gray {
    if ([t length] == 0) return;
    NSMutableAttributedString *seg = [[[NSMutableAttributedString alloc] initWithString:t] autorelease];
    NSRange rr; rr.location = 0; rr.length = [t length];
    [seg addAttribute:@"NSFont" value:fnt range:rr];
    if (shaded) [seg addAttribute:@"NSBackgroundColor" value:[UIColor colorWithWhite:0.92f alpha:1.0f] range:rr];
    if (gray) [seg addAttribute:@"NSColor" value:[UIColor colorWithWhite:0.55f alpha:1.0f] range:rr];
    [outStr appendAttributedString:seg];
}

- (id)renderMD:(NSString *)md grayAll:(BOOL)grayAll {
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
                [self appendStyled:outStr text:cp font:fnt shaded:(inCode || isC) gray:grayAll];
                isC = !isC;
            }
            isB = !isB;
        }
        [self appendStyled:outStr text:@"\n" font:normal shaded:NO gray:grayAll];
    }
    return outStr;
}

#pragma mark - 对话记录

- (void)scrollBottom {
    NSRange r; r.location = [_rich length]; r.length = 0;
    [_log scrollRangeToVisible:r];
}

- (void)appendLine:(NSString *)who text:(NSString *)text isUser:(BOOL)isUser {
    NSUInteger start = [_rich length];
    [self appendStyled:_rich text:[NSString stringWithFormat:@"%@：\n", who]
                font:[UIFont boldSystemFontOfSize:14.0f] shaded:NO gray:NO];
    NSUInteger bodyStart = [_rich length];
    [_rich appendAttributedString:[self renderMD:text grayAll:NO]];
    NSUInteger end = [_rich length];
    if (isUser && end > start) {
        NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
        [ps setAlignment:2];   // 右对齐
        NSRange all; all.location = start; all.length = end - start;
        [_rich addAttribute:@"NSParagraphStyle" value:ps range:all];
        [ps release];
        NSRange body; body.location = bodyStart; body.length = end - bodyStart;
        [_rich addAttribute:@"NSBackgroundColor" value:[UIColor colorWithRed:0.85f green:0.92f blue:1.0f alpha:1.0f] range:body];
    }
    _log.attributedText = _rich;
    [self scrollBottom];
}

#pragma mark - 键盘

- (void)slideInput:(BOOL)up {
    CGFloat kh = up ? _kbHeight : 0.0f;
    CGRect bf = [[UIScreen mainScreen] applicationFrame];
    CGFloat top = 0;   // 同上：壳视图本地坐标
    _log.frame = CGRectMake(0, top, bf.size.width, bf.size.height - 48.0f - kh);
    UIView *bar = [_shell.view viewWithTag:4242];
    bar.frame = CGRectMake(0, top + bf.size.height - 48.0f - kh, bf.size.width, 48.0f);
    _thumb.frame = CGRectMake(bf.size.width - 54, top + bf.size.height - 48 - 52 - kh, 46, 46);
    if (up) [self scrollBottom];
}

- (void)kbShow:(NSNotification *)n {
    CGRect kr = [[[n userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    if (kr.size.height > 0) _kbHeight = kr.size.height;
    if (_editing) [self slideInput:YES];
}

- (void)fieldBegan {
    _editing = YES;
    _kbOverlay.hidden = NO;
    [self slideInput:YES];
}

- (void)fieldEnded {
    _editing = NO;
    _kbOverlay.hidden = YES;
    [self slideInput:NO];
}

- (void)overlayTapped {
    [_field resignFirstResponder];
}

- (void)scrollViewWillBeginDragging:(id)sv {
    [_field resignFirstResponder];
}

#pragma mark - 深度思考

- (void)thinkPressed {
    _deepThink = !_deepThink;
    [_thinkBtn setTitleColor:(_deepThink ? [UIColor colorWithRed:0.1f green:0.4f blue:0.9f alpha:1.0f] : [UIColor blackColor])
                    forState:UIControlStateNormal];
    [self appendLine:@"系统" text:(_deepThink ? @"深度思考已开启（回答会更慢更聪明）" : @"深度思考已关闭") isUser:NO];
}

#pragma mark - 拍照识图

- (void)photoPressed {
    BOOL hasCam = [UIImagePickerController isSourceTypeAvailable:1];   // Camera=1
    UIActionSheet *sheet;
    if (hasCam) {
        sheet = [[UIActionSheet alloc] initWithTitle:@"识图（图片将发给视觉模型）" delegate:self
            cancelButtonTitle:nil destructiveButtonTitle:nil
            otherButtonTitles:@"拍照", @"从相册选择", @"取消", nil];
    } else {
        sheet = [[UIActionSheet alloc] initWithTitle:@"识图（图片将发给视觉模型）" delegate:self
            cancelButtonTitle:nil destructiveButtonTitle:nil
            otherButtonTitles:@"从相册选择", @"取消", nil];
    }
    [sheet showInView:_window];
    [sheet release];
}

- (void)actionSheet:(id)sheet clickedButtonAtIndex:(NSInteger)idx {
    BOOL hasCam = [UIImagePickerController isSourceTypeAvailable:1];
    NSInteger cancelIdx = hasCam ? 2 : 1;
    if (idx == cancelIdx) return;
    NSInteger src = (hasCam && idx == 0) ? 1 : 0;   // Camera=1, PhotoLibrary=0
    UIImagePickerController *p = [[UIImagePickerController alloc] init];
    p.sourceType = src;
    p.delegate = self;
    [_shell presentModalViewController:p animated:YES];
    [p release];
}

- (void)imagePickerControllerDidCancel:(id)p {
    [_shell dismissModalViewControllerAnimated:YES];
}

- (void)imagePickerController:(id)picker didFinishPickingMediaWithInfo:(id)info {
    UIImage *img = [info objectForKey:@"UIImagePickerControllerOriginalImage"];
    [_shell dismissModalViewControllerAnimated:YES];
    if (!img) return;

    CGSize s = [img size];
    CGFloat maxSide = 1024.0f;
    CGFloat scale = 1.0f;
    if (s.width > maxSide || s.height > maxSide)
        scale = maxSide / (s.width > s.height ? s.width : s.height);
    CGSize ns; ns.width = s.width * scale; ns.height = s.height * scale;
    UIGraphicsBeginImageContext(ns);
    [img drawInRect:CGRectMake(0, 0, ns.width, ns.height)];
    UIImage *small = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    NSData *jpg = UIImageJPEGRepresentation(small, 0.7f);
    [_pendingImage release];
    _pendingImage = [[NSString stringWithFormat:@"data:image/jpeg;base64,%@", b64encode(jpg)] retain];
    [_thumb setImage:small];
    _thumb.hidden = NO;
    [self appendLine:@"系统" text:@"图片已就绪，输入文字后发送即可让它看图（发送后自动清除）" isUser:NO];
}

#pragma mark - 发送与网络

- (NSString *)currentModel {
    if (_pendingImage) return @"deepseek-v4-flash-vision-exp";
    return _deepThink ? @"deepseek-reasoner" : @"deepseek-chat";
}

- (void)sendPressed {
    NSString *text = [_field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL hasImg = (_pendingImage != nil);
    if (([text length] == 0 && !hasImg) || _waiting) return;
    if ([_apiKey length] == 0) return;
    [_field resignFirstResponder];
    _field.text = @"";
    [self appendLine:@"我" text:(hasImg ? [NSString stringWithFormat:@"[图片] %@", text] : text) isUser:YES];

    id content;
    if (hasImg) {
        id textPart = [NSDictionary dictionaryWithObjectsAndKeys:@"text", @"type", text, @"text", nil];
        id imgPart = [NSDictionary dictionaryWithObjectsAndKeys:@"image_url", @"type",
            [NSDictionary dictionaryWithObjectsAndKeys:_pendingImage, @"url", nil], @"image_url", nil];
        content = [NSArray arrayWithObjects:textPart, imgPart, nil];
    } else {
        content = text;
    }
    [_msgs addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"user", @"role", content, @"content", nil]];
    [self saveSession];

    _waiting = YES;
    _sendBtn.enabled = NO;
    [_spin startAnimating];
    _httpError = NO;
    [_streamText setString:@""];
    [_streamThink setString:@""];
    _streamDirty = NO;
    [_streamBase release];
    _streamBase = [[_log text] copy];
    [_streamTimer invalidate];
    _streamTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(streamTick) userInfo:nil repeats:YES];

    NSMutableArray *apiMsgs = [NSMutableArray array];
    [apiMsgs addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"system", @"role",
        @"你是 DeepSeek，一个乐于助人的 AI 助手。请用简体中文回答，回答尽量简洁。", @"content", nil]];
    for (NSDictionary *m in _msgs) {
        [apiMsgs addObject:m];
    }
    NSDictionary *body = [NSDictionary dictionaryWithObjectsAndKeys:
        [self currentModel], @"model",
        apiMsgs, @"messages",
        [NSNumber numberWithBool:YES], @"stream",
        nil];
    NSData *json = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://api.deepseek.com/chat/completions"]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 300.0;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", _apiKey] forHTTPHeaderField:@"Authorization"];
    req.HTTPBody = json;

    [_buf setLength:0];
    [_conn release];
    _conn = [[NSURLConnection alloc] initWithRequest:req delegate:self startImmediately:YES];

    // 待发图片处理完即清
    [_pendingImage release]; _pendingImage = nil;
    _thumb.hidden = YES;
}

#pragma mark - SSE 流式解析

- (void)scrollBottomPlain {
    NSRange r; r.location = [[_log text] length]; r.length = 0;
    [_log scrollRangeToVisible:r];
}

- (void)streamTick {
    if (!_streamDirty) return;
    _streamDirty = NO;
    NSMutableString *show = [NSMutableString string];
    if (_streamBase) [show appendString:_streamBase];
    if ([_streamThink length] > 0) {
        [show appendString:@"\nDeepSeek：\n【思考中…】\n"];
        [show appendString:_streamThink];
    }
    if ([_streamText length] > 0) {
        [show appendString:@"\nDeepSeek：\n"];
        [show appendString:_streamText];
    }
    _log.text = show;
    [self scrollBottomPlain];
}

- (void)processSSELine:(NSString *)line {
    if (![line hasPrefix:@"data:"]) return;
    NSString *payload = [[line substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([payload isEqualToString:@"[DONE]"]) return;
    id obj = [NSJSONSerialization JSONObjectWithData:[payload dataUsingEncoding:4] options:0 error:NULL];
    if (![obj isKindOfClass:[NSDictionary class]]) return;
    NSArray *choices = [obj objectForKey:@"choices"];
    if ([choices count] == 0) return;
    id delta = [[choices objectAtIndex:0] objectForKey:@"delta"];
    if (![delta isKindOfClass:[NSDictionary class]]) return;
    NSString *piece = [delta objectForKey:@"content"];
    NSString *think = [delta objectForKey:@"reasoning_content"];
    if ([think isKindOfClass:[NSString class]] && [think length] > 0) {
        [_streamThink appendString:think];
        _streamDirty = YES;
    }
    if ([piece isKindOfClass:[NSString class]] && [piece length] > 0) {
        [_streamText appendString:piece];
        _streamDirty = YES;
    }
}

- (void)connection:(NSURLConnection *)c didReceiveResponse:(id)resp {
    NSHTTPURLResponse *r = (NSHTTPURLResponse *)resp;
    _httpError = ([r statusCode] != 200);
}

- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)data {
    [_buf appendData:data];
    // 按行切 SSE，留尾巴
    const char *bytes = (const char *)[_buf bytes];
    NSUInteger len = [_buf length];
    NSUInteger start = 0, i;
    for (i = 0; i < len; i++) {
        if (bytes[i] == '\n') {
            if (i > start) {
                NSRange lr; lr.location = start; lr.length = i - start;
                NSData *lineData = [_buf subdataWithRange:lr];
                NSString *line = [[[NSString alloc] initWithData:lineData encoding:4] autorelease];
                if (line) [self processSSELine:line];
            }
            start = i + 1;
        }
    }
    if (start > 0) {
        NSRange tr; tr.location = start; tr.length = len - start;
        NSData *tail = [_buf subdataWithRange:tr];
        [_buf setData:tail];
    }
}

- (void)stopStreamTimer {
    [_streamTimer invalidate];   // scheduledTimer 返回的是 autorelease 对象，不许 release
    _streamTimer = nil;
    [_streamBase release]; _streamBase = nil;
}

- (void)finalizeStream {
    _waiting = NO;
    _sendBtn.enabled = YES;
    [_spin stopAnimating];
    [self stopStreamTimer];
    if ([_streamThink length] == 0 && [_streamText length] == 0) return;
    [self appendStyled:_rich text:@"DeepSeek：\n" font:[UIFont boldSystemFontOfSize:14.0f] shaded:NO gray:NO];
    if ([_streamThink length] > 0) {
        [self appendStyled:_rich text:@"【思考过程】\n" font:[UIFont boldSystemFontOfSize:13.0f] shaded:NO gray:YES];
        [_rich appendAttributedString:[self renderMD:_streamThink grayAll:YES]];
    }
    if ([_streamText length] > 0) {
        [_msgs addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"assistant", @"role", _streamText, @"content", nil]];
        [_rich appendAttributedString:[self renderMD:_streamText grayAll:NO]];
    }
    _log.attributedText = _rich;
    [self scrollBottom];
    [self saveSession];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)c {
    if (_httpError) {
        _waiting = NO;
        _sendBtn.enabled = YES;
        [_spin stopAnimating];
        [self stopStreamTimer];
        id obj = [NSJSONSerialization JSONObjectWithData:_buf options:0 error:NULL];
        NSString *msg = @"未知错误";
        if ([obj isKindOfClass:[NSDictionary class]] && [obj objectForKey:@"error"])
            msg = [[obj objectForKey:@"error"] objectForKey:@"message"];
        [self appendLine:@"系统" text:[NSString stringWithFormat:@"API 报错：%@", msg] isUser:NO];
        return;
    }
    [self finalizeStream];
}

- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)error {
    _waiting = NO;
    _sendBtn.enabled = YES;
    [_spin stopAnimating];
    [self stopStreamTimer];
    [self appendLine:@"系统" text:[NSString stringWithFormat:@"网络错误：%@（code %d）",
        [error localizedDescription], (int)[error code]] isUser:NO];
}

#pragma mark - 会话管理

- (NSString *)sessionsDir {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    return [docs stringByAppendingPathComponent:@"sessions"];
}

- (NSString *)titleForMsgs:(NSArray *)msgs {
    NSUInteger i;
    for (i = 0; i < [msgs count]; i++) {
        NSDictionary *m = [msgs objectAtIndex:i];
        if ([[m objectForKey:@"role"] isEqualToString:@"user"]) {
            id content = [m objectForKey:@"content"];
            NSString *t = nil;
            if ([content isKindOfClass:[NSString class]]) t = content;
            else if ([content isKindOfClass:[NSArray class]] && [content count] > 0)
                t = [[content objectAtIndex:0] objectForKey:@"text"];
            if ([t length] > 0) {
                if ([t length] > 12) t = [[t substringToIndex:12] stringByAppendingString:@"…"];
                return t;
            }
        }
    }
    return @"新会话";
}

- (void)saveSession {
    if ([_msgs count] == 0) return;
    if (!_sessionId)
        _sessionId = [[NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]] retain];
    NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:
        [self titleForMsgs:_msgs], @"title", _msgs, @"msgs", nil];
    NSData *json = [NSJSONSerialization dataWithJSONObject:d options:0 error:NULL];
    if (json) [json writeToFile:[[self sessionsDir] stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.json", _sessionId]] atomically:YES];
}

- (BOOL)loadSessionFile:(NSString *)path {
    NSData *json = [NSData dataWithContentsOfFile:path];
    if (!json) return NO;
    id obj = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
    if (![obj isKindOfClass:[NSDictionary class]]) return NO;
    NSArray *msgs = [obj objectForKey:@"msgs"];
    if (![msgs isKindOfClass:[NSArray class]]) return NO;

    [_msgs release]; _msgs = [msgs mutableCopy];
    [_rich release]; _rich = [[NSMutableAttributedString alloc] initWithString:@""];
    NSUInteger i;
    for (i = 0; i < [_msgs count]; i++) {
        NSDictionary *m = [_msgs objectAtIndex:i];
        NSString *role = [m objectForKey:@"role"];
        id content = [m objectForKey:@"content"];
        NSString *text = nil;
        if ([content isKindOfClass:[NSString class]]) text = content;
        else if ([content isKindOfClass:[NSArray class]] && [content count] > 0)
            text = [NSString stringWithFormat:@"[图片] %@", [[content objectAtIndex:0] objectForKey:@"text"]];
        if ([text length] > 0)
            [self appendLine:([role isEqualToString:@"user"] ? @"我" : @"DeepSeek") text:text isUser:[role isEqualToString:@"user"]];
    }
    return YES;
}

- (BOOL)loadLatestSession {
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self sessionsDir] error:NULL];
    if (!files || [files count] == 0) return NO;
    NSArray *sorted = [files sortedArrayUsingSelector:@selector(compare:)];
    NSString *last = [sorted objectAtIndex:[sorted count] - 1];
    BOOL ok = [self loadSessionFile:[[self sessionsDir] stringByAppendingPathComponent:last]];
    if (ok) _sessionId = [[last stringByDeletingPathExtension] retain];
    return ok;
}

- (void)newSession {
    [self saveSession];
    [_sessionId release]; _sessionId = nil;
    [_msgs release]; _msgs = [[NSMutableArray alloc] init];
    [_rich release]; _rich = [[NSMutableAttributedString alloc] initWithString:@""];
    _log.attributedText = _rich;
    [self appendLine:@"DeepSeek" text:@"新会话开始了，有何贵干？" isUser:NO];
}

- (void)menuPressed {
    [self saveSession];
    _alertMode = 0;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self sessionsDir] error:NULL];
    NSArray *sorted = files ? [files sortedArrayUsingSelector:@selector(compare:)] : [NSArray array];

    UIAlertView *av = [[UIAlertView alloc] init];
    [av setTitle:@"会话"];
    [av setDelegate:self];
    [av addButtonWithTitle:@"＋ 新会话"];
    NSUInteger i;
    for (i = 0; i < [sorted count]; i++) {
        NSString *f = [sorted objectAtIndex:i];
        id obj = [NSJSONSerialization JSONObjectWithData:
            [NSData dataWithContentsOfFile:[[self sessionsDir] stringByAppendingPathComponent:f]] options:0 error:NULL];
        NSString *title = [obj isKindOfClass:[NSDictionary class]] ? [obj objectForKey:@"title"] : f;
        [av addButtonWithTitle:title ? title : f];
    }
    if (_sessionId) [av addButtonWithTitle:@"✏️ 重命名当前会话"];
    if (_sessionId) [av addButtonWithTitle:@"🗑 删除当前会话"];
    [av addButtonWithTitle:@"取消"];
    [av show];
    [av release];
}

- (void)renameCurrentSession:(NSString *)newTitle {
    if (!_sessionId || [newTitle length] == 0) return;
    NSString *path = [[self sessionsDir] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", _sessionId]];
    id obj = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:NULL];
    if (![obj isKindOfClass:[NSDictionary class]]) return;
    NSMutableDictionary *d = [obj mutableCopy];
    [d setObject:newTitle forKey:@"title"];
    NSData *json = [NSJSONSerialization dataWithJSONObject:d options:0 error:NULL];
    if (json) [json writeToFile:path atomically:YES];
    [d release];
    [self appendLine:@"系统" text:[NSString stringWithFormat:@"本会话已重命名为「%@」", newTitle] isUser:NO];
}

- (void)alertView:(id)av clickedButtonAtIndex:(NSInteger)idx {
    if (_alertMode == 1) {   // 重命名弹窗
        if (idx == 1) {      // 好
            UITextField *tf = [av textFieldAtIndex:0];
            if (tf) [self renameCurrentSession:[tf text]];
        }
        _alertMode = 0;
        return;
    }
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self sessionsDir] error:NULL];
    NSArray *sorted = files ? [files sortedArrayUsingSelector:@selector(compare:)] : [NSArray array];
    NSInteger extra = _sessionId ? 2 : 0;   // 重命名+删除
    NSInteger cancelIdx = 1 + [sorted count] + extra;
    if (idx == cancelIdx) return;                    // 取消
    if (idx == 0) { [self newSession]; return; }     // 新会话
    if (idx >= 1 && idx <= (NSInteger)[sorted count]) {
        [self saveSession];
        NSString *f = [sorted objectAtIndex:idx - 1];
        if ([self loadSessionFile:[[self sessionsDir] stringByAppendingPathComponent:f]]) {
            [_sessionId release];
            _sessionId = [[f stringByDeletingPathExtension] retain];
        }
        return;
    }
    if (_sessionId && idx == (NSInteger)[sorted count] + 1) {
        // 重命名当前会话：弹输入框
        _alertMode = 1;
        UIAlertView *rv = [[UIAlertView alloc] init];
        [rv setTitle:@"重命名会话"];
        [rv setDelegate:self];
        [rv setAlertViewStyle:1];   // PlainTextInput
        UITextField *tf = [rv textFieldAtIndex:0];
        if (tf) [tf setText:[self titleForMsgs:_msgs]];
        [rv addButtonWithTitle:@"算了"];
        [rv addButtonWithTitle:@"好"];
        [rv show];
        [rv release];
        return;
    }
    // 删除当前会话
    if (_sessionId) {
        [[NSFileManager defaultManager] removeItemAtPath:
            [[self sessionsDir] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.json", _sessionId]] error:NULL];
        [self newSession];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_window release]; [_shell release]; [_log release]; [_field release];
    [_sendBtn release]; [_thinkBtn release]; [_spin release]; [_thumb release];
    [_rich release]; [_msgs release]; [_buf release]; [_conn release]; [_apiKey release];
    [_pendingImage release]; [_sessionId release]; [_streamText release]; [_streamThink release];
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

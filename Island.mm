// Island.dylib — iOS 6 灵动岛（白色版）
// 功能：常驻白色药丸（最高置顶，锁屏/通知中心/App 内全可见）
//       音乐：显示正在播放的歌名-歌手；充电：闪电+电量百分比
// 平台：iOS 6.1.3 / armv7 / MobileSubstrate / MRC（无 Logos，手写 MSHookMessageEx）
#include "mini_ios.h"
#include "CydiaSubstrate.h"
#include <dlfcn.h>

#pragma mark - 运行时符号声明
typedef void *dispatch_queue_t;
extern void dispatch_async(dispatch_queue_t queue, void (^block)(void));
extern dispatch_queue_t dispatch_get_main_queue(void);

extern CFNotificationCenterRef CFNotificationCenterGetLocalCenter(void);
extern void CFNotificationCenterAddObserver(CFNotificationCenterRef center, const void *observer,
    void (*callBack)(CFNotificationCenterRef, void *, CFStringRef, const void *, CFDictionaryRef),
    CFStringRef name, const void *object, int suspensionBehavior);

#pragma mark - 配置
#define ISLAND_BG      [UIColor colorWithWhite:0.97 alpha:0.98]
#define ISLAND_TEXT    [UIColor colorWithWhite:0.15 alpha:1.0]
#define ISLAND_DIM     [UIColor colorWithWhite:0.55 alpha:1.0]
#define ISLAND_GREEN   [UIColor colorWithRed:0.2 green:0.65 blue:0.25 alpha:1.0]
#define ISLAND_W_IDLE  110.0
#define ISLAND_W_ACT   220.0
#define ISLAND_H       26.0
#define ISLAND_Y       6.0
#define FONT_MAIN      [UIFont boldSystemFontOfSize:11.5]

#pragma mark - 岛视图
@interface IslandView : UIView {
    UILabel *_label;
}
- (void)showText:(NSString *)text accent:(UIColor *)accent;
- (void)idle;
@end

@implementation IslandView
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = ISLAND_BG;
        self.layer.cornerRadius = frame.size.height / 2.0;
        self.layer.borderWidth = 0.5;
        self.layer.borderColor = [UIColor colorWithWhite:0.75 alpha:1.0].CGColor;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.18;
        self.layer.shadowRadius = 4.0;
        self.layer.shadowOffset = CGSizeMake(0, 2);

        _label = [[UILabel alloc] initWithFrame:self.bounds];
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _label.backgroundColor = [UIColor clearColor];
        _label.textColor = ISLAND_TEXT;
        _label.font = FONT_MAIN;
        _label.textAlignment = NSTextAlignmentCenter;
        _label.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self addSubview:_label];
        [self idle];
    }
    return self;
}
- (void)showText:(NSString *)text accent:(UIColor *)accent {
    _label.text = text;
    _label.textColor = accent ? accent : ISLAND_TEXT;
}
- (void)idle {
    _label.text = @"●";
    _label.textColor = ISLAND_DIM;
}
@end

#pragma mark - 宿主
static UIWindow *islandWindow = nil;
static IslandView *island = nil;

static void islandResize(CGFloat w) {
    if (!islandWindow) return;
    [UIView animateWithDuration:0.25 animations:^{
        CGFloat sw = [UIScreen mainScreen].bounds.size.width;
        islandWindow.frame = CGRectMake((sw - w) / 2.0, ISLAND_Y, w, ISLAND_H);
    }];
}

#pragma mark - 音乐（MediaRemote 运行时加载）
typedef void (*MRGetInfo_t)(dispatch_queue_t, void (^)(NSDictionary *));
static MRGetInfo_t MRGetInfo = NULL;

static void updateMusic() {
    if (!island) return;
    if (!MRGetInfo) {
        void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (mr) MRGetInfo = (MRGetInfo_t)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
        if (!MRGetInfo) return;
    }
    MRGetInfo(dispatch_get_main_queue(), ^(NSDictionary *info) {
        NSString *title = [info objectForKey:@"kMRMediaRemoteNowPlayingInfoTitle"];
        NSString *artist = [info objectForKey:@"kMRMediaRemoteNowPlayingInfoArtist"];
        if (title.length > 0) {
            NSString *s = artist.length > 0 ? [NSString stringWithFormat:@"♪ %@ - %@", title, artist]
                                            : [NSString stringWithFormat:@"♪ %@", title];
            [island showText:s accent:nil];
            islandResize(ISLAND_W_ACT);
        }
    });
}

#pragma mark - 充电
static void updateCharge() {
    if (!island) return;
    UIDevice *dev = [UIDevice currentDevice];
    if (dev.batteryState == UIDeviceBatteryStateCharging || dev.batteryState == UIDeviceBatteryStateFull) {
        int pct = (int)(dev.batteryLevel * 100);
        if (pct < 0) pct = 0;
        [island showText:[NSString stringWithFormat:@"⚡ 充电中 %d%%", pct] accent:ISLAND_GREEN];
        islandResize(ISLAND_W_ACT);
    } else {
        updateMusic();
    }
}

static void onBatteryChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *d, CFDictionaryRef i) {
    dispatch_async(dispatch_get_main_queue(), ^{ updateCharge(); });
}
static void onMusicChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *d, CFDictionaryRef i) {
    dispatch_async(dispatch_get_main_queue(), ^{ updateMusic(); });
}

#pragma mark - 初始化
static void initIsland() {
    if (islandWindow) return;
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    islandWindow = [[UIWindow alloc] initWithFrame:CGRectMake((sw - ISLAND_W_IDLE) / 2.0, ISLAND_Y, ISLAND_W_IDLE, ISLAND_H)];
    islandWindow.windowLevel = 2100.0;
    islandWindow.backgroundColor = [UIColor clearColor];
    islandWindow.userInteractionEnabled = NO;
    island = [[IslandView alloc] initWithFrame:islandWindow.bounds];
    island.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [islandWindow addSubview:island];
    islandWindow.hidden = NO;

    [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL, onBatteryChanged,
        (CFStringRef)@"UIDeviceBatteryStateDidChangeNotification", NULL, 4);
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL, onBatteryChanged,
        (CFStringRef)@"UIDeviceBatteryLevelDidChangeNotification", NULL, 4);
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL, onMusicChanged,
        (CFStringRef)@"kMRMediaRemoteNowPlayingInfoDidChangeNotification", NULL, 4);

    updateCharge();
    updateMusic();
}

#pragma mark - Hook（手动 MSHookMessageEx）
typedef id (*DidFinishLaunching_t)(id, SEL, id);
static DidFinishLaunching_t orig_DidFinishLaunching = NULL;

static void mark(const char *p) {
    FILE *f = fopen(p, "w");
    if (f) { fputs("ok", f); fclose(f); }
}

__attribute__((constructor))
static void island_boot() {
    mark("/var/mobile/island_ctor.txt");
    initIsland();
    mark("/var/mobile/island_init.txt");
}

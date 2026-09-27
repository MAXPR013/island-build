// mini_ios.h — 手写最小 iOS 接口声明（替代 SDK 头文件）
// 只声明 Island.dylib 用到的部分；动态查找链接，运行时由 dyld 解析
#ifndef MINI_IOS_H
#define MINI_IOS_H

#include "mini_objc.h"
#include <stdint.h>

#ifdef __OBJC__

// ---- CoreFoundation 最小声明 ----
typedef const void *CFTypeRef;
typedef const struct __CFString *CFStringRef;
typedef const struct __CFDictionary *CFDictionaryRef;
typedef struct __CFNotificationCenter *CFNotificationCenterRef;
typedef const void *CGColorRef;

// ---- 基础几何 ----
typedef float CGFloat;
struct CGPoint { CGFloat x, y; };
struct CGSize  { CGFloat width, height; };
struct CGRect  { struct CGPoint origin; struct CGSize size; };
typedef struct CGPoint CGPoint;
typedef struct CGSize CGSize;
typedef struct CGRect CGRect;
static inline CGSize CGSizeMake(CGFloat w, CGFloat h) { CGSize s; s.width = w; s.height = h; return s; }
static inline CGPoint CGPointMake(CGFloat x, CGFloat y) { CGPoint p; p.x = x; p.y = y; return p; }
static inline CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { CGRect r; r.origin.x = x; r.origin.y = y; r.size.width = w; r.size.height = h; return r; }

#ifndef NS_ENUM
#define NS_ENUM(_type, _name) _type _name; enum
#endif

typedef NSInteger UIWindowLevel;
enum {
    NSTextAlignmentLeft = 0,
    NSTextAlignmentCenter = 1,
    NSTextAlignmentRight = 2,
};
enum {
    NSLineBreakByWordWrapping = 0,
    NSLineBreakByCharWrapping = 1,
    NSLineBreakByClipping = 2,
    NSLineBreakByTruncatingHead = 3,
    NSLineBreakByTruncatingTail = 4,
    NSLineBreakByTruncatingMiddle = 5,
};
typedef NSInteger UIDeviceBatteryState;
enum {
    UIDeviceBatteryStateUnknown = 0,
    UIDeviceBatteryStateUnplugged,
    UIDeviceBatteryStateCharging,
    UIDeviceBatteryStateFull,
};
enum {
    UIViewAutoresizingNone = 0,
    UIViewAutoresizingFlexibleLeftMargin = 1 << 0,
    UIViewAutoresizingFlexibleWidth = 1 << 1,
    UIViewAutoresizingFlexibleRightMargin = 1 << 2,
    UIViewAutoresizingFlexibleTopMargin = 1 << 3,
    UIViewAutoresizingFlexibleHeight = 1 << 4,
    UIViewAutoresizingFlexibleBottomMargin = 1 << 5,
};

@class NSString, NSDictionary, NSTimer, NSNotificationCenter;
@class UIColor, UIFont, UIView, UIWindow, UILabel, UIScreen, UIDevice, UIApplication;
@class CALayer;

@interface NSObject
+ (id)alloc;
- (id)init;
- (void)release;
- (id)retain;
- (void)dealloc;
@end

@interface NSString : NSObject
+ (id)stringWithFormat:(id)fmt, ...;
- (unsigned)length;
@end

@interface NSDictionary : NSObject
- (id)objectForKey:(id)key;
@end

@interface UIColor : NSObject
+ (UIColor *)colorWithWhite:(CGFloat)w alpha:(CGFloat)a;
+ (UIColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (UIColor *)blackColor;
+ (UIColor *)clearColor;
- (CGColorRef)CGColor;
@end

@interface UIFont : NSObject
+ (UIFont *)boldSystemFontOfSize:(CGFloat)s;
@end

@interface CALayer : NSObject
@property CGFloat cornerRadius, borderWidth, shadowOpacity, shadowRadius;
@property (assign) CGColorRef borderColor, shadowColor;
@property (assign) CGSize shadowOffset;
@end

@interface UIView : NSObject
@property (nonatomic) CGRect frame, bounds;
@property (nonatomic, retain) UIColor *backgroundColor;
@property (nonatomic, readonly) CALayer *layer;
@property (nonatomic) BOOL hidden, userInteractionEnabled;
@property (nonatomic) NSUInteger autoresizingMask;
@property (nonatomic, readonly) UIView *superview;
- (id)initWithFrame:(CGRect)f;
- (void)addSubview:(UIView *)v;
+ (void)animateWithDuration:(double)d animations:(void (^)(void))anim;
@end

@interface UIWindow : UIView
@property (nonatomic) UIWindowLevel windowLevel;
@end

@interface UILabel : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, retain) UIColor *textColor;
@property (nonatomic, retain) UIFont *font;
@property (nonatomic) NSInteger textAlignment, lineBreakMode;
@end

@interface UIScreen : NSObject
+ (UIScreen *)mainScreen;
- (CGRect)bounds;
@end

@interface UIDevice : NSObject
+ (UIDevice *)currentDevice;
@property (nonatomic, readonly) UIDeviceBatteryState batteryState;
@property (nonatomic, readonly) float batteryLevel;
- (void)setBatteryMonitoringEnabled:(BOOL)on;
@end

#endif // __OBJC__
#endif // MINI_IOS_H

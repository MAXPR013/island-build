// dschat_mini.h — DSChat 用到的最小 UIKit/Foundation 声明（免 SDK，dynamic_lookup 运行时解析）
#ifndef DSCHAT_MINI_H
#define DSCHAT_MINI_H

#include "mini_objc.h"
#include <stdint.h>

#ifdef __OBJC__

// ---- CoreGraphics 基础 ----
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
#define CGRectZero CGRectMake(0,0,0,0)

// ---- 枚举常量 ----
enum { NSUTF8StringEncoding = 4 };
enum { NSDocumentDirectory = 9, NSUserDomainMask = 1 };
enum { UITableViewStylePlain = 0 };
enum { UITableViewCellStyleDefault = 0 };
enum { UITableViewCellSelectionStyleNone = 0 };
enum { UITableViewCellSeparatorStyleNone = 0 };
enum { UITableViewScrollPositionBottom = 3 };
enum { UITextAlignmentLeft = 0, UITextAlignmentCenter = 1, UITextAlignmentRight = 2 };
enum { UILineBreakModeWordWrap = 0 };
enum { UITextBorderStyleRoundedRect = 3 };
enum { UIReturnKeySend = 7 };
enum { UIButtonTypeRoundedRect = 1 };
enum { UIControlStateNormal = 0 };
enum { UIControlEventTouchUpInside = 1 << 6 };
enum { UIControlEventEditingDidBegin = 1 << 16 };
enum { UIControlEventEditingDidEnd = 1 << 18 };
enum { UIControlEventEditingDidEndOnExit = 1 << 19 };
enum { UIActivityIndicatorViewStyleGray = 2 };

@class NSString, NSArray, NSMutableArray, NSDictionary, NSNumber, NSData, NSMutableData;
@class NSError, NSIndexPath, NSNotificationCenter, NSAutoreleasePool, NSCharacterSet, NSNotification, NSValue;
@class NSURL, NSURLRequest, NSMutableURLRequest, NSURLConnection, NSURLCredential;
@class NSURLAuthenticationChallenge, NSURLProtectionSpace, UIFont, UIColor, CALayer;
@class UIView, UIViewController, UIWindow, UIScreen, UILabel, UITableView, UITableViewCell;
@class UITextField, UIButton, UIControl, UIActivityIndicatorView, UIApplication;

// ---- 外部字符串常量 ----
extern NSString * const UIKeyboardWillShowNotification;
extern NSString * const UIKeyboardWillHideNotification;
extern NSString * const UIKeyboardFrameEndUserInfoKey;
extern NSString * const NSURLAuthenticationMethodServerTrust;

// ---- C 函数 ----
int UIApplicationMain(int argc, char *argv[], id principalClassName, id delegateClassName);
NSArray *NSSearchPathForDirectoriesInDomains(NSUInteger directory, NSUInteger domainMask, BOOL expandTilde);

// ---- 协议（空声明即可，实现由运行时识别）----
@protocol UITableViewDataSource @end
@protocol UITableViewDelegate @end
@protocol UITextFieldDelegate @end
@protocol NSURLConnectionDelegate @end
@protocol UIApplicationDelegate @end

// ---- Foundation ----
@interface NSObject
+ (id)alloc;
+ (Class)class;
- (id)init;
- (void)release;
- (id)retain;
- (id)autorelease;
- (void)dealloc;
- (BOOL)isKindOfClass:(Class)c;
@end

@interface NSAutoreleasePool : NSObject
@end

@interface NSString : NSObject
+ (id)stringWithFormat:(id)fmt, ...;
+ (id)stringWithContentsOfFile:(id)path encoding:(NSUInteger)enc error:(NSError **)err;
- (id)stringByTrimmingCharactersInSet:(id)cs;
- (id)stringByAppendingPathComponent:(id)str;
- (NSUInteger)length;
- (BOOL)isEqualToString:(id)s;
@end

@interface NSString (UIKitAdditions)
- (CGSize)sizeWithFont:(UIFont *)font constrainedToSize:(CGSize)size lineBreakMode:(NSInteger)mode;
- (BOOL)writeToFile:(id)path atomically:(BOOL)atom encoding:(NSUInteger)enc error:(NSError **)err;
@end

@interface NSArray : NSObject
- (NSUInteger)count;
- (id)objectAtIndex:(NSUInteger)i;
- (NSUInteger)countByEnumeratingWithState:(void *)state objects:(id *)stackbuf count:(NSUInteger)len;
@end

@interface NSMutableArray : NSArray
+ (id)array;
- (void)addObject:(id)o;
@end

@interface NSMutableString : NSObject
+ (id)stringWithFormat:(id)fmt, ...;
- (id)initWithFormat:(id)fmt, ...;
- (void)appendFormat:(id)fmt, ...;
- (id)description;
@end

@interface NSDictionary : NSObject
+ (id)dictionaryWithObjectsAndKeys:(id)first, ...;
- (id)objectForKey:(id)key;
@end

@interface NSNumber : NSObject
+ (id)numberWithBool:(BOOL)b;
@end

@interface NSData : NSObject
- (NSUInteger)length;
@end

@interface NSMutableData : NSData
- (void)setLength:(NSUInteger)len;
- (void)appendData:(NSData *)d;
@end

@interface NSJSONSerialization : NSObject
+ (NSData *)dataWithJSONObject:(id)obj options:(NSUInteger)opt error:(NSError **)err;
+ (id)JSONObjectWithData:(NSData *)data options:(NSUInteger)opt error:(NSError **)err;
@end

@interface NSCharacterSet : NSObject
+ (id)whitespaceAndNewlineCharacterSet;
@end

@interface NSException : NSObject
- (id)name;
- (id)reason;
- (id)callStackSymbols;
@end

@interface NSIndexPath : NSObject
+ (id)indexPathForRow:(NSInteger)row inSection:(NSInteger)section;
- (NSInteger)row;
- (NSInteger)section;
@end

@interface NSError : NSObject
- (id)localizedDescription;
- (NSInteger)code;
@end

@interface NSNotification : NSObject
- (id)userInfo;
@end

@interface NSValue : NSObject
- (CGRect)CGRectValue;
@end

@interface NSNotificationCenter : NSObject
+ (id)defaultCenter;
- (void)addObserver:(id)observer selector:(SEL)sel name:(id)name object:(id)obj;
- (void)removeObserver:(id)observer;
@end

@interface NSURL : NSObject
+ (id)URLWithString:(id)str;
@end

@interface NSURLRequest : NSObject
+ (id)requestWithURL:(id)url;
@end

@interface NSMutableURLRequest : NSURLRequest
- (void)setHTTPMethod:(id)m;
- (void)setTimeoutInterval:(double)t;
- (void)setValue:(id)v forHTTPHeaderField:(id)f;
- (void)setHTTPBody:(NSData *)d;
@end

@interface NSURLConnection : NSObject
- (id)initWithRequest:(id)req delegate:(id)del startImmediately:(BOOL)start;
@end

@interface NSURLCredential : NSObject
+ (id)credentialForTrust:(void *)trust;
@end

@interface NSURLProtectionSpace : NSObject
- (id)authenticationMethod;
- (void *)serverTrust;
@end

@interface NSURLAuthenticationChallenge : NSObject
- (NSURLProtectionSpace *)protectionSpace;
- (id)sender;
@end

@protocol NSURLAuthenticationChallengeSender
- (void)useCredential:(id)cred forAuthenticationChallenge:(id)ch;
- (void)continueWithoutCredentialForAuthenticationChallenge:(id)ch;
@end

// ---- UIKit ----
@interface UIColor : NSObject
+ (UIColor *)colorWithWhite:(CGFloat)w alpha:(CGFloat)a;
+ (UIColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a;
+ (UIColor *)whiteColor;
+ (UIColor *)blackColor;
+ (UIColor *)clearColor;
@end

@interface UIFont : NSObject
+ (UIFont *)systemFontOfSize:(CGFloat)s;
@end

@interface CALayer : NSObject
@property (nonatomic) CGFloat cornerRadius;
@property (nonatomic) BOOL masksToBounds;
@end

@interface UIView : NSObject
@property (nonatomic) CGRect frame;
@property (nonatomic, retain) UIColor *backgroundColor;
@property (nonatomic, readonly) CALayer *layer;
- (id)initWithFrame:(CGRect)f;
- (void)addSubview:(UIView *)v;
+ (void)beginAnimations:(id)animID context:(void *)ctx;
+ (void)setAnimationDuration:(double)d;
+ (void)commitAnimations;
@end

@interface UIViewController : NSObject {
    char _pad_vc[512];   // 占位：免SDK编译时编译器不知父类ivar大小，防止子类ivar与父类内部冲突
}
@property (nonatomic, retain) UIView *view;
- (void)loadView;
- (void)viewDidLoad;
@end

@interface UIWindow : UIView
@property (nonatomic, retain) UIViewController *rootViewController;
- (void)makeKeyAndVisible;
@end

@interface UIScreen : NSObject
+ (UIScreen *)mainScreen;
- (CGRect)bounds;
- (CGRect)applicationFrame;
@end

@interface UILabel : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, retain) UIColor *textColor;
@property (nonatomic, retain) UIFont *font;
@property (nonatomic) NSInteger textAlignment, lineBreakMode, numberOfLines;
@end

@interface UITableViewCell : UIView {
    char _pad_cell[512];   // 同上：防止子类ivar撞父类内部
}
@property (nonatomic) NSInteger selectionStyle;
@property (nonatomic, readonly) UIView *contentView;
- (id)initWithStyle:(NSInteger)style reuseIdentifier:(id)reuseIdentifier;
@end

@interface UITableView : UIView
@property (nonatomic, assign) id dataSource, delegate;
@property (nonatomic) NSInteger separatorStyle;
@property (nonatomic) BOOL allowsSelection;
- (id)initWithFrame:(CGRect)f style:(NSInteger)style;
- (void)reloadData;
- (void)scrollToRowAtIndexPath:(id)ip atScrollPosition:(NSInteger)pos animated:(BOOL)anim;
- (id)dequeueReusableCellWithIdentifier:(id)ident;
@end

@interface UIControl : UIView
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSUInteger)events;
@property (nonatomic) BOOL enabled;
@end

@interface UIButton : UIControl
+ (id)buttonWithType:(NSInteger)type;
- (void)setTitle:(id)title forState:(NSUInteger)state;
@end

@interface UITextField : UIControl
@property (nonatomic) NSInteger borderStyle, returnKeyType;
@property (nonatomic, copy) NSString *placeholder, *text;
@property (nonatomic, assign) id delegate;
- (BOOL)resignFirstResponder;
@end

@interface UIActivityIndicatorView : UIView
@property (nonatomic) CGPoint center;
@property (nonatomic) BOOL hidesWhenStopped;
- (id)initWithActivityIndicatorStyle:(NSInteger)style;
- (void)startAnimating;
- (void)stopAnimating;
@end

#endif // __OBJC__
#endif // DSCHAT_MINI_H

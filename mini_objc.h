// mini_objc.h — 手写最小 Objective-C 运行时声明（替代 <objc/runtime.h> 与 <objc/message.h>）
// 只包含 CydiaSubstrate.h 与 Island.dylib 实际使用的 API，签名与 Apple 官方一致
#ifndef MINI_OBJC_H
#define MINI_OBJC_H

#include <stdint.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---- 基本类型（等价 <objc/objc.h>）----
typedef struct objc_class *Class;
typedef struct objc_object *id;
typedef struct objc_selector *SEL;
typedef id (*IMP)(id, SEL, ...);
typedef struct objc_method *Method;
typedef struct objc_ivar *Ivar;
typedef signed char BOOL;
typedef int NSInteger;
typedef unsigned int NSUInteger;
#ifndef YES
#define YES 1
#define NO  0
#endif
#ifndef nil
#define nil ((id)0)
#define Nil ((Class)0)
#endif
typedef unsigned long arith_t;

// ---- 运行时函数（等价 <objc/runtime.h>）----
const char *sel_getName(SEL sel);
SEL sel_registerName(const char *str);
const char *class_getName(Class cls);
Class object_getClass(id obj);
Class objc_getClass(const char *name);
Class objc_getMetaClass(const char *name);
Class objc_getRequiredClass(const char *name);
Method class_getInstanceMethod(Class cls, SEL name);
Method class_getClassMethod(Class cls, SEL name);
IMP method_getImplementation(Method m);
const char *method_getTypeEncoding(Method m);
SEL method_getName(Method m);
void method_exchangeImplementations(Method m1, Method m2);
void class_replaceMethod(Class cls, SEL name, IMP imp, const char *types);
BOOL class_addMethod(Class cls, SEL name, IMP imp, const char *types);
IMP class_getMethodImplementation(Class cls, SEL name);
id object_getIvar(id obj, Ivar ivar);
Ivar class_getInstanceVariable(Class cls, const char *name);
void object_setIvar(id obj, Ivar ivar, id value);
ptrdiff_t ivar_getOffset(Ivar v);
Class class_getSuperclass(Class cls);

// ---- 消息发送（等价 <objc/message.h>）----
id objc_msgSend(id self, SEL op, ...);
id objc_msgSendSuper(struct objc_super *super, SEL op, ...);
struct objc_super {
    id receiver;
    Class super_class;
};

// ---- Mach-O nlist（等价 <mach-o/nlist.h>，CydiaSubstrate.h 需要）----
struct nlist {
    int32_t n_strx;
    uint8_t n_type;
    uint8_t n_sect;
    int16_t n_desc;
    uint32_t n_value;
};
struct nlist_64 {
    uint32_t n_strx;
    uint8_t n_type;
    uint8_t n_sect;
    uint16_t n_desc;
    uint64_t n_value;
};

#ifdef __cplusplus
}
#endif

#endif // MINI_OBJC_H

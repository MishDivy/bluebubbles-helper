// Synthetic layout calculations only. No accounts, transfers, messages, or views.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

typedef struct IMAssociatedMessageGeometryDescriptor {
    unsigned long long layoutIntent;
    unsigned long long associatedLayoutIntent;
    double parentPreviewWidth;
    double xScalar;
    double yScalar;
    double scale;
    double rotation;
} StickerGeometry;

static BOOL matches(Class cls, SEL selector, const char *encoding) {
    Method method = class_getClassMethod(cls, selector);
    return method && strcmp(method_getTypeEncoding(method), encoding) == 0;
}

int main(void) {
#if !defined(__arm64__)
    fputs("This synthetic layout probe requires arm64.\n", stderr);
    return 2;
#endif
    @autoreleasepool {
        if (!dlopen("/System/Library/PrivateFrameworks/IMCore.framework/IMCore", RTLD_NOW)
            || !dlopen("/System/iOSSupport/System/Library/PrivateFrameworks/ChatKit.framework/ChatKit", RTLD_NOW)) {
            fputs("Required framework unavailable.\n", stderr); return 1;
        }
        Class cls = objc_getClass("CKAssociatedMessageChatItem");
        SEL frameSelector = sel_registerName("frameForAssociatedMessageItemSize:parentFrame:geometryDescriptor:");
        SEL transformSelector = sel_registerName("transformForImageViewWithGeometryDescriptor:shouldScale:parentSize:");
        Ivar geometry = class_getInstanceVariable(objc_getClass("IMAssociatedMessageChatItem"), "_geometryDescriptor");
        const char *fields = "{IMAssociatedMessageGeometryDescriptor=\"layoutIntent\"Q\"associatedLayoutIntent\"Q\"parentPreviewWidth\"d\"xScalar\"d\"yScalar\"d\"scale\"d\"rotation\"d}";
        if (!geometry || strcmp(ivar_getTypeEncoding(geometry), fields) != 0
            || !matches(cls, frameSelector, "{CGRect={CGPoint=dd}{CGSize=dd}}120@0:8{CGSize=dd}16{CGRect={CGPoint=dd}{CGSize=dd}}32{IMAssociatedMessageGeometryDescriptor=QQddddd}64")
            || !matches(cls, transformSelector, "{CATransform3D=dddddddddddddddd}92@0:8{IMAssociatedMessageGeometryDescriptor=QQddddd}16B72{CGSize=dd}76")) {
            fputs("Layout ABI differs; no calls performed.\n", stderr); return 2;
        }
        const struct { const char *name; StickerGeometry geometry; CGSize parent; } cases[] = {
            {"center", {0, 0, 200, .5, .5, 1, 0}, {200, 100}},
            {"origin", {0, 0, 200, 0, 0, 1, 0}, {200, 100}},
            {"far", {0, 0, 200, 1, 1, 1, 0}, {200, 100}},
            {"half", {0, 0, 200, .5, .5, .5, 0}, {200, 100}},
            {"rotated", {0, 0, 200, .5, .5, 1, 1.5707963267948966}, {200, 100}},
            {"narrow-parent", {0, 0, 200, .5, .5, 1, 0}, {100, 100}},
            {"wide-parent", {0, 0, 200, .5, .5, 1, 0}, {400, 100}},
            {"offset", {0, 0, 200, .25, .75, 1, 0}, {200, 100}},
        };
        @try {
            for (NSUInteger i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
                CGRect parent = {{0, 0}, cases[i].parent};
                CGRect frame = ((CGRect (*)(id, SEL, CGSize, CGRect, StickerGeometry))objc_msgSend)(
                    cls, frameSelector, CGSizeMake(64, 48), parent, cases[i].geometry);
                CATransform3D transform = ((CATransform3D (*)(id, SEL, StickerGeometry, bool, CGSize))objc_msgSend)(
                    cls, transformSelector, cases[i].geometry, true, cases[i].parent);
                printf("%s frame=(%.8f,%.8f,%.8f,%.8f) matrix=(%.8f,%.8f,%.8f,%.8f)\n", cases[i].name,
                       frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
                       transform.m11, transform.m12, transform.m21, transform.m22);
            }
        } @catch (NSException *exception) {
            (void)exception;
            fputs("Synthetic layout calculation failed.\n", stderr); return 3;
        }
        puts("Only synthetic layout inputs used; no message objects accessed.");
        return 0;
    }
}

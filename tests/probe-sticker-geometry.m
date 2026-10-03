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

typedef struct { double top, left, bottom, right; } StickerInsets;

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
        SEL reactionSelector = sel_registerName("locationForStickerReactionWithParentFrame:reactionIndex:parentIsFromMe:insets:");
        SEL centerSelector = sel_registerName("stickerCenterForIndex:inFrame:alignLeft:stickerSize:");
        Class reactionLayout = objc_getClass("CKStickerReactionLayoutHelper");
        Class sticker = objc_getClass("IMSticker");
        SEL decodeSelector = sel_registerName("geometryDescriptorFromUserInfoDictionary:");
        SEL encodeSelector = sel_registerName("userInfoDictionaryWithGeometryDescriptor:");
        Ivar geometry = class_getInstanceVariable(objc_getClass("IMAssociatedMessageChatItem"), "_geometryDescriptor");
        const char *fields = "{IMAssociatedMessageGeometryDescriptor=\"layoutIntent\"Q\"associatedLayoutIntent\"Q\"parentPreviewWidth\"d\"xScalar\"d\"yScalar\"d\"scale\"d\"rotation\"d}";
        if (!geometry || strcmp(ivar_getTypeEncoding(geometry), fields) != 0
            || !matches(cls, frameSelector, "{CGRect={CGPoint=dd}{CGSize=dd}}120@0:8{CGSize=dd}16{CGRect={CGPoint=dd}{CGSize=dd}}32{IMAssociatedMessageGeometryDescriptor=QQddddd}64")
            || !matches(cls, transformSelector, "{CATransform3D=dddddddddddddddd}92@0:8{IMAssociatedMessageGeometryDescriptor=QQddddd}16B72{CGSize=dd}76")
            || !matches(cls, reactionSelector, "{CGPoint=dd}92@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16q48B56{UIEdgeInsets=dddd}60")
            || !matches(reactionLayout, centerSelector, "{CGPoint=dd}76@0:8q16{CGRect={CGPoint=dd}{CGSize=dd}}24B56{CGSize=dd}60")
            || !matches(sticker, decodeSelector, "{IMAssociatedMessageGeometryDescriptor=QQddddd}24@0:8@16")
            || !matches(sticker, encodeSelector, "@72@0:8{IMAssociatedMessageGeometryDescriptor=QQddddd}16")) {
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
            for (NSUInteger fromMe = 0; fromMe < 2; ++fromMe) {
                for (long long index = 0; index < 6; ++index) {
                    CGRect parent = CGRectMake(0, 0, 200, 100);
                    CGPoint location = ((CGPoint (*)(id, SEL, CGRect, long long, bool, StickerInsets))objc_msgSend)(
                        cls, reactionSelector, parent, index, (bool)fromMe, (StickerInsets){0, 0, 0, 0});
                    CGPoint center = ((CGPoint (*)(id, SEL, long long, CGRect, bool, CGSize))objc_msgSend)(
                        reactionLayout, centerSelector, index, parent, (bool)fromMe, CGSizeMake(64, 48));
                    printf("reaction fromMe=%lu index=%lld location=(%.8f,%.8f) helperAlignLeft=%lu center=(%.8f,%.8f)\n",
                           (unsigned long)fromMe, index, location.x, location.y,
                           (unsigned long)fromMe, center.x, center.y);
                }
            }
            for (NSUInteger version = 0; version < 2; ++version) {
                NSDictionary *info = version == 0
                    ? @{@"sli": @"0", @"sai": @"0", @"spw": @"200", @"sxs": @"0.25", @"sys": @"0.75", @"ssa": @"0.5", @"sro": @"1.5", @"spv": @0}
                    : @{@"sli": @0, @"sai": @0, @"spw": @200, @"sxs": @0.25, @"sys": @0.75, @"ssa": @0.5, @"sro": @1.5, @"spv": @1};
                StickerGeometry decoded = ((StickerGeometry (*)(id, SEL, id))objc_msgSend)(sticker, decodeSelector, info);
                id encoded = ((id (*)(id, SEL, StickerGeometry))objc_msgSend)(sticker, encodeSelector, decoded);
                if (![encoded isKindOfClass:NSDictionary.class]) return 3;
                printf("roundtrip version=%lu intents=(%llu,%llu) width=%.8f center=(%.8f,%.8f) scale=%.8f rotation=%.8f\n",
                       (unsigned long)version, decoded.layoutIntent, decoded.associatedLayoutIntent,
                       decoded.parentPreviewWidth, decoded.xScalar, decoded.yScalar, decoded.scale, decoded.rotation);
                for (NSString *key in @[@"sli", @"sai", @"spw", @"sxs", @"sys", @"ssa", @"sro", @"spv"]) {
                    id value = encoded[key];
                    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class])
                        printf("encoded %s type=%s value=%s\n", key.UTF8String,
                               [value isKindOfClass:NSString.class] ? "string" : "number", [[value description] UTF8String]);
                }
            }
            for (NSUInteger intent = 0; intent < 5; ++intent) {
                NSDictionary *info = @{@"sli": @(intent), @"sai": @0, @"spw": @200, @"sxs": @0.25,
                    @"sys": @0.75, @"ssa": @0.5, @"sro": @1.5, @"spv": @1};
                StickerGeometry decoded = ((StickerGeometry (*)(id, SEL, id))objc_msgSend)(sticker, decodeSelector, info);
                printf("decode intent=%lu intents=(%llu,%llu) width=%.8f center=(%.8f,%.8f) scale=%.8f rotation=%.8f\n",
                       (unsigned long)intent, decoded.layoutIntent, decoded.associatedLayoutIntent,
                       decoded.parentPreviewWidth, decoded.xScalar, decoded.yScalar, decoded.scale, decoded.rotation);
            }
            StickerGeometry direct = {0, 0, 200, .25, .75, .5, 1.5};
            id directInfo = ((id (*)(id, SEL, StickerGeometry))objc_msgSend)(sticker, encodeSelector, direct);
            if (![directInfo isKindOfClass:NSDictionary.class]) return 3;
            StickerGeometry reread = ((StickerGeometry (*)(id, SEL, id))objc_msgSend)(sticker, decodeSelector, directInfo);
            printf("direct geometry roundtrip width=%.8f x=%.8f y=%.8f scale=%.8f rotation=%.8f\n",
                   reread.parentPreviewWidth, reread.xScalar, reread.yScalar, reread.scale, reread.rotation);
        } @catch (NSException *exception) {
            (void)exception;
            fputs("Synthetic layout calculation failed.\n", stderr); return 3;
        }
        puts("Only synthetic layout inputs used; no message objects accessed.");
        return 0;
    }
}

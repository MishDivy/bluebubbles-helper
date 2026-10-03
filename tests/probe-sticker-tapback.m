// Constructs only synthetic tapback descriptors. Never creates a sender or sends.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

@interface NSObject (StickerTapbackProbe)
- (instancetype)initWithTransferGUID:(id)guid isRemoved:(bool)removed;
@end

static BOOL matches(Class cls, const char *selector, const char *encoding) {
    Method method = class_getInstanceMethod(cls, sel_registerName(selector));
    return method && strcmp(method_getTypeEncoding(method), encoding) == 0;
}

int main(void) {
    @autoreleasepool {
        if (!dlopen("/System/Library/PrivateFrameworks/IMCore.framework/IMCore", RTLD_NOW)) return 1;
        Class cls = objc_getClass("IMStickerTapback");
        if (!matches(cls, "initWithTransferGUID:isRemoved:", "@28@0:8@16B24")
            || !matches(cls, "associatedMessageType", "q16@0:8")
            || !matches(cls, "isRemoved", "B16@0:8")) {
            fputs("Tapback ABI differs; no descriptor constructed.\n", stderr); return 2;
        }
        @try {
            for (NSUInteger removed = 0; removed < 2; ++removed) {
                id descriptor = [[cls alloc] initWithTransferGUID:@"synthetic-nonexistent-transfer" isRemoved:(bool)removed];
                if (![descriptor isKindOfClass:cls]) return 3;
                long long type = ((long long (*)(id, SEL))objc_msgSend)(descriptor, sel_registerName("associatedMessageType"));
                bool actualRemoved = ((bool (*)(id, SEL))objc_msgSend)(descriptor, sel_registerName("isRemoved"));
                printf("Synthetic tapback: removed=%s associatedMessageType=%lld\n", actualRemoved ? "true" : "false", type);
            }
        } @catch (NSException *exception) {
            (void)exception; fputs("Synthetic descriptor construction failed.\n", stderr); return 3;
        }
        puts("No sender, file transfer, message, account, or chat was created or queried.");
        return 0;
    }
}

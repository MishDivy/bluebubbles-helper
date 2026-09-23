#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    @autoreleasepool {
        if (!dlopen("/System/Library/PrivateFrameworks/IMCore.framework/IMCore", RTLD_NOW)) return 1;
        Class chat = objc_getClass("IMChat");
        const char *selectors[] = {
            "editMessageItem:atPartIndex:withNewPartText:newPartTranslation:backwardCompatabilityText:",
            "inviteParticipants:reason:"
        };
        NSArray *types[] = {@[@"@", @(@encode(NSInteger)), @"@", @"@", @"@"], @[@"@", @"@"]};
        for (unsigned i = 0; i < 2; ++i) {
            Method method = class_getInstanceMethod(chat, sel_registerName(selectors[i]));
            if (!method) return 2;
            NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
            if (strcmp(signature.methodReturnType, "v") || signature.numberOfArguments != types[i].count + 2) return 3;
            for (NSUInteger arg = 0; arg < types[i].count; ++arg) {
                if (strcmp([signature getArgumentTypeAtIndex:arg + 2], [types[i][arg] UTF8String])) return 4;
            }
        }
        puts("Modern edit and invitation signatures verified. No chats or accounts accessed.");
    }
    return 0;
}

// Private-framework class metadata only. No instances, accounts, chats, or sends.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void printMethod(const char *name, const char *selector, BOOL factory) {
    Class cls = objc_getClass(name);
    SEL sel = sel_registerName(selector);
    Method method = factory ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    printf("%s %c%s ABI=%s\n", name, factory ? '+' : '-', selector,
           method ? method_getTypeEncoding(method) : "absent");
}

int main(void) {
    @autoreleasepool {
        if (!dlopen("/System/Library/PrivateFrameworks/IMCore.framework/IMCore", RTLD_NOW)) {
            fprintf(stderr, "IMCore load failed: %s\n", dlerror());
            return 1;
        }
        if (!dlopen("/System/iOSSupport/System/Library/PrivateFrameworks/ChatKit.framework/ChatKit", RTLD_NOW)) {
            fprintf(stderr, "Catalyst ChatKit unavailable: %s\n", dlerror());
            if (!dlopen("/System/Library/PrivateFrameworks/ChatKit.framework/ChatKit", RTLD_NOW)) {
                fprintf(stderr, "System ChatKit unavailable: %s\n", dlerror());
            }
        }
        const struct { const char *name; const char *selector; BOOL factory; } methods[] = {
            {"IMChat", "hasStoredMessageWithGUID:", NO},
            {"IMChatHistoryController", "sharedInstance", YES},
            {"IMChatHistoryController", "loadMessageWithGUID:completionBlock:", NO},
            {"IMMessage", "_imMessageItem", NO},
            {"IMMessageItem", "_newChatItems", NO},
            {"IMMessagePartChatItem", "index", NO},
            {"IMMessagePartChatItem", "messagePartRange", NO},
            {"IMAggregateAttachmentMessagePartChatItem", "aggregateAttachmentParts", NO},
            {"IMMessageItem", "setAssociatedMessageGUID:", NO},
            {"IMMessageItem", "setAssociatedMessageType:", NO},
            {"IMMessageItem", "setAssociatedMessageRange:", NO},
            {"IMMessageItem", "setMessageSummaryInfo:", NO},
            {"IMStickerTapback", "initWithTransferGUID:isRemoved:", NO},
            {"IMTapbackSender", "initWithTapback:chat:messagePartChatItem:", NO},
            {"IMTapbackSender", "send", NO},
        };
        for (NSUInteger i = 0; i < sizeof(methods) / sizeof(methods[0]); ++i) {
            printMethod(methods[i].name, methods[i].selector, methods[i].factory);
        }
        const char *classes[] = {"IMStickerTapback", "IMTapbackSender", "IMStickerUserInfo",
            "IMSticker", "CKSticker", "CKStickerInfo", "CKStickerMediaObject",
            "CKStickerMessagePartChatItem", "IMStickerMessagePartChatItem", "IMTapback",
            "IMMessagePartChatItem", "IMAssociatedStickerChatItem", "CKAssociatedStickerChatItem",
            "CKStickerReactionLayoutHelper", "IMAssociatedMessageChatItem", "IMAssociatedMessageAcknowledgmentChatItem",
            "IMTapbackChatItem", "CKTapbackChatItem", "IMStickerGeometryDescriptor",
            "IMAggregateAcknowledgmentChatItem", "IMMessageAcknowledgmentChatItem",
            "CKAssociatedMessageChatItem", "CKBrowserDraggedSticker", "CKStickerTranscriptInsertionHandler"};
        for (NSUInteger i = 0; i < sizeof(classes) / sizeof(classes[0]); ++i) {
            Class cls = objc_getClass(classes[i]);
            printf("Class %s: %s\n", classes[i], cls ? "present" : "absent");
            if (cls) printf("Superclass %s: %s\n", classes[i], class_getName(class_getSuperclass(cls)));
            unsigned int count = 0;
            Method *list = class_copyMethodList(cls, &count);
            for (unsigned int j = 0; j < count; ++j) {
                printf("%s -%s ABI=%s\n", classes[i], sel_getName(method_getName(list[j])),
                       method_getTypeEncoding(list[j]));
            }
            free(list);
            Ivar *ivars = class_copyIvarList(cls, &count);
            for (unsigned int j = 0; j < count; ++j) {
                if (strstr(ivar_getName(ivars[j]), "eometry")) {
                    printf("%s ivar %s ABI=%s\n", classes[i], ivar_getName(ivars[j]), ivar_getTypeEncoding(ivars[j]));
                }
            }
            free(ivars);
            list = class_copyMethodList(object_getClass(cls), &count);
            for (unsigned int j = 0; j < count; ++j) {
                printf("%s +%s ABI=%s\n", classes[i], sel_getName(method_getName(list[j])),
                       method_getTypeEncoding(list[j]));
            }
            free(list);
        }
        const char *messageClasses[] = {"IMMessage", "IMMessageItem"};
        for (NSUInteger i = 0; i < sizeof(messageClasses) / sizeof(messageClasses[0]); ++i) {
            unsigned int count = 0;
            Method *list = class_copyMethodList(objc_getClass(messageClasses[i]), &count);
            for (unsigned int j = 0; j < count; ++j) {
                const char *selector = sel_getName(method_getName(list[j]));
                if (strstr(selector, "initWithSender:") || strstr(selector, "AssociatedMessage")
                    || strstr(selector, "associatedMessage")) {
                    printf("%s -%s ABI=%s\n", messageClasses[i], selector, method_getTypeEncoding(list[j]));
                }
            }
            free(list);
        }
        unsigned int classCount = 0;
        Class *classList = objc_copyClassList(&classCount);
        for (unsigned int i = 0; i < classCount; ++i) {
            const char *name = class_getName(classList[i]);
            if ((strncmp(name, "IM", 2) == 0 || strncmp(name, "CK", 2) == 0)
                && (strstr(name, "Sticker") || strstr(name, "Geometry") || strstr(name, "Tapback")
                    || strstr(name, "Acknowledgment"))) printf("Sticker class: %s\n", name);
        }
        free(classList);
        const char *keys[] = {"IMStickerUserInfoLayoutIntentKey", "IMStickerUserInfoAssociatedLayoutIntentKey",
            "IMStickerUserInfoParentPreviewWidthKey", "IMStickerUserInfoXScalarKey", "IMStickerUserInfoYScalarKey",
            "IMStickerUserInfoScaleKey", "IMStickerUserInfoRotationKey", "IMStickerUserInfoTranscodedScaleKey",
            "IMStickerUserInfoStickerPositionVersionKey", "IMStickerUserInfoStickerEffectTypeKey",
            "IMStickerUserInfoStickerIsReactionKey", "IMStickerUserInfoStickerGUIDKey",
            "IMStickerUserInfoStickerPackGUIDKey", "IMStickerUserInfoStickerBundleIDKey"};
        for (NSUInteger i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i) {
            id __unsafe_unretained *value = (id __unsafe_unretained *)dlsym(RTLD_DEFAULT, keys[i]);
            if (value && [*value isKindOfClass:NSString.class]) {
                printf("Static key %s=%s\n", keys[i], [(NSString *)*value UTF8String]);
            }
        }
        puts("Metadata inventory complete. No instances created or messages accessed.");
        return 0;
    }
}

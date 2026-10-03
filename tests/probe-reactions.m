// Class metadata only: no account/chat lookup, construction, or message sends.
#import "BBHReactions.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    @autoreleasepool {
        if (!dlopen("/System/Library/PrivateFrameworks/IMCore.framework/IMCore", RTLD_NOW)) {
            fprintf(stderr, "IMCore load failed: %s\n", dlerror()); return 1;
        }
        // Upstream's Xcode project references the iOSSupport ChatKit framework;
        // its dumped header also names the older system-framework location.
        if (!dlopen("/System/iOSSupport/System/Library/PrivateFrameworks/ChatKit.framework/ChatKit", RTLD_NOW)) {
            fprintf(stderr, "ChatKit iOSSupport load failed: %s\n", dlerror());
            if (!dlopen("/System/Library/PrivateFrameworks/ChatKit.framework/ChatKit", RTLD_NOW)) {
                fprintf(stderr, "ChatKit system-framework load failed: %s\n", dlerror()); return 1;
            }
        }
        Class chat = NSClassFromString(@"IMChat"), emoji = NSClassFromString(@"IMEmojiTapback"), item = NSClassFromString(@"CKChatItem");
        printf("IMChat class: %s\n", chat ? class_getName(chat) : "absent");
        if (chat) printf("IMChat image: %s\n", class_getImageName(chat) ?: "unknown");
        const char *sendSelectors[] = {"sendTapback:forChatItem:", "sendMessageAcknowledgment:forChatItem:",
            "sendMessageAcknowledgment:forChatItem:withAssociatedMessageInfo:"};
        for (NSUInteger i = 0; i < 3; ++i) {
            Method method = class_getInstanceMethod(chat, sel_registerName(sendSelectors[i]));
            printf("IMChat %s ABI=%s\n", sendSelectors[i], method ? method_getTypeEncoding(method) : "absent");
        }
        // Method metadata can identify a renamed API; it does not authorize an invocation.
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(chat, &methodCount);
        for (unsigned int i = 0; i < methodCount; ++i) {
            const char *name = sel_getName(method_getName(methods[i]));
            if (strstr(name, "Tapback") || strstr(name, "tapback")) {
                printf("IMChat tapback research: %s ABI=%s\n", name, method_getTypeEncoding(methods[i]));
            }
        }
        free(methods);
        printf("IMChat sendTapback signature: %s\n", BBHReactionClassMethodMatches(chat,
            NSSelectorFromString(@"sendTapback:forChatItem:"), NO, "v", @[@"@", @"@"]) ? "compatible (void return)"
            : BBHReactionClassMethodMatches(chat, NSSelectorFromString(@"sendTapback:forChatItem:"), NO, "@", @[@"@", @"@"])
                ? "compatible (object return)" : "unavailable");
        printf("IMEmojiTapback initializer signature: %s\n", BBHReactionClassMethodMatches(emoji,
            @selector(initWithEmoji:isRemoved:), NO, "@", @[@"@", @(@encode(bool))]) ? "compatible" : "unavailable");
        SEL factory = BBHReactionChatItemFactory(item);
        printf("CKChatItem factory: %s\n", factory ? sel_getName(factory) : "unavailable");
        BOOL available = BBHCustomEmojiReactionsAvailable(chat, emoji, item);
        printf("Custom emoji native API available: %s; sticker reactions: unsupported.\n", available ? "yes" : "no");
        // Inventory the standalone candidate and the unverified placement APIs.
        // Inspecting a selector never invokes it or establishes delivery support.
        const struct { const char *name; const char *selector; BOOL factory; } stickerMethods[] = {
            {"CKMediaObjectManager", "mediaObjectWithSticker:stickerUserInfo:", NO},
            {"CKMediaObjectManager", "transferWithStickerFileURL:transferUserInfo:attributionInfo:", NO},
            {"CKComposition", "stickerCompositionWithMediaObjects:", YES},
            {"IMChatRegistry", "sharedInstance", YES},
            {"IMChatRegistry", "existingChatWithGUID:", NO},
            {"IMChat", "account", NO}, {"IMChat", "guid", NO}, {"IMChat", "sendMessage:", NO},
            {"IMAccount", "serviceName", NO},
            {"IMFileTransferCenter", "sharedInstance", YES},
            {"IMFileTransferCenter", "guidForNewOutgoingTransferWithLocalURL:", NO},
            {"IMFileTransferCenter", "transferForGUID:", NO},
            {"IMFileTransferCenter", "registerTransferWithDaemon:", NO},
            {"IMFileTransfer", "setIsSticker:", NO},
            {"IMFileTransfer", "setStickerUserInfo:", NO},
            {"IMFileTransfer", "setAttributionInfo:", NO},
            {"IMFileTransfer", "guid", NO}, {"IMFileTransfer", "localURL", NO},
            {"IMMessageItem", "initWithSender:time:body:attributes:fileTransferGUIDs:flags:error:guid:threadIdentifier:", NO},
            {"IMMessageItem", "setBodyData:", NO},
            {"IMMessage", "messageFromIMMessageItem:sender:subject:", YES},
            {"IMMessage", "guid", NO},
        };
        for (NSUInteger i = 0; i < sizeof(stickerMethods) / sizeof(stickerMethods[0]); ++i) {
            Class cls = objc_getClass(stickerMethods[i].name);
            SEL selector = sel_registerName(stickerMethods[i].selector);
            Method method = stickerMethods[i].factory ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
            printf("Sticker research only: %s %s ABI=%s\n", stickerMethods[i].name, stickerMethods[i].selector,
                method ? method_getTypeEncoding(method) : "absent");
        }
        puts("No chats or accounts accessed; no sends performed. Delivery remains unverified.");
        return available ? 0 : 2;
    }
}

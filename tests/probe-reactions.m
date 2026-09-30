// Class metadata only: no account/chat lookup, construction, or message sends.
#import "BBHReactions.h"
#include <dlfcn.h>
#include <stdio.h>

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
        printf("IMChat sendTapback signature: %s\n", BBHReactionClassMethodMatches(chat,
            NSSelectorFromString(@"sendTapback:forChatItem:"), NO, "v", @[@"@", @"@"]) ? "compatible" : "unavailable");
        printf("IMEmojiTapback initializer signature: %s\n", BBHReactionClassMethodMatches(emoji,
            @selector(initWithEmoji:isRemoved:), NO, "@", @[@"@", @(@encode(bool))]) ? "compatible" : "unavailable");
        SEL factory = BBHReactionChatItemFactory(item);
        printf("CKChatItem factory: %s\n", factory ? sel_getName(factory) : "unavailable");
        BOOL available = BBHCustomEmojiReactionsAvailable(chat, emoji, item);
        printf("Custom emoji native API available: %s; sticker reactions: unsupported.\n", available ? "yes" : "no");
        // Inventory only the sticker-related declarations present upstream.
        // Their existence does not establish a sticker send/removal contract.
        const char *stickerClasses[] = {"CKMediaObjectManager", "CKMediaObjectManager", "CKComposition", "IMFileTransfer", "IMFileTransfer"};
        const char *stickerSelectors[] = {"mediaObjectWithSticker:stickerUserInfo:",
            "transferWithStickerFileURL:transferUserInfo:attributionInfo:",
            "stickerCompositionWithMediaObjects:", "setIsSticker:", "setStickerUserInfo:"};
        for (NSUInteger i = 0; i < 5; ++i) {
            Class cls = objc_getClass(stickerClasses[i]);
            SEL selector = sel_registerName(stickerSelectors[i]);
            Method method = i == 2 ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
            printf("Sticker research only: %s %s ABI=%s\n", stickerClasses[i], stickerSelectors[i],
                method ? method_getTypeEncoding(method) : "absent");
        }
        puts("No chats or accounts accessed; no sends performed. Delivery remains unverified.");
        return available ? 0 : 2;
    }
}

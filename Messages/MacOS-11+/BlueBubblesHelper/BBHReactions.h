// Narrow backport of upstream development's emoji tapback path. No swizzling.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <string.h>

// Declaring the initializer gives ARC its init-family ownership semantics.
@interface NSObject (BBHEmojiTapbackInitializer)
- (instancetype)initWithEmoji:(id)emoji isRemoved:(bool)removed;
@end

static inline BOOL BBHReactionSignatureMatches(NSMethodSignature *signature,
                                               const char *result, NSArray<NSString *> *types) {
    if (!signature || strcmp(signature.methodReturnType, result)
        || signature.numberOfArguments != types.count + 2) return NO;
    for (NSUInteger i = 0; i < types.count; ++i) {
        if (strcmp([signature getArgumentTypeAtIndex:i + 2], types[i].UTF8String)) return NO;
    }
    return YES;
}

static inline BOOL BBHReactionClassMethodMatches(Class cls, SEL selector, BOOL classMethod,
                                                 const char *result, NSArray<NSString *> *types) {
    Method method = classMethod ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
    if (!method) return NO;
    return BBHReactionSignatureMatches([NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)], result, types);
}

static inline SEL BBHReactionChatItemFactory(Class cls) {
    SEL shortFactory = NSSelectorFromString(@"chatItemWithIMChatItem:balloonMaxWidth:");
    SEL fullFactory = NSSelectorFromString(@"chatItemWithIMChatItem:balloonMaxWidth:fullMaxWidth:transcriptTraitCollection:overlayLayout:");
    if (BBHReactionClassMethodMatches(cls, shortFactory, YES, "@", @[@"@", @(@encode(CGFloat))])) return shortFactory;
    if (BBHReactionClassMethodMatches(cls, fullFactory, YES, "@", @[@"@", @(@encode(CGFloat)), @(@encode(CGFloat)), @"@", @(@encode(BOOL))])) return fullFactory;
    return NULL;
}

static inline BOOL BBHCustomEmojiReactionsAvailable(Class chat, Class tapback, Class chatItem) {
    return chat && tapback && chatItem
        && BBHReactionClassMethodMatches(tapback, @selector(initWithEmoji:isRemoved:), NO, "@", @[@"@", @(@encode(bool))])
        && BBHReactionChatItemFactory(chatItem)
        && (BBHReactionClassMethodMatches(chat, NSSelectorFromString(@"sendTapback:forChatItem:"), NO, "v", @[@"@", @"@"])
            || BBHReactionClassMethodMatches(chat, NSSelectorFromString(@"sendTapback:forChatItem:"), NO, "@", @[@"@", @"@"]));
}

static inline NSDictionary *BBHReactionCapabilities(void) {
    return @{@"customEmojiReactions": @(BBHCustomEmojiReactionsAvailable(NSClassFromString(@"IMChat"),
        NSClassFromString(@"IMEmojiTapback"), NSClassFromString(@"CKChatItem"))), @"stickerReactions": @NO};
}

// Preserve the entire composed sequence (ZWJ, skin tone, flag, keycap, etc.).
// The server additionally validates that the sequence is an emoji.
static inline BOOL BBHValidReactionEmoji(id emoji) {
    if (![emoji isKindOfClass:[NSString class]] || ![emoji length] || [emoji length] > 128) return NO;
    return NSEqualRanges([emoji rangeOfComposedCharacterSequenceAtIndex:0], NSMakeRange(0, [emoji length]));
}

static inline BOOL BBHReactionPartMatches(id part, NSInteger index) {
    SEL selector = NSSelectorFromString(@"index");
    if (!part || index < 0 || ![part respondsToSelector:selector]
        || !BBHReactionSignatureMatches([part methodSignatureForSelector:selector], @encode(long long), @[])) return NO;
    return ((long long (*)(id, SEL))objc_msgSend)(part, selector) == index;
}

// Upstream returns lastSentMessage immediately. Wait for it to advance so the
// server cannot mistake the previous outgoing message for this reaction. The
// server must still verify the returned message's target/type/emoji in its DB.
static inline void BBHWaitForReactionGUID(NSString *previous, NSString *(^readGUID)(void),
                                         NSUInteger attempts, void (^completion)(NSString *)) {
    NSString *guid = readGUID();
    if (guid.length && ![guid isEqualToString:previous]) { completion(guid); return; }
    if (!attempts) { completion(nil); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        BBHWaitForReactionGUID(previous, readGUID, attempts - 1, completion);
    });
}

// nil acknowledges native dispatch, not remote delivery. A missing part must
// never fall back to reacting to the whole message or another attachment.
static inline NSString *BBHSendEmojiReaction(id chat, id part, NSString *type, id emoji,
                                            Class tapbackClass, Class chatItemClass) {
    if (!chat || !part || !([type isEqualToString:@"emoji"] || [type isEqualToString:@"-emoji"])
        || !BBHValidReactionEmoji(emoji)) return @"Invalid custom emoji reaction arguments";
    if (!BBHCustomEmojiReactionsAvailable([chat class], tapbackClass, chatItemClass))
        return @"Custom emoji reactions are unavailable in this Messages runtime";
    @try {
        SEL factory = BBHReactionChatItemFactory(chatItemClass);
        id chatItem;
        if (factory == NSSelectorFromString(@"chatItemWithIMChatItem:balloonMaxWidth:")) {
            chatItem = ((id (*)(id, SEL, id, CGFloat))objc_msgSend)(chatItemClass, factory, part, 100);
        } else {
            chatItem = ((id (*)(id, SEL, id, CGFloat, CGFloat, id, BOOL))objc_msgSend)(chatItemClass, factory, part, 100, 100, nil, NO);
        }
        if (!chatItem) return @"Unable to construct a native reaction target";
        id tapback = [[tapbackClass alloc] initWithEmoji:emoji isRemoved:[type isEqualToString:@"-emoji"]];
        if (!tapback) return @"Unable to construct a native emoji reaction";
        SEL send = NSSelectorFromString(@"sendTapback:forChatItem:");
        if (BBHReactionClassMethodMatches([chat class], send, NO, "@", @[@"@", @"@"])) {
            // macOS 27 reports an object return. Its meaning is not established;
            // use its exact ABI, and let the server confirm the reaction row.
            (void)((id (*)(id, SEL, id, id))objc_msgSend)(chat, send, tapback, chatItem);
        } else {
            ((void (*)(id, SEL, id, id))objc_msgSend)(chat, send, tapback, chatItem);
        }
    } @catch (NSException *exception) {
        (void)exception;
        return @"Native emoji reaction raised an exception";
    }
    return nil;
}

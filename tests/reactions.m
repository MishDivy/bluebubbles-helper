#import "BBHReactions.h"
#include <assert.h>
#include <stdio.h>

@interface EmojiFixture : NSObject
@property NSString *emoji;
@property bool removed;
@end
@implementation EmojiFixture
- (instancetype)initWithEmoji:(id)emoji isRemoved:(bool)removed {
    self = [super init];
    if (self) { self.emoji = emoji; self.removed = removed; }
    return self;
}
@end

@interface PartFixture : NSObject
@property long long index;
@end
@implementation PartFixture @end

@interface WrongPart : NSObject
@property id index;
@end
@implementation WrongPart @end

@interface ChatFixture : NSObject
@property EmojiFixture *tapback;
@property id part;
@property NSUInteger calls;
@end
@implementation ChatFixture
- (void)sendTapback:(id)tapback forChatItem:(id)part {
    self.tapback = tapback; self.part = part; self.calls++;
}
@end

@interface ShortFactory : NSObject @end
@implementation ShortFactory
+ (id)chatItemWithIMChatItem:(id)part balloonMaxWidth:(CGFloat)width {
    assert(width == 100); return @{@"part": part};
}
@end

@interface FullFactory : NSObject @end
@implementation FullFactory
+ (id)chatItemWithIMChatItem:(id)part balloonMaxWidth:(CGFloat)width fullMaxWidth:(CGFloat)fullWidth
    transcriptTraitCollection:(id)traits overlayLayout:(BOOL)overlay {
    assert(width == 100 && fullWidth == 100 && !traits && !overlay);
    return @{@"part": part};
}
@end

@interface WrongChat : NSObject @end
@implementation WrongChat
- (id)sendTapback:(id)tapback forChatItem:(id)part {
    (void)tapback; (void)part; assert(0); return nil;
}
@end

@interface WrongEmoji : NSObject @end
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-parameter-types" // Intentional unsupported private ABI fixture.
@implementation WrongEmoji
- (instancetype)initWithEmoji:(id)emoji isRemoved:(NSInteger)removed {
    (void)emoji; (void)removed; assert(0); return nil;
}
@end
#pragma clang diagnostic pop

@interface WrongFactory : NSObject @end
@implementation WrongFactory
+ (id)chatItemWithIMChatItem:(id)part balloonMaxWidth:(NSInteger)width {
    (void)part; (void)width; assert(0); return nil;
}
@end

@interface NilFactory : ShortFactory @end
@implementation NilFactory
+ (id)chatItemWithIMChatItem:(id)part balloonMaxWidth:(CGFloat)width {
    (void)part; (void)width; return nil;
}
@end

@interface NilEmoji : EmojiFixture @end
@implementation NilEmoji
- (instancetype)initWithEmoji:(id)emoji isRemoved:(bool)removed {
    (void)emoji; (void)removed; return nil;
}
@end

@interface ThrowingChat : ChatFixture @end
@implementation ThrowingChat
- (void)sendTapback:(id)tapback forChatItem:(id)part {
    (void)tapback; (void)part;
    [NSException raise:@"Fixture" format:@"private fixture details"];
}
@end

int main(void) {
    @autoreleasepool {
        Class emojiClass = [EmojiFixture class], chatClass = [ChatFixture class];
        id part = [NSObject new];
        NSArray *emojis = @[@"😀", @"👍🏽", @"👨‍👩‍👧‍👦", @"🇺🇸", @"1️⃣", @"❤️"];
        for (Class factory in @[[ShortFactory class], [FullFactory class]]) {
            assert(BBHCustomEmojiReactionsAvailable(chatClass, emojiClass, factory));
            ChatFixture *chat = [ChatFixture new];
            for (NSString *emoji in emojis) {
                assert(BBHValidReactionEmoji(emoji));
                assert(!BBHSendEmojiReaction(chat, part, @"emoji", emoji, emojiClass, factory));
                assert([chat.tapback.emoji isEqual:emoji] && !chat.tapback.removed);
                assert([chat.part[@"part"] isEqual:part]);
                assert(!BBHSendEmojiReaction(chat, part, @"-emoji", emoji, emojiClass, factory));
                assert([chat.tapback.emoji isEqual:emoji] && chat.tapback.removed);
            }
            assert(chat.calls == emojis.count * 2); // includes replacement with a different emoji
        }
        for (id invalid in @[@"", @"😀😀", @"two words", @42, [NSNull null]]) {
            assert(!BBHValidReactionEmoji(invalid));
            assert(BBHSendEmojiReaction([ChatFixture new], part, @"emoji", invalid, emojiClass, [ShortFactory class]));
        }
        assert(!BBHValidReactionEmoji(nil));
        assert(!BBHCustomEmojiReactionsAvailable(Nil, emojiClass, [ShortFactory class]));
        assert(!BBHCustomEmojiReactionsAvailable(chatClass, Nil, [ShortFactory class]));
        assert(!BBHCustomEmojiReactionsAvailable(chatClass, emojiClass, Nil));
        assert(!BBHCustomEmojiReactionsAvailable([WrongChat class], emojiClass, [ShortFactory class]));
        assert(!BBHCustomEmojiReactionsAvailable(chatClass, [WrongEmoji class], [ShortFactory class]));
        assert(!BBHCustomEmojiReactionsAvailable(chatClass, emojiClass, [WrongFactory class]));
        ChatFixture *chat = [ChatFixture new];
        for (Class badFactory in @[[NSObject class], [WrongFactory class], [NilFactory class]]) {
            assert(BBHSendEmojiReaction(chat, part, @"emoji", @"😀", emojiClass, badFactory));
        }
        for (Class badEmoji in @[[NSObject class], [WrongEmoji class], [NilEmoji class]]) {
            assert(BBHSendEmojiReaction(chat, part, @"emoji", @"😀", badEmoji, [ShortFactory class]));
        }
        assert(BBHSendEmojiReaction(chat, nil, @"emoji", @"😀", emojiClass, [ShortFactory class]));
        assert(BBHSendEmojiReaction(nil, part, @"emoji", @"😀", emojiClass, [ShortFactory class]));
        assert(BBHSendEmojiReaction(chat, part, @"sticker", @"😀", emojiClass, [ShortFactory class]));
        assert(chat.calls == 0);
        NSString *error = BBHSendEmojiReaction([ThrowingChat new], part, @"emoji", @"😀", emojiClass, [ShortFactory class]);
        assert(error && ![error containsString:@"private"]);
        __block NSUInteger completions = 0;
        BBHWaitForReactionGUID(@"previous", ^{ return @"new"; }, 0, ^(NSString *guid) {
            assert([guid isEqual:@"new"]); completions++;
        });
        BBHWaitForReactionGUID(@"previous", ^{ return @"previous"; }, 0, ^(NSString *guid) {
            assert(!guid); completions++;
        });
        BBHWaitForReactionGUID(nil, ^{ return @""; }, 0, ^(NSString *guid) {
            assert(!guid); completions++;
        });
        assert(completions == 3);
        __block NSUInteger reads = 0;
        BBHWaitForReactionGUID(@"previous", ^{ return ++reads < 2 ? @"previous" : @"late"; }, 2, ^(NSString *guid) {
            assert([guid isEqual:@"late"]); completions++;
        });
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (completions == 3 && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        assert(completions == 4 && reads == 2);
        PartFixture *indexedPart = [PartFixture new]; indexedPart.index = 3;
        assert(BBHReactionPartMatches(indexedPart, 3));
        assert(!BBHReactionPartMatches(indexedPart, 0));
        assert(!BBHReactionPartMatches(indexedPart, -1));
        assert(!BBHReactionPartMatches(nil, 0));
        assert(!BBHReactionPartMatches([NSObject new], 0));
        assert(!BBHReactionPartMatches([WrongPart new], 0));
        assert([BBHReactionCapabilities()[@"stickerReactions"] isEqual:@NO]);
        puts("Reaction tests passed: signatures, both factories, full emoji sequences, send/replace/remove forwarding, fail-closed capabilities, nils, exceptions, stale identifiers.");
    }
    return 0;
}

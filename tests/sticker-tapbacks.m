#import "BBHStickerTapbacks.h"
#include <assert.h>
#include <stdio.h>

@interface TAccount : NSObject
@property NSString *serviceName;
@end
@implementation TAccount @end
@interface TPart : NSObject
@property long long index;
@property NSRange messagePartRange;
@property NSArray *visible;
@end
@implementation TPart
- (id)_visibleAssociatedChatItemsByFlatteningAggregateChatItems { return self.visible; }
@end
@interface TItem : NSObject
@property id parts;
@end
@implementation TItem
- (id)_newChatItems { return self.parts; }
@end
@interface TMessage : NSObject
@property NSString *guid;
@property TItem *item;
@end
@implementation TMessage
- (id)_imMessageItem { return self.item; }
@end
@interface TChat : NSObject
@property NSString *guid;
@property TAccount *account;
@property bool containsTarget;
@property NSUInteger sends;
@property NSUInteger outcome;
@end
@implementation TChat
- (bool)hasStoredMessageWithGUID:(id)guid { return self.containsTarget && [guid isEqual:@"target"]; }
- (id)lastSentMessage { assert(0); return nil; }
@end
@interface THistory : NSObject
@property TMessage *message;
@property void (^callback)(id);
@property BOOL repeat;
@property BOOL never;
@end
@implementation THistory
+ (id)sharedInstance { return [self new]; }
- (void)loadMessageWithGUID:(id)guid completionBlock:(void (^)(id))callback {
    assert([guid isEqual:@"target"]); self.callback = callback;
    if (self.never) return;
    callback(self.message); if (self.repeat) callback(self.message);
}
@end
@interface TAttachmentAggregate : NSObject
@property NSArray *children;
@end
@implementation TAttachmentAggregate
- (id)aggregateAttachmentParts { return self.children; }
@end
@interface TAcknowledgmentAggregate : NSObject
@property NSArray *acknowledgments;
@end
@implementation TAcknowledgmentAggregate @end
@interface TTapback : NSObject
@property NSString *transferGUID;
@property bool isRemoved;
@property long long associatedMessageType;
@end
@implementation TTapback
- (instancetype)initWithTransferGUID:(id)guid isRemoved:(bool)removed {
    self = [super init];
    if (self) { self.transferGUID = guid; self.isRemoved = removed; self.associatedMessageType = removed ? 3007 : 2007; }
    return self;
}
@end
@interface TAssociated : NSObject
@property bool isFromMe;
@property bool isReaction;
@property long long associatedMessageType;
@property NSString *associatedMessageGUID;
@property TTapback *tapback;
@property TMessage *message;
@end
@implementation TAssociated @end
@interface TTransfer : NSObject
@property NSString *guid;
@property NSURL *localURL;
@property bool isSticker;
@property NSDictionary *stickerUserInfo;
@property NSDictionary *attributionInfo;
@end
@implementation TTransfer @end
@interface TCenter : NSObject
@property TTransfer *transfer;
@property NSUInteger allocations;
@property NSUInteger registrations;
@property BOOL throws;
@end
@implementation TCenter
+ (id)sharedInstance { return [self new]; }
- (id)guidForNewOutgoingTransferWithLocalURL:(id)url {
    self.allocations++; self.transfer = [TTransfer new]; self.transfer.guid = @"new-transfer";
    self.transfer.localURL = url; return self.transfer.guid;
}
- (id)transferForGUID:(id)guid { assert([guid isEqual:self.transfer.guid]); return self.transfer; }
- (void)registerTransferWithDaemon:(id)guid {
    assert([guid isEqual:self.transfer.guid] && self.transfer.isSticker && self.transfer.stickerUserInfo.count);
    assert(!self.transfer.attributionInfo && [self.transfer.stickerUserInfo[@"sir"] isEqual:@NO]);
    self.registrations++;
    if (self.throws) [NSException raise:@"Synthetic" format:@"private transfer details"];
}
@end
@interface TSender : NSObject
@property TChat *chat;
@property TTapback *tapback;
@end
@implementation TSender
- (instancetype)initWithTapback:(id)tapback chat:(id)chat messagePartChatItem:(id)part {
    assert([part isKindOfClass:TPart.class]); self = [super init];
    if (self) { self.chat = chat; self.tapback = tapback; } return self;
}
- (id)send {
    self.chat.sends++;
    if (self.chat.outcome == 1) return nil;
    if (self.chat.outcome == 2) [NSException raise:@"Synthetic" format:@"private conversation details"];
    if (self.chat.outcome == 3) return @"not a message";
    TMessage *message = [TMessage new]; message.guid = self.chat.outcome == 4 ? @"target" : @"exact-sender-result";
    return message;
}
@end
@interface TNilSender : TSender @end
@implementation TNilSender
- (instancetype)initWithTapback:(id)tapback chat:(id)chat messagePartChatItem:(id)part {
    (void)tapback; (void)chat; (void)part; return nil;
}
@end
@interface TWrongSender : NSObject @end
@implementation TWrongSender
- (instancetype)initWithTapback:(id)tapback chat:(id)chat messagePartChatItem:(id)part {
    (void)tapback; (void)chat; (void)part; assert(0); return nil;
}
- (void)send { assert(0); }
@end

@interface TRegistry : NSObject @end
@implementation TRegistry
+ (id)sharedInstance { assert(0); return nil; }
- (id)existingChatWithGUID:(id)guid { (void)guid; assert(0); return nil; }
@end

static void Alias(Class parent, const char *name) {
    assert(!objc_getClass(name)); Class alias = objc_allocateClassPair(parent, name, 0);
    assert(alias); objc_registerClassPair(alias);
}

static NSString *Send(TChat *chat, TPart *part, NSDictionary *request, BOOL remove, NSString *root,
                      TCenter *center, Class sender, NSString **guid) {
    return BBHSendStickerTapback(chat, part, request, remove, root, center, TTransfer.class,
        TTapback.class, sender, TAssociated.class, TAcknowledgmentAggregate.class, TMessage.class, guid);
}

static TAssociated *Own(void) {
    TAssociated *item = [TAssociated new]; item.isFromMe = true; item.isReaction = true;
    item.associatedMessageType = 2007; item.associatedMessageGUID = @"p:0/target";
    item.tapback = [[TTapback alloc] initWithTransferGUID:@"existing-native-transfer" isRemoved:false];
    item.message = [TMessage new]; item.message.guid = @"current-reaction"; return item;
}

static NSArray *Snapshots(NSString *root) {
    NSMutableArray *result = [NSMutableArray new];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:NULL])
        if ([name hasPrefix:@"bbh-sticker-"]) [result addObject:[root stringByAppendingPathComponent:name]];
    return result;
}

static void Pump(NSTimeInterval interval) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:interval]];
}

int main(void) {
    @autoreleasepool {
        assert(BBHStickerTargetABI(TChat.class, THistory.class, TMessage.class, TItem.class, TPart.class));
        assert(BBHStickerTapbackABI(TTapback.class, TSender.class, TAssociated.class, TAcknowledgmentAggregate.class, TPart.class));
        assert(!BBHStickerTapbackABI(TTapback.class, TWrongSender.class, TAssociated.class, TAcknowledgmentAggregate.class, TPart.class));
        assert(!BBHStickerReactionsAvailable()); // Synthetic class names are never native capability evidence.
        assert(!BBHStickerTargetArguments(@"target", @YES));
        assert(!BBHStickerTargetArguments(@"target", @0.5));
        assert(!BBHStickerTargetArguments(@"target", @(-1)));
        TChat *chat = [TChat new]; chat.guid = @"chat"; chat.containsTarget = true;
        chat.account = [TAccount new]; chat.account.serviceName = @"iMessage";
        TPart *part = [TPart new]; part.index = 0; part.messagePartRange = NSMakeRange(2, 5); part.visible = @[];
        TItem *item = [TItem new]; item.parts = @[part];
        TMessage *target = [TMessage new]; target.guid = @"target"; target.item = item;
        NSRange range;
        assert(BBHStickerFindTargetPart(chat, target, @"target", 0, TAttachmentAggregate.class, &range) == part);
        assert(NSEqualRanges(range, part.messagePartRange));
        assert(!BBHStickerFindTargetPart(chat, target, @"target", 1, TAttachmentAggregate.class, &range));
        item.parts = @[part, part]; assert(!BBHStickerFindTargetPart(chat, target, @"target", 0, TAttachmentAggregate.class, &range));
        TAttachmentAggregate *aggregate = [TAttachmentAggregate new]; aggregate.children = @[part]; item.parts = @[aggregate];
        assert(BBHStickerFindTargetPart(chat, target, @"target", 0, TAttachmentAggregate.class, &range) == part);
        part.messagePartRange = NSMakeRange(NSUIntegerMax, 2);
        assert(!BBHStickerFindTargetPart(chat, target, @"target", 0, TAttachmentAggregate.class, &range));
        part.messagePartRange = NSMakeRange(2, 5); chat.containsTarget = false;
        assert(!BBHStickerFindTargetPart(chat, target, @"target", 0, TAttachmentAggregate.class, &range));
        chat.containsTarget = true; target.guid = @"different";
        assert(!BBHStickerFindTargetPart(chat, target, @"target", 0, TAttachmentAggregate.class, &range));
        target.guid = @"target";
        THistory *history = [THistory new]; history.message = target; history.repeat = YES;
        __block NSUInteger calls = 0;
        BBHLoadStickerTarget(chat, @"target", 0, history, TAttachmentAggregate.class, 40, ^(id found, NSRange foundRange, NSString *error) {
            assert(found == part && NSEqualRanges(foundRange, part.messagePartRange) && !error); calls++;
        });
        Pump(0.07); assert(calls == 1);
        history.never = YES;
        BBHLoadStickerTarget(chat, @"target", 0, history, TAttachmentAggregate.class, 1, ^(id found, NSRange foundRange, NSString *error) {
            (void)foundRange; assert(!found && [error containsString:@"timed out"]); calls++;
        });
        Pump(0.03); assert(calls == 2); history.callback(target); Pump(0.03); assert(calls == 2);

        char directory[] = "/private/tmp/bbh-tapbacks.XXXXXX";
        assert(mkdtemp(directory)); NSString *root = [NSString stringWithUTF8String:directory];
        NSString *path = [root stringByAppendingPathComponent:@"synthetic.png"];
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, 2, 2, 8, 8, space, kCGImageAlphaPremultipliedLast);
        assert(context); CGImageRef frame = CGBitmapContextCreateImage(context);
        NSMutableData *png = [NSMutableData new];
        CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)png, CFSTR("public.png"), 1, NULL);
        assert(destination); CGImageDestinationAddImage(destination, frame, NULL); assert(CGImageDestinationFinalize(destination));
        CFRelease(destination); CGImageRelease(frame); CGContextRelease(context); CGColorSpaceRelease(space);
        int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL, 0600);
        assert(fd >= 0 && write(fd, png.bytes, png.length) == (ssize_t)png.length && !close(fd));
        NSDictionary *add = @{@"chatGuid": @"chat", @"selectedMessageGuid": @"target", @"partIndex": @0, @"filePath": path};
        NSDictionary *remove = @{@"chatGuid": @"chat", @"selectedMessageGuid": @"target", @"partIndex": @0, @"reactionGuid": @"current-reaction"};
        assert(BBHStickerTapbackRequestValid(add, NO) && BBHStickerTapbackRequestValid(remove, YES));
        NSMutableDictionary *invalid = [remove mutableCopy]; invalid[@"filePath"] = path;
        assert(!BBHStickerTapbackRequestValid(invalid, YES));
        [invalid removeObjectForKey:@"filePath"]; [invalid removeObjectForKey:@"reactionGuid"];
        assert(!BBHStickerTapbackRequestValid(invalid, YES));
        TAssociated *own = Own(); part.visible = @[own];
        assert([BBHStickerOwnReaction(part, remove, TAssociated.class, TAcknowledgmentAggregate.class, TTapback.class, TMessage.class) isEqual:@"existing-native-transfer"]);
        TAcknowledgmentAggregate *ack = [TAcknowledgmentAggregate new]; ack.acknowledgments = @[own]; part.visible = @[ack];
        assert(BBHStickerOwnReaction(part, remove, TAssociated.class, TAcknowledgmentAggregate.class, TTapback.class, TMessage.class));
        part.visible = @[own, Own()];
        assert(!BBHStickerOwnReaction(part, remove, TAssociated.class, TAcknowledgmentAggregate.class, TTapback.class, TMessage.class));
        part.visible = @[own]; own.isFromMe = false;
        assert(!BBHStickerOwnReaction(part, remove, TAssociated.class, TAcknowledgmentAggregate.class, TTapback.class, TMessage.class));
        own.isFromMe = true; own.message.guid = @"newer-replacement";
        assert(!BBHStickerOwnReaction(part, remove, TAssociated.class, TAcknowledgmentAggregate.class, TTapback.class, TMessage.class));
        own.message.guid = @"current-reaction"; own.tapback.isRemoved = true;
        assert(!BBHStickerOwnReaction(part, remove, TAssociated.class, TAcknowledgmentAggregate.class, TTapback.class, TMessage.class));
        own.tapback.isRemoved = false;
        NSString *guid = nil; TCenter *center = [TCenter new];
        NSString *error = Send(chat, part, add, NO, root, center, TSender.class, &guid);
        if (BBH_EXPERIMENTAL_STICKERS == 1) {
            assert(!error && [guid isEqual:@"exact-sender-result"] && chat.sends == 1 && center.registrations == 1 && Snapshots(root).count == 1);
            for (NSString *snapshot in Snapshots(root)) BBHStickerRemoveSnapshot(snapshot, root);
            center = [TCenter new]; chat.sends = 0;
            assert(!Send(chat, part, remove, YES, root, center, TSender.class, &guid));
            assert(guid && chat.sends == 1 && center.allocations == 0 && center.registrations == 0 && !Snapshots(root).count);
            own.message.guid = @"newer-replacement"; chat.sends = 0;
            assert(Send(chat, part, remove, YES, root, center, TSender.class, &guid));
            assert(!guid && !chat.sends && !center.allocations); own.message.guid = @"current-reaction";
            chat.containsTarget = false;
            assert(Send(chat, part, add, NO, root, center, TSender.class, &guid) && !center.allocations && !Snapshots(root).count);
            chat.containsTarget = true; chat.account.serviceName = @"SMS";
            assert(Send(chat, part, add, NO, root, center, TSender.class, &guid) && !center.allocations);
            chat.account.serviceName = @"iMessage";
            assert(Send(chat, part, add, NO, root, center, TWrongSender.class, &guid) && !center.allocations);
            assert(Send(chat, part, add, NO, root, center, TNilSender.class, &guid) && center.allocations == 1 && !center.registrations && !Snapshots(root).count);
            center = [TCenter new]; center.throws = YES;
            error = Send(chat, part, add, NO, root, center, TSender.class, &guid);
            assert([error containsString:@"unknown"] && !guid && !chat.sends && center.registrations == 1 && Snapshots(root).count == 1);
            for (NSString *snapshot in Snapshots(root)) BBHStickerRemoveSnapshot(snapshot, root);
            for (NSUInteger outcome = 1; outcome <= 4; outcome++) {
                center = [TCenter new]; chat.outcome = outcome; chat.sends = 0;
                error = Send(chat, part, add, NO, root, center, TSender.class, &guid);
                assert([error containsString:@"unknown"] && !guid && chat.sends == 1 && center.registrations == 1 && Snapshots(root).count == 1);
                for (NSString *snapshot in Snapshots(root)) BBHStickerRemoveSnapshot(snapshot, root);
                chat.sends = 0;
                error = Send(chat, part, remove, YES, root, center, TSender.class, &guid);
                assert([error containsString:@"unknown"] && !guid && chat.sends == 1 && !Snapshots(root).count);
            }
        } else assert(error && !guid && !chat.sends && !center.allocations && !Snapshots(root).count);
        assert([BBHStickerRead(path, root) isEqual:png]);
        assert(!unlink(path.fileSystemRepresentation) && !rmdir(root.fileSystemRepresentation));
        Alias(TRegistry.class, "IMChatRegistry"); Alias(TChat.class, "IMChat"); Alias(TAccount.class, "IMAccount");
        Alias(THistory.class, "IMChatHistoryController"); Alias(TMessage.class, "IMMessage"); Alias(TItem.class, "IMMessageItem");
        Alias(TPart.class, "IMMessagePartChatItem"); Alias(TAttachmentAggregate.class, "IMAggregateAttachmentMessagePartChatItem");
        Alias(TCenter.class, "IMFileTransferCenter"); Alias(TTransfer.class, "IMFileTransfer"); Alias(TTapback.class, "IMStickerTapback");
        Alias(TSender.class, "IMTapbackSender"); Alias(TAssociated.class, "IMAssociatedMessageChatItem");
        Alias(TAcknowledgmentAggregate.class, "IMAggregateAcknowledgmentChatItem");
        assert(BBHStickerReactionsAvailable() == (BBH_EXPERIMENTAL_STICKERS == 1));
        assert([BBHNativeStickerCapabilities()[@"stickerReactions"] boolValue] == (BBH_EXPERIMENTAL_STICKERS == 1));
        puts("Sticker tapback tests passed: gate, ABI, target ownership/range, timeout, exact result, stale/ambiguous removal, pre-registration cleanup, unknown outcomes.");
    }
    return 0;
}

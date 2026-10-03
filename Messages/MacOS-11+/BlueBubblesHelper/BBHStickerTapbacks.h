// Sticker tapback constructors adapt imbridge's pinned 0010 patch, Apache-2.0.
// Modified: exact ABI/ownership checks, bounded target lookup, private snapshots,
// stale-removal protection, and exact returned-message identity. See NOTICE.
#pragma once
#import "BBHStickerTargets.h"

@interface NSObject (BBHStickerTapbackInitializers)
- (instancetype)initWithTransferGUID:(id)guid isRemoved:(bool)removed;
- (instancetype)initWithTapback:(id)tapback chat:(id)chat messagePartChatItem:(id)part;
@end

static inline BOOL BBHStickerTapbackRequestValid(id request, BOOL remove) {
    if (![request isKindOfClass:NSDictionary.class]) return NO;
    NSArray *allowed = remove ? @[@"chatGuid", @"selectedMessageGuid", @"partIndex", @"reactionGuid"]
        : @[@"chatGuid", @"selectedMessageGuid", @"partIndex", @"filePath", @"filename", @"stickerLabel"];
    for (id key in request) if (![allowed containsObject:key]) return NO;
    if (!BBHStickerString(request[@"chatGuid"], 1024)
        || !BBHStickerTargetArguments(request[@"selectedMessageGuid"], request[@"partIndex"])) return NO;
    if (remove) return BBHStickerString(request[@"reactionGuid"], 1024);
    NSMutableDictionary *asset = [request mutableCopy];
    [asset removeObjectsForKeys:@[@"chatGuid", @"selectedMessageGuid", @"partIndex"]];
    return BBHStickerFieldsValid(asset, NO);
}

static inline BOOL BBHStickerAssociatedABI(Class associated) {
    return BBHStickerMethod(associated, @"isFromMe", NO, @encode(bool), @[])
        && BBHStickerMethod(associated, @"isReaction", NO, @encode(bool), @[])
        && BBHStickerMethod(associated, @"tapback", NO, "@", @[])
        && BBHStickerMethod(associated, @"associatedMessageType", NO, @encode(long long), @[])
        && BBHStickerMethod(associated, @"associatedMessageGUID", NO, "@", @[])
        && BBHStickerMethod(associated, @"message", NO, "@", @[]);
}

static inline BOOL BBHStickerTapbackABI(Class tapback, Class sender, Class associated, Class aggregate, Class part) {
    return BBHStickerMethod(tapback, @"initWithTransferGUID:isRemoved:", NO, "@", @[@"@", @(@encode(bool))])
        && BBHStickerMethod(tapback, @"transferGUID", NO, "@", @[])
        && BBHStickerMethod(tapback, @"isRemoved", NO, @encode(bool), @[])
        && BBHStickerMethod(tapback, @"associatedMessageType", NO, @encode(long long), @[])
        && BBHStickerMethod(sender, @"initWithTapback:chat:messagePartChatItem:", NO, "@", @[@"@", @"@", @"@"])
        && BBHStickerMethod(sender, @"send", NO, "@", @[])
        && BBHStickerMethod(part, @"_visibleAssociatedChatItemsByFlatteningAggregateChatItems", NO, "@", @[])
        && BBHStickerMethod(aggregate, @"acknowledgments", NO, "@", @[])
        && BBHStickerAssociatedABI(associated);
}

static inline BOOL BBHStickerTapbackChatABI(Class chat, Class account, Class center, Class transfer, Class message) {
    return BBHStickerMethod(chat, @"account", NO, "@", @[])
        && BBHStickerMethod(chat, @"guid", NO, "@", @[])
        && BBHStickerMethod(account, @"serviceName", NO, "@", @[])
        && BBHStickerMethod(center, @"sharedInstance", YES, "@", @[])
        && BBHStickerMethod(center, @"guidForNewOutgoingTransferWithLocalURL:", NO, "@", @[@"@"])
        && BBHStickerMethod(center, @"transferForGUID:", NO, "@", @[@"@"])
        && BBHStickerMethod(center, @"registerTransferWithDaemon:", NO, "v", @[@"@"])
        && BBHStickerTransferABI(transfer)
        && BBHStickerMethod(message, @"guid", NO, "@", @[]);
}

static inline BOOL BBHStickerReactionsAvailable(void) {
    return BBH_EXPERIMENTAL_STICKERS == 1
        && BBHStickerMethod(NSClassFromString(@"IMChatRegistry"), @"sharedInstance", YES, "@", @[])
        && BBHStickerMethod(NSClassFromString(@"IMChatRegistry"), @"existingChatWithGUID:", NO, "@", @[@"@"])
        && BBHStickerTargetABI(NSClassFromString(@"IMChat"), NSClassFromString(@"IMChatHistoryController"),
            NSClassFromString(@"IMMessage"), NSClassFromString(@"IMMessageItem"), NSClassFromString(@"IMMessagePartChatItem"))
        && BBHStickerMethod(NSClassFromString(@"IMAggregateAttachmentMessagePartChatItem"), @"aggregateAttachmentParts", NO, "@", @[])
        && BBHStickerTapbackChatABI(NSClassFromString(@"IMChat"), NSClassFromString(@"IMAccount"),
            NSClassFromString(@"IMFileTransferCenter"), NSClassFromString(@"IMFileTransfer"), NSClassFromString(@"IMMessage"))
        && BBHStickerTapbackABI(NSClassFromString(@"IMStickerTapback"), NSClassFromString(@"IMTapbackSender"),
            NSClassFromString(@"IMAssociatedMessageChatItem"), NSClassFromString(@"IMAggregateAcknowledgmentChatItem"),
            NSClassFromString(@"IMMessagePartChatItem"));
}

static inline NSDictionary *BBHNativeStickerCapabilities(void) {
    NSMutableDictionary *capabilities = [BBHHelperCapabilities() mutableCopy];
    capabilities[@"stickerReactions"] = @(BBHStickerReactionsAvailable());
    return capabilities;
}

static inline bool BBHStickerBool(id object, NSString *name) {
    return ((bool (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(name));
}

static inline long long BBHStickerInteger(id object, NSString *name) {
    return ((long long (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(name));
}

// Only a uniquely visible, own, live sticker reaction may supply a removal GUID.
static inline id BBHStickerOwnReaction(id part, NSDictionary *request, Class associatedClass,
                                     Class aggregateClass, Class tapbackClass, Class messageClass) {
    if (!BBHStickerMethod([part class], @"_visibleAssociatedChatItemsByFlatteningAggregateChatItems", NO, "@", @[])) return nil;
    id visible = BBHStickerObject(part, @"_visibleAssociatedChatItemsByFlatteningAggregateChatItems");
    if (![visible isKindOfClass:NSArray.class] || [visible count] > 256) return nil;
    NSMutableArray *items = [NSMutableArray new];
    for (id item in visible) {
        if ([item isKindOfClass:aggregateClass]) {
            if (!BBHStickerMethod([item class], @"acknowledgments", NO, "@", @[])) return nil;
            id children = BBHStickerObject(item, @"acknowledgments");
            if (![children isKindOfClass:NSArray.class] || [children count] > 256 - items.count) return nil;
            [items addObjectsFromArray:children];
        } else {
            if (items.count == 256) return nil;
            [items addObject:item];
        }
    }
    NSString *association = [NSString stringWithFormat:@"p:%ld/%@", (long)[request[@"partIndex"] integerValue], request[@"selectedMessageGuid"]];
    id found = nil;
    for (id item in items) {
        if (![item isKindOfClass:associatedClass]) continue;
        if (!BBHStickerAssociatedABI([item class])) return nil;
        if (!BBHStickerBool(item, @"isFromMe") || !BBHStickerBool(item, @"isReaction")
            || BBHStickerInteger(item, @"associatedMessageType") != 2007
            || ![BBHStickerObject(item, @"associatedMessageGUID") isEqual:association]) continue;
        id tapback = BBHStickerObject(item, @"tapback");
        id message = BBHStickerObject(item, @"message");
        if (![tapback isKindOfClass:tapbackClass]
            || !BBHStickerMethod([tapback class], @"isRemoved", NO, @encode(bool), @[])
            || !BBHStickerMethod([tapback class], @"associatedMessageType", NO, @encode(long long), @[])
            || !BBHStickerMethod([tapback class], @"transferGUID", NO, "@", @[])
            || ![message isKindOfClass:messageClass] || !BBHStickerMethod([message class], @"guid", NO, "@", @[])) return nil;
        if (BBHStickerBool(tapback, @"isRemoved") || BBHStickerInteger(tapback, @"associatedMessageType") != 2007) continue;
        if (found) return nil;
        found = item;
    }
    if (!found || ![BBHStickerObject(BBHStickerObject(found, @"message"), @"guid") isEqual:request[@"reactionGuid"]]) return nil;
    id guid = BBHStickerObject(BBHStickerObject(found, @"tapback"), @"transferGUID");
    return BBHStickerString(guid, 1024) ? guid : nil;
}

static inline NSString *BBHSendStickerTapback(id chat, id part, NSDictionary *request, BOOL remove,
    NSString *root, id center, Class transferClass, Class tapbackClass, Class senderClass,
    Class associatedClass, Class aggregateClass, Class messageClass, NSString **outGUID) {
    if (outGUID) *outGUID = nil;
    if (!BBHStickerTapbackRequestValid(request, remove)) return @"Invalid sticker reaction request";
    if (BBH_EXPERIMENTAL_STICKERS != 1) return @"Experimental sticker reactions are disabled";
    NSString *snapshot = nil; BOOL registered = NO, attempted = NO;
    @try {
        if (!BBHStickerMethod([chat class], @"account", NO, "@", @[])) return @"Native sticker reactions are unavailable";
        id account = BBHStickerObject(chat, @"account");
        if (!BBHStickerTapbackChatABI([chat class], [account class], [center class], transferClass, messageClass)
            || !BBHStickerTapbackABI(tapbackClass, senderClass, associatedClass, aggregateClass, [part class])
            || !BBHStickerMethod([part class], @"index", NO, @encode(long long), @[])
            || BBHStickerInteger(part, @"index") != [request[@"partIndex"] integerValue]
            || !BBHStickerTargetBelongsToChat(chat, request[@"selectedMessageGuid"])
            || ![BBHStickerObject(chat, @"guid") isEqual:request[@"chatGuid"]]) return @"Native sticker reaction target is unavailable";
        if (![BBHStickerObject(account, @"serviceName") isEqual:@"iMessage"]) return @"Stickers require a native iMessage chat";
        id transferGUID = nil;
        if (remove) {
            transferGUID = BBHStickerOwnReaction(part, request, associatedClass, aggregateClass, tapbackClass, messageClass);
            if (!transferGUID) return @"Current own sticker reaction is unavailable or changed";
        } else {
            NSData *data = BBHStickerRead(request[@"filePath"], root);
            NSDictionary *image = BBHStickerImage(data);
            if (!image) return @"Invalid or inaccessible sticker image";
            snapshot = BBHStickerSnapshot(data, request[@"filePath"], image[@"extension"], root);
            if (!snapshot || ![BBHStickerRead(snapshot, root) isEqual:data]) return @"Unable to snapshot sticker image";
            id transfer = BBHStickerPrepareTransfer(center, transferClass, snapshot);
            if (!transfer) return @"Unable to prepare native sticker transfer";
            transferGUID = BBHStickerObject(transfer, @"guid");
            BBHStickerApplyMetadata(transfer, @{@"pid": @"com.apple.Stickers.UserGenerated.MessagesExtension",
                @"shash": BBHStickerDigest(data, YES), @"sid": snapshot.lastPathComponent,
                @"sir": @NO, @"spv": @0, @"suri": @"sticker:///user/identifier/"}, nil);
        }
        id tapback = [[tapbackClass alloc] initWithTransferGUID:transferGUID isRemoved:(bool)remove];
        if (![tapback isKindOfClass:tapbackClass]
            || !BBHStickerMethod([tapback class], @"transferGUID", NO, "@", @[])
            || !BBHStickerMethod([tapback class], @"isRemoved", NO, @encode(bool), @[])
            || !BBHStickerMethod([tapback class], @"associatedMessageType", NO, @encode(long long), @[])
            || ![BBHStickerObject(tapback, @"transferGUID") isEqual:transferGUID]
            || BBHStickerBool(tapback, @"isRemoved") != (bool)remove
            || BBHStickerInteger(tapback, @"associatedMessageType") != (remove ? 3007 : 2007)) return @"Unable to construct native sticker reaction";
        id sender = [[senderClass alloc] initWithTapback:tapback chat:chat messagePartChatItem:part];
        if (![sender isKindOfClass:senderClass] || !BBHStickerMethod([sender class], @"send", NO, "@", @[]))
            return @"Unable to construct native sticker reaction";
        if (!BBHStickerTargetBelongsToChat(chat, request[@"selectedMessageGuid"])) return @"Native sticker reaction target changed";
        if (remove) {
            if (![BBHStickerOwnReaction(part, request, associatedClass, aggregateClass, tapbackClass, messageClass) isEqual:transferGUID])
                return @"Current own sticker reaction is unavailable or changed";
        } else {
            registered = YES;
            ((void (*)(id, SEL, id))objc_msgSend)(center, NSSelectorFromString(@"registerTransferWithDaemon:"), transferGUID);
        }
        attempted = YES;
        id message = BBHStickerObject(sender, @"send");
        if (![message isKindOfClass:messageClass] || !BBHStickerMethod([message class], @"guid", NO, "@", @[]))
            return @"Sticker reaction dispatch outcome is unknown; do not retry";
        id guid = BBHStickerObject(message, @"guid");
        if (!BBHStickerString(guid, 1024) || [guid isEqual:request[@"selectedMessageGuid"]]
            || [guid isEqual:request[@"reactionGuid"]]) return @"Sticker reaction dispatch outcome is unknown; do not retry";
        if (outGUID) *outGUID = [guid copy];
        return nil;
    } @catch (NSException *exception) {
        (void)exception;
        return registered || attempted ? @"Sticker reaction dispatch outcome is unknown; do not retry" : @"Native sticker reaction preparation failed";
    } @finally {
        if (!registered) BBHStickerRemoveSnapshot(snapshot, root);
    }
}

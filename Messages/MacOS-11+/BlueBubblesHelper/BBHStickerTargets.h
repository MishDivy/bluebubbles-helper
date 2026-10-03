// Native target lookup shared by placement and sticker tapback operations.
#pragma once
#import "BBHStickers.h"

static inline BOOL BBHStickerTargetArguments(id targetGUID, id partIndex) {
    return BBHStickerString(targetGUID, 1024) && [partIndex isKindOfClass:NSNumber.class]
        && CFGetTypeID((__bridge CFTypeRef)partIndex) != CFBooleanGetTypeID()
        && [partIndex integerValue] >= 0 && [partIndex doubleValue] == (double)[partIndex integerValue];
}

static inline BOOL BBHStickerTargetABI(Class chat, Class history, Class message, Class item, Class part) {
    return BBHStickerMethod(chat, @"hasStoredMessageWithGUID:", NO, "B", @[@"@"])
        && BBHStickerMethod(history, @"sharedInstance", YES, "@", @[])
        && BBHStickerMethod(history, @"loadMessageWithGUID:completionBlock:", NO, "v", @[@"@", @"@?"])
        && BBHStickerMethod(message, @"guid", NO, "@", @[])
        && BBHStickerMethod(message, @"_imMessageItem", NO, "@", @[])
        && BBHStickerMethod(item, @"_newChatItems", NO, "@", @[])
        && BBHStickerMethod(part, @"index", NO, @encode(long long), @[])
        && BBHStickerMethod(part, @"messagePartRange", NO, @encode(NSRange), @[]);
}

static inline BOOL BBHStickerTargetBelongsToChat(id chat, NSString *guid) {
    return chat && BBHStickerMethod([chat class], @"hasStoredMessageWithGUID:", NO, "B", @[@"@"])
        && ((bool (*)(id, SEL, id))objc_msgSend)(chat, NSSelectorFromString(@"hasStoredMessageWithGUID:"), guid);
}

static inline id BBHStickerFindTargetPart(id chat, id message, NSString *guid, NSInteger index,
                                        Class aggregateClass, NSRange *outRange) {
    if (outRange) *outRange = NSMakeRange(0, 0);
    if (index < 0 || !BBHStickerTargetBelongsToChat(chat, guid)
        || !BBHStickerMethod([message class], @"guid", NO, "@", @[])
        || ![BBHStickerObject(message, @"guid") isEqual:guid]
        || !BBHStickerMethod([message class], @"_imMessageItem", NO, "@", @[])) return nil;
    id messageItem = BBHStickerObject(message, @"_imMessageItem");
    if (!BBHStickerMethod([messageItem class], @"_newChatItems", NO, "@", @[])) return nil;
    id items = BBHStickerObject(messageItem, @"_newChatItems");
    NSArray *parts = [items isKindOfClass:NSArray.class] ? items : items ? @[items] : @[];
    if (parts.count > 256) return nil;
    NSMutableArray *candidates = [NSMutableArray new];
    for (id part in parts) {
        if (aggregateClass && [part isKindOfClass:aggregateClass]) {
            if (!BBHStickerMethod([part class], @"aggregateAttachmentParts", NO, "@", @[])) return nil;
            id children = BBHStickerObject(part, @"aggregateAttachmentParts");
            if (![children isKindOfClass:NSArray.class] || [children count] > 256 - candidates.count) return nil;
            [candidates addObjectsFromArray:children];
        } else {
            if (candidates.count == 256) return nil;
            [candidates addObject:part];
        }
    }
    id found = nil; NSRange range = NSMakeRange(0, 0);
    for (id part in candidates) {
        if (!BBHStickerMethod([part class], @"index", NO, @encode(long long), @[])
            || !BBHStickerMethod([part class], @"messagePartRange", NO, @encode(NSRange), @[])) continue;
        if (((long long (*)(id, SEL))objc_msgSend)(part, NSSelectorFromString(@"index")) != index) continue;
        if (found) return nil;
        range = ((NSRange (*)(id, SEL))objc_msgSend)(part, NSSelectorFromString(@"messagePartRange"));
        if (!range.length || range.location > NSUIntegerMax - range.length) return nil;
        found = part;
    }
    if (found && outRange) *outRange = range;
    return found;
}

static inline void BBHLoadStickerTarget(id chat, NSString *guid, NSInteger index, id history,
                                       Class aggregateClass, NSUInteger timeoutMilliseconds,
                                       void (^completion)(id, NSRange, NSString *)) {
    // Lookup and its deadline settle on the main queue before any registration.
    __block BOOL finished = NO;
    void (^finish)(id, NSRange, NSString *) = ^(id part, NSRange range, NSString *error) {
        if (finished) return;
        finished = YES; completion(part, range, error);
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)timeoutMilliseconds * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        finish(nil, NSMakeRange(0, 0), @"Native sticker target lookup timed out");
    });
    @try {
        if (!BBHStickerTargetBelongsToChat(chat, guid)
            || !BBHStickerMethod([history class], @"loadMessageWithGUID:completionBlock:", NO, "v", @[@"@", @"@?"])) {
            finish(nil, NSMakeRange(0, 0), @"Native sticker target is unavailable"); return;
        }
        ((void (*)(id, SEL, id, void (^)(id)))objc_msgSend)(history, NSSelectorFromString(@"loadMessageWithGUID:completionBlock:"), guid, ^(id message) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (finished) return;
                @try {
                    NSRange range;
                    id part = BBHStickerFindTargetPart(chat, message, guid, index, aggregateClass, &range);
                    finish(part, range, part ? nil : @"Native sticker target part is unavailable");
                } @catch (NSException *exception) {
                    (void)exception; finish(nil, NSMakeRange(0, 0), @"Native sticker target lookup failed");
                }
            });
        });
    } @catch (NSException *exception) {
        (void)exception; finish(nil, NSMakeRange(0, 0), @"Native sticker target lookup failed");
    }
}

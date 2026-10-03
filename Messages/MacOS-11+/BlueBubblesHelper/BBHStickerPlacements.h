// Native type-1000 placement construction adapts the pinned imbridge 0009 patch.
// Modified: supplied geometry, target/range checks, private snapshots, exact GUID,
// and ABI guards. See third-party/imbridge-NOTICE and docs/native-stickers.md.
#pragma once
#import "BBHStickerTapbacks.h"
#include <math.h>

@interface NSObject (BBHStickerPlacementInitializer)
- (instancetype)initWithSender:(id)sender time:(id)time text:(id)text messageSubject:(id)messageSubject
             fileTransferGUIDs:(id)transfers flags:(unsigned long long)flags error:(id)error guid:(id)guid
                       subject:(id)subject associatedMessageGUID:(id)association associatedMessageType:(long long)type
        associatedMessageRange:(NSRange)range messageSummaryInfo:(id)summary;
@end

static inline BOOL BBHStickerPlacementValid(id placement) {
    if (![placement isKindOfClass:NSDictionary.class] || [placement count] != 5) return NO;
    for (id key in placement) if (![@[@"x", @"y", @"scale", @"rotation", @"parentWidth"] containsObject:key]) return NO;
    for (NSString *key in @[@"x", @"y", @"scale", @"rotation", @"parentWidth"]) {
        id value = placement[key];
        if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()
            || !isfinite([value doubleValue])) return NO;
    }
    double x = [placement[@"x"] doubleValue], y = [placement[@"y"] doubleValue];
    double scale = [placement[@"scale"] doubleValue], rotation = [placement[@"rotation"] doubleValue];
    double width = [placement[@"parentWidth"] doubleValue];
    // Application limits, not a claim about Apple's accepted geometry domain.
    return x >= -4 && x <= 4 && y >= -4 && y <= 4 && scale >= 0.01 && scale <= 4
        && rotation >= -2 * M_PI && rotation <= 2 * M_PI && width >= 1 && width <= 4096;
}

static inline BOOL BBHStickerPlacementRequestValid(id request) {
    if (![request isKindOfClass:NSDictionary.class]) return NO;
    for (id key in request) if (![@[@"chatGuid", @"selectedMessageGuid", @"partIndex", @"filePath",
                                    @"filename", @"stickerLabel", @"placement"] containsObject:key]) return NO;
    if (!BBHStickerString(request[@"chatGuid"], 1024)
        || !BBHStickerTargetArguments(request[@"selectedMessageGuid"], request[@"partIndex"])
        || !BBHStickerPlacementValid(request[@"placement"])) return NO;
    NSMutableDictionary *asset = [request mutableCopy];
    [asset removeObjectsForKeys:@[@"chatGuid", @"selectedMessageGuid", @"partIndex", @"placement"]];
    return BBHStickerFieldsValid(asset, NO);
}

static inline BOOL BBHStickerPlacementABI(Class chat, Class account, Class center,
                                        Class transfer, Class item, Class message) {
    return BBHStickerTapbackChatABI(chat, account, center, transfer, message)
        && BBHStickerMethod(chat, @"sendMessage:", NO, "v", @[@"@"])
        && BBHStickerMethod(item, @"setBodyData:", NO, "v", @[@"@"])
        && BBHStickerMethod(message, @"_imMessageItem", NO, "@", @[])
        && BBHStickerMethod(message, @"initWithSender:time:text:messageSubject:fileTransferGUIDs:flags:error:guid:subject:associatedMessageGUID:associatedMessageType:associatedMessageRange:messageSummaryInfo:", NO, "@",
            @[@"@", @"@", @"@", @"@", @"@", @(@encode(unsigned long long)), @"@", @"@", @"@", @"@",
              @(@encode(long long)), @(@encode(NSRange)), @"@"]);
}

static inline BOOL BBHStickerPlacementAvailable(void) {
    return BBH_EXPERIMENTAL_STICKERS == 1
        && BBHStickerMethod(NSClassFromString(@"IMChatRegistry"), @"sharedInstance", YES, "@", @[])
        && BBHStickerMethod(NSClassFromString(@"IMChatRegistry"), @"existingChatWithGUID:", NO, "@", @[@"@"])
        && BBHStickerTargetABI(NSClassFromString(@"IMChat"), NSClassFromString(@"IMChatHistoryController"),
            NSClassFromString(@"IMMessage"), NSClassFromString(@"IMMessageItem"), NSClassFromString(@"IMMessagePartChatItem"))
        && BBHStickerMethod(NSClassFromString(@"IMAggregateAttachmentMessagePartChatItem"), @"aggregateAttachmentParts", NO, "@", @[])
        && BBHStickerPlacementABI(NSClassFromString(@"IMChat"), NSClassFromString(@"IMAccount"),
            NSClassFromString(@"IMFileTransferCenter"), NSClassFromString(@"IMFileTransfer"),
            NSClassFromString(@"IMMessageItem"), NSClassFromString(@"IMMessage"));
}

static inline NSString *BBHSendStickerPlacement(id chat, id part, NSRange range, NSDictionary *request,
    NSString *root, id center, Class transferClass, Class itemClass, Class messageClass, NSString **outGUID) {
    if (outGUID) *outGUID = nil;
    if (!BBHStickerPlacementRequestValid(request)) return @"Invalid sticker placement request";
    if (BBH_EXPERIMENTAL_STICKERS != 1) return @"Experimental sticker placement is disabled";
    NSString *snapshot = nil; BOOL registered = NO;
    @try {
        if (!BBHStickerMethod([chat class], @"account", NO, "@", @[])) return @"Native sticker placement is unavailable";
        id account = BBHStickerObject(chat, @"account");
        if (!BBHStickerPlacementABI([chat class], [account class], [center class], transferClass, itemClass, messageClass)
            || !BBHStickerMethod([part class], @"index", NO, @encode(long long), @[])
            || !BBHStickerMethod([part class], @"messagePartRange", NO, @encode(NSRange), @[])
            || BBHStickerInteger(part, @"index") != [request[@"partIndex"] integerValue]
            || !range.length || range.location > NSUIntegerMax - range.length
            || !NSEqualRanges(range, ((NSRange (*)(id, SEL))objc_msgSend)(part, NSSelectorFromString(@"messagePartRange")))
            || !BBHStickerTargetBelongsToChat(chat, request[@"selectedMessageGuid"])
            || ![BBHStickerObject(chat, @"guid") isEqual:request[@"chatGuid"]]) return @"Native sticker placement target is unavailable";
        if (![BBHStickerObject(account, @"serviceName") isEqual:@"iMessage"]) return @"Stickers require a native iMessage chat";
        NSData *data = BBHStickerRead(request[@"filePath"], root);
        NSDictionary *image = BBHStickerImage(data);
        if (!image) return @"Invalid or inaccessible sticker image";
        snapshot = BBHStickerSnapshot(data, request[@"filePath"], image[@"extension"], root);
        if (!snapshot || ![BBHStickerRead(snapshot, root) isEqual:data]) return @"Unable to snapshot sticker image";
        id transfer = BBHStickerPrepareTransfer(center, transferClass, snapshot);
        if (!transfer) return @"Unable to prepare native sticker transfer";
        id transferGUID = BBHStickerObject(transfer, @"guid");
        NSMutableDictionary *info = [BBHStickerStamp(transfer, data, image, snapshot.lastPathComponent, request[@"stickerLabel"]) mutableCopy];
        NSDictionary *geometry = request[@"placement"];
        for (NSString *key in @[@"x", @"y", @"scale", @"rotation", @"parentWidth"]) {
            NSString *nativeKey = @{@"x": @"sxs", @"y": @"sys", @"scale": @"ssa", @"rotation": @"sro", @"parentWidth": @"spw"}[key];
            info[nativeKey] = [NSString stringWithFormat:@"%.17g", [geometry[key] doubleValue]];
        }
        info[@"sir"] = @NO; info[@"spv"] = @0; info[@"sai"] = @"0"; info[@"sli"] = @"0";
        ((void (*)(id, SEL, id))objc_msgSend)(transfer, NSSelectorFromString(@"setStickerUserInfo:"), info);
        NSString *filename = request[@"filename"] ?: [@"sticker." stringByAppendingString:image[@"extension"]];
        NSAttributedString *body = [[NSAttributedString alloc] initWithString:@"\ufffc" attributes:@{
            @"__kIMBaseWritingDirectionAttributeName": @(-1), @"__kIMFileTransferGUIDAttributeName": transferGUID,
            @"__kIMFilenameAttributeName": filename, @"__kIMMessagePartAttributeName": @0}];
        NSString *association = [NSString stringWithFormat:@"p:%ld/%@", (long)[request[@"partIndex"] integerValue], request[@"selectedMessageGuid"]];
        NSString *expectedGUID = NSUUID.UUID.UUIDString;
        id message = [[messageClass alloc] initWithSender:nil time:NSDate.date text:body messageSubject:nil
            fileTransferGUIDs:@[transferGUID] flags:0x5ULL error:nil guid:expectedGUID subject:nil
            associatedMessageGUID:association associatedMessageType:1000 associatedMessageRange:range
            messageSummaryInfo:@{@"eogcd": @3, @"ust": @YES}];
        if (![message isKindOfClass:messageClass] || !BBHStickerMethod([message class], @"guid", NO, "@", @[])
            || !BBHStickerMethod([message class], @"_imMessageItem", NO, "@", @[])
            || ![BBHStickerObject(message, @"guid") isEqual:expectedGUID]) return @"Unable to construct native sticker placement";
        id item = BBHStickerObject(message, @"_imMessageItem");
        if (![item isKindOfClass:itemClass] || !BBHStickerMethod([item class], @"setBodyData:", NO, "v", @[@"@"]))
            return @"Unable to construct native sticker placement";
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSData *bodyData = [NSArchiver archivedDataWithRootObject:body];
#pragma clang diagnostic pop
        if (!bodyData.length) return @"Unable to construct native sticker placement";
        ((void (*)(id, SEL, id))objc_msgSend)(item, NSSelectorFromString(@"setBodyData:"), bodyData);
        if (![BBHStickerObject(message, @"guid") isEqual:expectedGUID]) return @"Unable to construct native sticker placement";
        if (!BBHStickerTargetBelongsToChat(chat, request[@"selectedMessageGuid"])
            || !NSEqualRanges(range, ((NSRange (*)(id, SEL))objc_msgSend)(part, NSSelectorFromString(@"messagePartRange"))))
            return @"Native sticker placement target changed";
        registered = YES;
        ((void (*)(id, SEL, id))objc_msgSend)(center, NSSelectorFromString(@"registerTransferWithDaemon:"), transferGUID);
        ((void (*)(id, SEL, id))objc_msgSend)(chat, NSSelectorFromString(@"sendMessage:"), message);
        id guid = BBHStickerObject(message, @"guid");
        if (![guid isEqual:expectedGUID]) return @"Sticker placement dispatch outcome is unknown; do not retry";
        if (outGUID) *outGUID = [guid copy];
        return nil;
    } @catch (NSException *exception) {
        (void)exception;
        return registered ? @"Sticker placement dispatch outcome is unknown; do not retry" : @"Native sticker placement preparation failed";
    } @finally {
        if (!registered) BBHStickerRemoveSnapshot(snapshot, root);
    }
}

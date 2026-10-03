#import "BBHStickers.h"
#include <assert.h>
#include <stdio.h>

@interface StickerAccount : NSObject
@property NSString *serviceName;
@end
@implementation StickerAccount @end

@interface StickerTransfer : NSObject
@property NSString *guid;
@property NSURL *localURL;
@property bool isSticker;
@property NSDictionary *stickerUserInfo;
@property NSDictionary *attributionInfo;
@end
@implementation StickerTransfer @end

@interface ThrowingStickerTransfer : StickerTransfer @end
@implementation ThrowingStickerTransfer
- (void)setStickerUserInfo:(NSDictionary *)info {
    (void)info; [NSException raise:@"Synthetic" format:@"private sticker metadata"];
}
@end

@interface StickerItem : NSObject
@property NSString *guid;
@property NSData *bodyData;
@property NSAttributedString *body;
@property NSArray<NSString *> *transfers;
@end
@implementation StickerItem
- (instancetype)initWithSender:(id)sender time:(id)time body:(id)body attributes:(id)attributes
             fileTransferGUIDs:(id)transfers flags:(unsigned long long)flags error:(id)error
                          guid:(id)guid threadIdentifier:(id)thread {
    assert(!sender && time && !attributes && [transfers count] >= 1 && [transfers count] <= BBHStickerMaxRowItems
        && flags == 0x100005ULL && !error && !thread);
    self = [super init]; if (self) { self.guid = guid; self.body = body; self.transfers = transfers; } return self;
}
@end

@interface StickerMessage : NSObject
@property NSString *guid;
@property StickerItem *item;
@end
@implementation StickerMessage
+ (id)messageFromIMMessageItem:(StickerItem *)item sender:(id)sender subject:(id)subject {
    assert(!sender && !subject && item.bodyData.length);
    StickerMessage *message = [self new]; message.guid = item.guid; message.item = item; return message;
}
@end

@interface StickerCenter : NSObject
@property StickerTransfer *transfer;
@property NSUInteger allocations;
@property NSUInteger registrations;
@property BOOL throwRegistration;
@property NSUInteger failAllocationAt;
@property NSUInteger failLookupAt;
@property NSUInteger failStampAt;
@property NSUInteger failRegistrationAt;
@property NSUInteger duplicateGUIDAt;
@property NSMutableArray<StickerTransfer *> *transfers;
@property NSMutableArray<NSString *> *registeredGUIDs;
@end
@implementation StickerCenter
+ (id)sharedInstance { return [self new]; }
- (id)guidForNewOutgoingTransferWithLocalURL:(NSURL *)url {
    self.allocations++;
    if (self.allocations == self.failAllocationAt) [NSException raise:@"Synthetic" format:@"private allocation details"];
    self.transfer = self.allocations == self.failStampAt ? [ThrowingStickerTransfer new] : [StickerTransfer new];
    self.transfer.localURL = url;
    self.transfer.guid = self.allocations == self.duplicateGUIDAt ? self.transfers.firstObject.guid
        : [NSString stringWithFormat:@"synthetic-transfer-%lu", (unsigned long)self.allocations];
    if (!self.transfers) self.transfers = [NSMutableArray new];
    [self.transfers addObject:self.transfer]; return self.transfer.guid;
}
- (id)transferForGUID:(id)guid {
    if (self.allocations == self.failLookupAt) return nil;
    assert([guid isEqual:self.transfer.guid]); return self.transfer;
}
- (void)registerTransferWithDaemon:(id)guid {
    BOOL found = NO;
    for (StickerTransfer *transfer in self.transfers) {
        assert(transfer.isSticker && transfer.stickerUserInfo.count && transfer.attributionInfo.count);
        if ([guid isEqual:transfer.guid]) found = YES;
    }
    assert(found);
    self.registrations++;
    if (!self.registeredGUIDs) self.registeredGUIDs = [NSMutableArray new];
    [self.registeredGUIDs addObject:guid];
    if (self.throwRegistration || self.registrations == self.failRegistrationAt)
        [NSException raise:@"Synthetic" format:@"private file path"];
}
@end

@interface StickerChat : NSObject
@property StickerAccount *account;
@property NSString *guid;
@property StickerMessage *message;
@property NSUInteger sends;
@property BOOL throwSend;
@property BOOL changeGUID;
@end
@implementation StickerChat
- (void)sendMessage:(StickerMessage *)message {
    self.sends++; self.message = message;
    if (self.changeGUID) message.guid = @"unexpected-guid";
    if (self.throwSend) [NSException raise:@"Synthetic" format:@"private chat details"];
}
// A shared chat identifier must never supply the result of this operation.
- (id)lastSentMessage { assert(0); return nil; }
@end

@interface StickerRegistry : NSObject @end
@implementation StickerRegistry
+ (id)sharedInstance { return [self new]; }
- (id)existingChatWithGUID:(id)guid { (void)guid; assert(0); return nil; }
@end

@interface WrongStickerTransfer : StickerTransfer @end
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-parameter-types"
@implementation WrongStickerTransfer
- (void)setIsSticker:(long long)value { (void)value; assert(0); }
@end
#pragma clang diagnostic pop

@interface WrongStickerCenter : NSObject @end
@implementation WrongStickerCenter
+ (id)sharedInstance { return [self new]; }
- (id)guidForNewOutgoingTransferWithLocalURL:(id)url { (void)url; assert(0); return nil; }
- (id)transferForGUID:(id)guid { (void)guid; assert(0); return nil; }
- (id)registerTransferWithDaemon:(id)guid { (void)guid; assert(0); return nil; }
@end

@interface NilStickerMessage : StickerMessage @end
@implementation NilStickerMessage
+ (id)messageFromIMMessageItem:(StickerItem *)item sender:(id)sender subject:(id)subject {
    (void)item; (void)sender; (void)subject; return nil;
}
@end

static NSUInteger directConstructionMode, directConstructionCalls;
@interface DirectStickerMessage : NSObject
@property NSString *guid;
@property NSAttributedString *text;
@property NSArray *fileTransferGUIDs;
@property unsigned long long flags;
@property StickerItem *item;
@end
@implementation DirectStickerMessage
- (instancetype)initWithSender:(id)sender time:(id)time text:(id)text
             fileTransferGUIDs:(id)transfers flags:(unsigned long long)flags error:(id)error
                          guid:(id)guid subject:(id)subject threadIdentifier:(id)thread {
    directConstructionCalls++;
    assert(!sender && time && flags == 0x100005ULL && !error && !subject && !thread);
    if (directConstructionMode == 1) return nil;
    if (directConstructionMode == 2) return (id)[NSObject new];
    if (directConstructionMode == 10) [NSException raise:@"Synthetic" format:@"private construction details"];
    if (directConstructionMode == 11) return (id)[NSClassFromString(@"WrongDirectStickerMessage") new];
    self = [super init];
    if (self) {
        self.guid = directConstructionMode == 3 ? @"wrong-guid" : guid;
        self.text = directConstructionMode == 4 ? [[NSAttributedString alloc] initWithString:@"wrong-body"] : text;
        self.fileTransferGUIDs = directConstructionMode == 5 ? [[transfers reverseObjectEnumerator] allObjects] : transfers;
        self.flags = directConstructionMode == 6 ? 0 : flags;
        self.item = directConstructionMode == 7 ? (id)[NSObject new]
            : directConstructionMode == 14 ? nil
            : directConstructionMode == 15 ? [NSClassFromString(@"WrongBodyStickerItem") new] : [StickerItem new];
        if (directConstructionMode != 7) {
            self.item.guid = guid; self.item.transfers = transfers;
            self.item.body = directConstructionMode == 8 ? [[NSAttributedString alloc] initWithString:@"wrong-body"] : text;
            self.item.bodyData = directConstructionMode == 9 ? [NSData data] : [NSArchiver archivedDataWithRootObject:text];
            if (directConstructionMode == 12) self.item.bodyData = [NSMutableData dataWithLength:1024 * 1024 + 1];
            if (directConstructionMode == 13) self.item.bodyData = (id)@"not-data";
        }
    }
    return self;
}
- (id)_imMessageItem { return self.item; }
@end

@interface WrongDirectStickerMessage : DirectStickerMessage @end
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
@implementation WrongDirectStickerMessage
- (double)flags { assert(0); return 0; }
@end
#pragma clang diagnostic pop

@interface WrongBodyStickerItem : StickerItem @end
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-return-types"
@implementation WrongBodyStickerItem
- (double)body { assert(0); return 0; }
@end
#pragma clang diagnostic pop

// A valid direct initializer must not become a retry after legacy construction fails.
static BOOL bothFactoryReturnsNil;
@interface BothStickerMessage : DirectStickerMessage @end
@implementation BothStickerMessage
+ (id)messageFromIMMessageItem:(StickerItem *)item sender:(id)sender subject:(id)subject {
    assert(!sender && !subject && item.bodyData.length);
    if (bothFactoryReturnsNil) return nil;
    BothStickerMessage *message = [self new]; message.guid = item.guid; message.text = item.body;
    message.fileTransferGUIDs = item.transfers; message.flags = 0x100005ULL; message.item = item; return message;
}
@end

static NSData *Image(NSUInteger width, NSUInteger height, NSUInteger count, NSString *type) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    assert(context); CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, 0.5, 0.25, 0.75, 0.5);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGImageRef frame = CGBitmapContextCreateImage(context);
    NSMutableData *data = [NSMutableData new];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,
        (__bridge CFStringRef)type, count, NULL);
    assert(destination);
    if ([type isEqual:@"public.png"] && count > 1) {
        NSDictionary *container = @{(NSString *)kCGImagePropertyPNGDictionary: @{(NSString *)kCGImagePropertyAPNGLoopCount: @2}};
        CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)container);
    }
    NSDictionary *properties = [type isEqual:@"public.png"] && count > 1
        ? @{(NSString *)kCGImagePropertyPNGDictionary: @{(NSString *)kCGImagePropertyAPNGDelayTime: @0.1}}
        : @{(NSString *)kCGImagePropertyGIFDictionary: @{(NSString *)kCGImagePropertyGIFDelayTime: @0.1}};
    for (NSUInteger i = 0; i < count; i++) CGImageDestinationAddImage(destination, frame, (__bridge CFDictionaryRef)properties);
    assert(CGImageDestinationFinalize(destination));
    CFRelease(destination); CGImageRelease(frame); CGContextRelease(context); return data;
}

static void FixtureWrite(NSData *data, NSString *path) {
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    assert(fd >= 0 && write(fd, data.bytes, data.length) == (ssize_t)data.length); assert(!close(fd));
}

static NSData *DeltaGIF(void) {
    NSMutableData *data = [Image(1, 1, 2, @"com.compuserve.gif") mutableCopy];
    unsigned char *bytes = data.mutableBytes;
    assert(data.length > 13);
    bytes[6] = 3; bytes[7] = 0; bytes[8] = 3; bytes[9] = 0;
    NSUInteger cursor = 13 + ((bytes[10] & 0x80) ? 3 * (1U << ((bytes[10] & 7) + 1)) : 0);
    NSUInteger frames = 0;
    while (cursor < data.length && bytes[cursor] != 0x3b) {
        unsigned char marker = bytes[cursor++];
        if (marker == 0x21) {
            cursor++; // Extension label, followed by its data subblocks.
        } else {
            assert(marker == 0x2c && cursor + 9 < data.length);
            if (++frames == 2) { bytes[cursor] = 1; bytes[cursor + 2] = 1; }
            unsigned char packed = bytes[cursor + 8]; cursor += 9;
            if (packed & 0x80) cursor += 3 * (1U << ((packed & 7) + 1));
            cursor++; // LZW minimum code size, followed by image subblocks.
        }
        while (cursor < data.length && bytes[cursor]) {
            NSUInteger size = bytes[cursor++]; cursor += size;
        }
        assert(cursor < data.length); cursor++;
    }
    assert(frames == 2); return data;
}

static NSString *Send(StickerChat *chat, NSDictionary *request, NSString *root,
                      StickerCenter *center, Class message, NSString **guid) {
    return BBHSendSticker(chat, request, root, center, StickerTransfer.class, StickerItem.class, message, guid);
}

static NSArray<NSString *> *Snapshots(NSString *root) {
    NSMutableArray *paths = [NSMutableArray new];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:NULL]) {
        if ([name hasPrefix:@"bbh-sticker-"]) [paths addObject:[root stringByAppendingPathComponent:name]];
    }
    return paths;
}

static NSString *SendRow(StickerChat *chat, NSDictionary *request, NSString *root,
                         StickerCenter *center, Class message, NSString **guid) {
    NSArray<NSString *> *attachmentGUIDs = @[@"stale"];
    NSString *error = BBHSendStickerRow(chat, request, root, center, StickerTransfer.class, StickerItem.class, message, guid, &attachmentGUIDs);
    if (error) assert(!attachmentGUIDs);
    else assert([attachmentGUIDs isEqual:chat.message.item.transfers]);
    return error;
}

int main(void) {
    @autoreleasepool {
        assert(BBHStickerNativeABI(StickerChat.class, StickerAccount.class, StickerCenter.class,
            StickerTransfer.class, StickerItem.class, StickerMessage.class));
        assert(!BBHStickerTransferABI(WrongStickerTransfer.class));
        assert(!BBHStickerNativeABI(StickerChat.class, StickerAccount.class, WrongStickerCenter.class,
            StickerTransfer.class, StickerItem.class, StickerMessage.class));
        assert(!BBHStickerNativeABI(Nil, StickerAccount.class, StickerCenter.class,
            StickerTransfer.class, StickerItem.class, StickerMessage.class));
        assert(BBHStickerDirectConstructionABI(StickerItem.class, DirectStickerMessage.class));
        assert(!BBHStickerLegacyConstructionABI(StickerItem.class, DirectStickerMessage.class));
        assert(BBHStickerNativeABI(StickerChat.class, StickerAccount.class, StickerCenter.class,
            StickerTransfer.class, StickerItem.class, DirectStickerMessage.class));
        assert(!BBHStickerDirectConstructionABI(StickerItem.class, WrongDirectStickerMessage.class));
        assert(!BBHStickerDirectConstructionABI(NSObject.class, DirectStickerMessage.class));
        assert(!BBHStickerSendingAvailable());
        NSDictionary *nativeClasses = @{@"IMChat": StickerChat.class, @"IMAccount": StickerAccount.class,
            @"IMFileTransferCenter": StickerCenter.class, @"IMFileTransfer": StickerTransfer.class,
            @"IMMessageItem": StickerItem.class, @"IMMessage": StickerMessage.class, @"IMChatRegistry": StickerRegistry.class};
        for (NSString *name in nativeClasses) {
            Class cls = objc_allocateClassPair(nativeClasses[name], name.UTF8String, 0);
            assert(cls); objc_registerClassPair(cls);
        }
        assert(BBHStickerSendingAvailable() == (BBH_EXPERIMENTAL_STICKERS == 1));
        NSDictionary *capabilities = BBHHelperCapabilities();
        assert([capabilities[@"stickerSending"] boolValue] == (BBH_EXPERIMENTAL_STICKERS == 1));
        assert([capabilities[@"stickerRows"] boolValue] == (BBH_EXPERIMENTAL_STICKERS == 1));
        for (NSString *key in @[@"stickerReactions", @"stickerPlacement"]) assert(![capabilities[key] boolValue]);

        char templatePath[] = "/private/tmp/bbh-sticker-fixture.XXXXXXXX";
        assert(mkdtemp(templatePath)); NSString *root = [NSString stringWithUTF8String:templatePath];
        NSMutableArray *files = [NSMutableArray new];
        NSData *png = Image(2, 3, 1, @"public.png");
        NSDictionary *metadata = BBHStickerImage(png);
        assert([metadata[@"width"] isEqual:@2] && [metadata[@"height"] isEqual:@3] && [metadata[@"frames"] isEqual:@1]);
        assert(BBHStickerImage(Image(2, 3, 1, @"public.jpeg")));
        assert(BBHStickerImage(Image(2, 3, 2, @"com.compuserve.gif")));
        assert([BBHStickerImage(DeltaGIF())[@"frames"] isEqual:@2]);
        assert([BBHStickerImage(Image(2, 3, 2, @"public.png"))[@"frames"] isEqual:@2]);
        assert(!BBHStickerImage([png subdataWithRange:NSMakeRange(0, png.length - 1)]));
        assert(!BBHStickerImage([@"invalid bytes" dataUsingEncoding:NSUTF8StringEncoding]));
        assert(!BBHStickerImage([NSMutableData dataWithLength:BBHStickerMaxBytes + 1]));
        assert(!BBHStickerImage(Image(619, 1, 1, @"public.png")));
        assert(BBHStickerImage(Image(618, 618, 1, @"public.png")));
        assert(BBHStickerImage(Image(1, 1, 100, @"com.compuserve.gif")));
        assert(!BBHStickerImage(Image(1, 1, 101, @"com.compuserve.gif")));
        assert(!BBHStickerImage(Image(618, 618, 66, @"com.compuserve.gif")));

        NSString *path = [root stringByAppendingPathComponent:@"source.png"];
        FixtureWrite(png, path); [files addObject:path];
        assert([BBHStickerRead(path, root) isEqual:png]);
        assert(!BBHStickerRead(path, [root stringByAppendingString:@"-wrong"]));
        assert(!BBHStickerRead([root stringByAppendingPathComponent:@"../source.png"], root));
        assert(!BBHStickerRead([root stringByAppendingString:@"//source.png"], root));
        assert(!BBHStickerRead([root stringByAppendingString:@"/./source.png"], root));
        assert(!BBHStickerRead([path stringByAppendingString:@"/"], root));
        NSString *symlinkPath = [root stringByAppendingPathComponent:@"leaf-symlink"];
        assert(!symlink(path.fileSystemRepresentation, symlinkPath.fileSystemRepresentation)); [files addObject:symlinkPath];
        assert(!BBHStickerRead(symlinkPath, root));
        NSString *ancestor = [root stringByAppendingPathComponent:@"ancestor-symlink"];
        assert(!symlink(root.fileSystemRepresentation, ancestor.fileSystemRepresentation)); [files addObject:ancestor];
        assert(!BBHStickerRead([ancestor stringByAppendingPathComponent:@"source.png"], root));
        NSString *hardlinkPath = [root stringByAppendingPathComponent:@"hardlink"];
        assert(!link(path.fileSystemRepresentation, hardlinkPath.fileSystemRepresentation));
        assert(!BBHStickerRead(path, root)); assert(!unlink(hardlinkPath.fileSystemRepresentation));
        assert(!chmod(path.fileSystemRepresentation, 0666)); assert(!BBHStickerRead(path, root));
        assert(!chmod(path.fileSystemRepresentation, 0600));
        NSString *fifo = [root stringByAppendingPathComponent:@"fifo"];
        assert(!mkfifo(fifo.fileSystemRepresentation, 0600)); [files addObject:fifo]; assert(!BBHStickerRead(fifo, root));
        NSString *oversized = [root stringByAppendingPathComponent:@"oversized"];
        FixtureWrite([NSMutableData dataWithLength:BBHStickerMaxBytes + 1], oversized); [files addObject:oversized];
        assert(!BBHStickerRead(oversized, root));

        NSDictionary *request = @{@"chatGuid": @"iMessage;+;synthetic", @"filePath": path,
            @"filename": @"chosen.png", @"stickerLabel": @"Synthetic sticker"};
        assert(BBHStickerRequestValid(request));
        for (NSString *key in @[@"selectedMessageGuid", @"partIndex", @"rows", @"effectId", @"reactionType", @"message"]) {
            NSMutableDictionary *invalid = [request mutableCopy]; invalid[key] = @"unsupported";
            assert(!BBHStickerRequestValid(invalid));
        }
        for (id filename in @[@"../bad.png", @"bad\\name.png", @"bad\nname.png", @"", @42, [NSNull null]]) {
            NSMutableDictionary *invalid = [request mutableCopy]; invalid[@"filename"] = filename;
            assert(!BBHStickerRequestValid(invalid));
        }
        StickerChat *chat = [StickerChat new]; chat.guid = request[@"chatGuid"];
        chat.account = [StickerAccount new]; chat.account.serviceName = @"iMessage";
        StickerCenter *center = [StickerCenter new]; NSString *guid = @"stale";
        NSString *error = Send(chat, request, root, center, StickerMessage.class, &guid);
        if (BBH_EXPERIMENTAL_STICKERS == 1) {
            assert(!error && guid.length && [guid isEqual:chat.message.guid] && chat.sends == 1 && center.registrations == 1);
            assert([BBHStickerRead(center.transfer.localURL.path, root) isEqual:png]);
            assert([center.transfer.stickerUserInfo[@"shash"] isEqual:BBHStickerDigest(png, YES)]);
            assert([center.transfer.attributionInfo[@"accessl"] isEqual:request[@"stickerLabel"]]);
            assert([[chat.message.item.body attribute:@"__kIMFilenameAttributeName" atIndex:0 effectiveRange:NULL] isEqual:request[@"filename"]]);
            assert([[chat.message.item.body attribute:@"__kIMEmojiImageAttributeName" atIndex:0 effectiveRange:NULL] isEqual:@1]);
            assert([[chat.message.item.body attribute:@"__kIMBaseWritingDirectionAttributeName" atIndex:0 effectiveRange:NULL] isEqual:@(-1)]);
            BBHStickerRemoveSnapshot(center.transfer.localURL.path, root);
            chat.account.serviceName = @"SMS";
            assert(Send(chat, request, root, center, StickerMessage.class, &guid) && !guid && chat.sends == 1);
            chat.account.serviceName = @"iMessage";
            assert(Send(chat, request, root, center, NilStickerMessage.class, &guid) && !guid && chat.sends == 1);
            assert(![[NSFileManager defaultManager] fileExistsAtPath:center.transfer.localURL.path]);
            chat.throwSend = YES;
            error = Send(chat, request, root, center, StickerMessage.class, &guid);
            assert([error containsString:@"unknown"] && ![error containsString:@"private"] && !guid && chat.sends == 2);
            assert([[NSFileManager defaultManager] fileExistsAtPath:center.transfer.localURL.path]);
            BBHStickerRemoveSnapshot(center.transfer.localURL.path, root);
            chat.throwSend = NO; center.throwRegistration = YES;
            error = Send(chat, request, root, center, StickerMessage.class, &guid);
            assert([error containsString:@"unknown"] && chat.sends == 2 && !guid);
            BBHStickerRemoveSnapshot(center.transfer.localURL.path, root);
            center.throwRegistration = NO; chat.changeGUID = YES;
            error = Send(chat, request, root, center, StickerMessage.class, &guid);
            assert([error containsString:@"unknown"] && chat.sends == 3 && !guid);
            BBHStickerRemoveSnapshot(center.transfer.localURL.path, root);
        } else assert(error && !guid && center.allocations == 0 && chat.sends == 0);
        NSMutableArray *rowItems = [NSMutableArray new];
        for (NSUInteger index = 0; index < 3; index++) [rowItems addObject:@{@"filePath": path,
            @"filename": [NSString stringWithFormat:@"item-%lu.png", (unsigned long)index],
            @"stickerLabel": [NSString stringWithFormat:@"Item %lu", (unsigned long)index]}];
        NSDictionary *row = @{@"chatGuid": chat.guid, @"stickers": rowItems};
        assert(BBHStickerRowRequestValid(row));
        chat.throwSend = NO; chat.changeGUID = NO; chat.sends = 0; directConstructionMode = 0;
        center = [StickerCenter new];
        error = Send(chat, request, root, center, DirectStickerMessage.class, &guid);
        if (BBH_EXPERIMENTAL_STICKERS == 1) {
            assert(!error && guid.length && chat.sends == 1 && center.registrations == 1 && directConstructionCalls == 1);
            assert([[chat.message.item.body attribute:@"__kIMEmojiImageAttributeName" atIndex:0 effectiveRange:NULL] isEqual:@1]);
            for (NSString *snapshot in Snapshots(root)) BBHStickerRemoveSnapshot(snapshot, root);
            center = [StickerCenter new]; chat.sends = 0;
            assert(!SendRow(chat, row, root, center, DirectStickerMessage.class, &guid));
            assert(chat.sends == 1 && center.registrations == 3 && [chat.message.item.transfers isEqual:center.registeredGUIDs]);
            for (NSUInteger index = 0; index < 3; index++) {
                NSAttributedString *body = chat.message.item.body;
                assert([[body attribute:@"__kIMFileTransferGUIDAttributeName" atIndex:index effectiveRange:NULL]
                    isEqual:chat.message.item.transfers[index]]);
                assert([[body attribute:@"__kIMFilenameAttributeName" atIndex:index effectiveRange:NULL] isEqual:rowItems[index][@"filename"]]);
                assert([[body attribute:@"__kIMMessagePartAttributeName" atIndex:index effectiveRange:NULL] isEqual:@0]);
                assert([[body attribute:@"__kIMEmojiImageAttributeName" atIndex:index effectiveRange:NULL] isEqual:@1]);
                assert([[body attribute:@"__kIMBaseWritingDirectionAttributeName" atIndex:index effectiveRange:NULL] isEqual:@(-1)]);
            }
            for (NSString *snapshot in Snapshots(root)) BBHStickerRemoveSnapshot(snapshot, root);
            for (directConstructionMode = 1; directConstructionMode <= 15; directConstructionMode++) {
                center = [StickerCenter new]; chat.sends = 0;
                NSUInteger previousCalls = directConstructionCalls;
                error = SendRow(chat, row, root, center, DirectStickerMessage.class, &guid);
                assert(error && ![error containsString:@"private"] && !guid && center.registrations == 0 && chat.sends == 0);
                assert(directConstructionCalls == previousCalls + 1 && Snapshots(root).count == 0);
            }
            directConstructionMode = 0; center = [StickerCenter new];
            NSUInteger previousCalls = directConstructionCalls;
            assert(!SendRow(chat, row, root, center, BothStickerMessage.class, &guid));
            assert(guid.length && center.registrations == 3 && chat.sends == 1 && directConstructionCalls == previousCalls);
            for (NSString *snapshot in Snapshots(root)) BBHStickerRemoveSnapshot(snapshot, root);
            bothFactoryReturnsNil = YES; center = [StickerCenter new]; chat.sends = 0;
            assert(SendRow(chat, row, root, center, BothStickerMessage.class, &guid));
            assert(!guid && center.registrations == 0 && chat.sends == 0 && directConstructionCalls == previousCalls && Snapshots(root).count == 0);
            center = [StickerCenter new];
            assert(SendRow(chat, row, root, center, WrongDirectStickerMessage.class, &guid));
            assert(!guid && center.allocations == 0 && center.registrations == 0 && directConstructionCalls == previousCalls);
        } else assert(error && !guid && center.allocations == 0 && chat.sends == 0 && directConstructionCalls == 0);
        for (NSUInteger count = 0; count <= 11; count++) {
            NSMutableArray *items = [NSMutableArray new];
            for (NSUInteger i = 0; i < count; i++) [items addObject:rowItems[0]];
            assert(BBHStickerRowRequestValid(@{@"chatGuid": chat.guid, @"stickers": items}) == (count >= 2 && count <= 10));
        }
        for (NSString *key in @[@"selectedMessageGuid", @"targetPartIndex", @"placement", @"message", @"effectId"]) {
            NSMutableDictionary *invalid = [row mutableCopy]; invalid[key] = @"unsupported";
            assert(!BBHStickerRowRequestValid(invalid));
            NSMutableDictionary *badEntry = [rowItems[0] mutableCopy]; badEntry[key] = @"unsupported";
            assert(!BBHStickerRowRequestValid(@{@"chatGuid": chat.guid, @"stickers": @[rowItems[0], badEntry]}));
        }
        assert(!BBHStickerRowRequestValid(@{@"chatGuid": chat.guid, @"stickers": @[@42, rowItems[0]]}));
        chat.throwSend = NO; chat.changeGUID = NO; chat.sends = 0;
        center = [StickerCenter new];
        error = SendRow(chat, row, root, center, StickerMessage.class, &guid);
        if (BBH_EXPERIMENTAL_STICKERS == 1) {
            assert(!error && guid.length && [guid isEqual:chat.message.guid]);
            assert(chat.sends == 1 && center.allocations == 3 && center.registrations == 3);
            assert([chat.message.item.body.string isEqual:@"\ufffc\ufffc\ufffc"]);
            assert([chat.message.item.transfers isEqual:center.registeredGUIDs]);
            for (NSUInteger index = 0; index < 3; index++) {
                NSAttributedString *body = chat.message.item.body;
                assert([[body attribute:@"__kIMFileTransferGUIDAttributeName" atIndex:index effectiveRange:NULL]
                    isEqual:chat.message.item.transfers[index]]);
                assert([[body attribute:@"__kIMFilenameAttributeName" atIndex:index effectiveRange:NULL] isEqual:rowItems[index][@"filename"]]);
                assert([[body attribute:@"__kIMMessagePartAttributeName" atIndex:index effectiveRange:NULL] isEqual:@0]);
                assert([[body attribute:@"__kIMEmojiImageAttributeName" atIndex:index effectiveRange:NULL] isEqual:@1]);
                assert([[body attribute:@"__kIMBaseWritingDirectionAttributeName" atIndex:index effectiveRange:NULL] isEqual:@(-1)]);
                assert([BBHStickerRead(center.transfers[index].localURL.path, root) isEqual:png]);
            }
            for (NSString *snapshot in Snapshots(root)) BBHStickerRemoveSnapshot(snapshot, root);
            for (NSUInteger index = 1; index <= 3; index++) {
                NSMutableArray *badItems = [rowItems mutableCopy];
                badItems[index - 1] = @{@"filePath": oversized};
                center = [StickerCenter new]; chat.sends = 0;
                error = SendRow(chat, @{@"chatGuid": chat.guid, @"stickers": badItems}, root, center, StickerMessage.class, &guid);
                assert(error && !guid && center.allocations == 0 && center.registrations == 0 && chat.sends == 0 && Snapshots(root).count == 0);
                center = [StickerCenter new]; center.failAllocationAt = index;
                error = SendRow(chat, row, root, center, StickerMessage.class, &guid);
                assert(error && ![error containsString:@"private"] && !guid && center.registrations == 0 && chat.sends == 0 && Snapshots(root).count == 0);
                center = [StickerCenter new]; center.failLookupAt = index;
                assert(SendRow(chat, row, root, center, StickerMessage.class, &guid));
                assert(!guid && center.registrations == 0 && chat.sends == 0 && Snapshots(root).count == 0);
                center = [StickerCenter new]; center.failStampAt = index;
                error = SendRow(chat, row, root, center, StickerMessage.class, &guid);
                assert(error && ![error containsString:@"private"] && !guid && center.registrations == 0 && chat.sends == 0 && Snapshots(root).count == 0);
                center = [StickerCenter new]; center.failRegistrationAt = index;
                error = SendRow(chat, row, root, center, StickerMessage.class, &guid);
                assert([error containsString:@"unknown"] && !guid && center.allocations == 3 && center.registrations == index && chat.sends == 0);
                assert(Snapshots(root).count == 3);
                for (NSString *snapshot in Snapshots(root)) BBHStickerRemoveSnapshot(snapshot, root);
            }
            center = [StickerCenter new]; center.duplicateGUIDAt = 2;
            assert(SendRow(chat, row, root, center, StickerMessage.class, &guid));
            assert(!guid && center.registrations == 0 && chat.sends == 0 && Snapshots(root).count == 0);
            NSString *readonlyDirectory = [root stringByAppendingPathComponent:@"readonly"];
            assert(!mkdir(readonlyDirectory.fileSystemRepresentation, 0700));
            NSString *readonlySource = [readonlyDirectory stringByAppendingPathComponent:@"source.png"];
            FixtureWrite(png, readonlySource); assert(!chmod(readonlyDirectory.fileSystemRepresentation, 0500));
            center = [StickerCenter new];
            assert(SendRow(chat, @{@"chatGuid": chat.guid, @"stickers": @[rowItems[0], @{@"filePath": readonlySource}]},
                root, center, StickerMessage.class, &guid));
            assert(!guid && center.allocations == 0 && center.registrations == 0 && chat.sends == 0 && Snapshots(root).count == 0);
            assert(!chmod(readonlyDirectory.fileSystemRepresentation, 0700));
            assert(!unlink(readonlySource.fileSystemRepresentation)); assert(!rmdir(readonlyDirectory.fileSystemRepresentation));
            center = [StickerCenter new];
            assert(SendRow(chat, row, root, center, NilStickerMessage.class, &guid));
            assert(!guid && center.registrations == 0 && chat.sends == 0 && Snapshots(root).count == 0);
            NSMutableArray *ten = [NSMutableArray new];
            for (NSUInteger index = 0; index < 10; index++) [ten addObject:rowItems[0]];
            center = [StickerCenter new];
            assert(!SendRow(chat, @{@"chatGuid": chat.guid, @"stickers": ten}, root, center, StickerMessage.class, &guid));
            assert(guid.length && center.registrations == 10 && chat.sends == 1 && chat.message.item.transfers.count == 10);
            for (NSString *snapshot in Snapshots(root)) BBHStickerRemoveSnapshot(snapshot, root);
            chat.throwSend = YES; chat.sends = 0; center = [StickerCenter new];
            error = SendRow(chat, row, root, center, StickerMessage.class, &guid);
            assert([error containsString:@"unknown"] && !guid && chat.sends == 1 && center.registrations == 3 && Snapshots(root).count == 3);
            for (NSString *snapshot in Snapshots(root)) BBHStickerRemoveSnapshot(snapshot, root);
        } else assert(error && !guid && center.allocations == 0 && center.registrations == 0 && chat.sends == 0 && Snapshots(root).count == 0);
        assert([BBHStickerRead(path, root) isEqual:png]);
        for (NSString *file in files) assert(!unlink(file.fileSystemRepresentation));
        assert(!rmdir(root.fileSystemRepresentation));
        puts("Sticker tests passed: compile-time gate, exact ABI, native service, image bounds, secure reads, byte preservation, one-message row order/part/flags, metadata before registration, nth-item failures, exact GUID, unknown outcomes.");
    }
    return 0;
}

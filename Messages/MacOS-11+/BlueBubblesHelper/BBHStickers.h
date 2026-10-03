// Experimental standalone sticker path. See docs/native-stickers.md and
// third-party/imsg-LICENSE for the pinned imsg source and MIT attribution.
#pragma once
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>
#import "BBHReactions.h"
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <pwd.h>
#include <errno.h>

#ifndef BBH_EXPERIMENTAL_STICKERS
#define BBH_EXPERIMENTAL_STICKERS 0
#endif

enum { BBHStickerMaxBytes = 500 * 1024, BBHStickerMaxDimension = 618,
       BBHStickerMaxFrames = 100, BBHStickerMaxPixels = 25000000 };

@interface NSObject (BBHStickerItemInitializer)
- (instancetype)initWithSender:(id)sender time:(id)time body:(id)body attributes:(id)attributes
             fileTransferGUIDs:(id)transfers flags:(unsigned long long)flags error:(id)error
                          guid:(id)guid threadIdentifier:(id)thread;
@end

static inline BOOL BBHStickerMethod(Class cls, NSString *name, BOOL factory,
                                    const char *result, NSArray *arguments) {
    return cls && BBHReactionClassMethodMatches(cls, NSSelectorFromString(name), factory, result, arguments);
}

static inline BOOL BBHStickerTransferABI(Class cls) {
    return (BBHStickerMethod(cls, @"setIsSticker:", NO, "v", @[@(@encode(bool))])
            || BBHStickerMethod(cls, @"setIsSticker:", NO, "v", @[@(@encode(char))]))
        && BBHStickerMethod(cls, @"setStickerUserInfo:", NO, "v", @[@"@"])
        && BBHStickerMethod(cls, @"setAttributionInfo:", NO, "v", @[@"@"])
        && BBHStickerMethod(cls, @"guid", NO, "@", @[])
        && BBHStickerMethod(cls, @"localURL", NO, "@", @[]);
}

static inline BOOL BBHStickerNativeABI(Class chat, Class account, Class center,
                                      Class transfer, Class item, Class message) {
    return BBHStickerTransferABI(transfer)
        && BBHStickerMethod(chat, @"account", NO, "@", @[])
        && BBHStickerMethod(chat, @"guid", NO, "@", @[])
        && BBHStickerMethod(account, @"serviceName", NO, "@", @[])
        && BBHStickerMethod(chat, @"sendMessage:", NO, "v", @[@"@"])
        && BBHStickerMethod(center, @"sharedInstance", YES, "@", @[])
        && BBHStickerMethod(center, @"guidForNewOutgoingTransferWithLocalURL:", NO, "@", @[@"@"])
        && BBHStickerMethod(center, @"transferForGUID:", NO, "@", @[@"@"])
        && BBHStickerMethod(center, @"registerTransferWithDaemon:", NO, "v", @[@"@"])
        && BBHStickerMethod(item, @"initWithSender:time:body:attributes:fileTransferGUIDs:flags:error:guid:threadIdentifier:", NO,
                             "@", @[@"@", @"@", @"@", @"@", @"@", @(@encode(unsigned long long)), @"@", @"@", @"@"])
        && BBHStickerMethod(item, @"setBodyData:", NO, "v", @[@"@"])
        && BBHStickerMethod(message, @"messageFromIMMessageItem:sender:subject:", YES, "@", @[@"@", @"@", @"@"])
        && BBHStickerMethod(message, @"guid", NO, "@", @[]);
}

static inline BOOL BBHStickerSendingAvailable(void) {
    return BBH_EXPERIMENTAL_STICKERS == 1
        && BBHStickerMethod(NSClassFromString(@"IMChatRegistry"), @"sharedInstance", YES, "@", @[])
        && BBHStickerMethod(NSClassFromString(@"IMChatRegistry"), @"existingChatWithGUID:", NO, "@", @[@"@"])
        && BBHStickerNativeABI(NSClassFromString(@"IMChat"), NSClassFromString(@"IMAccount"),
            NSClassFromString(@"IMFileTransferCenter"), NSClassFromString(@"IMFileTransfer"),
            NSClassFromString(@"IMMessageItem"), NSClassFromString(@"IMMessage"));
}

static inline NSDictionary *BBHHelperCapabilities(void) {
    NSMutableDictionary *capabilities = [BBHReactionCapabilities() mutableCopy];
    capabilities[@"stickerSending"] = @(BBHStickerSendingAvailable());
    capabilities[@"stickerPlacement"] = @NO;
    capabilities[@"stickerRows"] = @NO;
    return capabilities;
}

static inline BOOL BBHStickerString(id value, NSUInteger maximum) {
    return [value isKindOfClass:[NSString class]] && [value length] > 0
        && [value length] <= maximum && [value rangeOfString:@"\0"].location == NSNotFound;
}

static inline BOOL BBHStickerRequestValid(id request) {
    if (![request isKindOfClass:[NSDictionary class]]) return NO;
    NSSet *allowed = [NSSet setWithArray:@[@"chatGuid", @"filePath", @"filename", @"stickerLabel"]];
    for (id key in request) if (![allowed containsObject:key]) return NO;
    if (!BBHStickerString(request[@"chatGuid"], 1024) || !BBHStickerString(request[@"filePath"], 4096)) return NO;
    id filename = request[@"filename"], label = request[@"stickerLabel"];
    if (filename && (!BBHStickerString(filename, 255) || [filename containsString:@"/"]
        || [filename containsString:@"\\"]
        || [filename rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound
        || [filename isEqual:@"."] || [filename isEqual:@".."])) return NO;
    return !label || BBHStickerString(label, 150);
}

static inline NSString *BBHStickerRoot(void) {
    struct passwd *entry = getpwuid(getuid());
    if (!entry || !entry->pw_dir) return nil;
    return [[NSString stringWithUTF8String:entry->pw_dir]
        stringByAppendingPathComponent:@"Library/Messages/Attachments/BlueBubbles"];
}

// Walk every component using descriptors so ancestor and leaf symlinks fail.
// root is injectable only for offline fixtures; the event always uses BBHStickerRoot.
static inline int BBHStickerDirectory(NSString *directory, NSString *root) {
    if (!BBHStickerString(directory, 4096) || !BBHStickerString(root, 4096)
        || !directory.isAbsolutePath || !root.isAbsolutePath
        || ![directory isEqual:directory.stringByStandardizingPath]
        || ![root isEqual:root.stringByStandardizingPath]
        || !([directory isEqual:root] || [directory hasPrefix:[root stringByAppendingString:@"/"]])) return -1;
    int fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    NSString *walked = @"";
    for (NSString *component in directory.pathComponents) {
        if ([component isEqual:@"/"]) continue;
        if ([component isEqual:@"."] || [component isEqual:@".."] || !component.length) { close(fd); return -1; }
        int next = openat(fd, component.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        close(fd); if (next < 0) return -1;
        fd = next;
        walked = [walked stringByAppendingFormat:@"/%@", component];
        struct stat info;
        if (fstat(fd, &info) || !S_ISDIR(info.st_mode)
            || (([walked isEqual:root] || [walked hasPrefix:[root stringByAppendingString:@"/"]])
                && (info.st_uid != getuid() || (info.st_mode & (S_IWGRP | S_IWOTH))))) {
            close(fd); return -1;
        }
    }
    return fd;
}

static inline NSData *BBHStickerRead(NSString *path, NSString *root) {
    if (!BBHStickerString(path, 4096) || ![path isEqual:path.stringByStandardizingPath]) return nil;
    int directory = BBHStickerDirectory(path.stringByDeletingLastPathComponent, root);
    if (directory < 0) return nil;
    int fd = openat(directory, path.lastPathComponent.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    close(directory); if (fd < 0) return nil;
    struct stat before, after;
    if (fstat(fd, &before) || !S_ISREG(before.st_mode) || before.st_uid != getuid()
        || before.st_nlink != 1 || (before.st_mode & (S_IWGRP | S_IWOTH))
        || before.st_size <= 0 || before.st_size > BBHStickerMaxBytes) { close(fd); return nil; }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)before.st_size];
    NSUInteger offset = 0;
    while (offset < data.length) {
        ssize_t count = read(fd, (unsigned char *)data.mutableBytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) { close(fd); return nil; }
        offset += (NSUInteger)count;
    }
    unsigned char extra; ssize_t remaining;
    do { remaining = read(fd, &extra, 1); } while (remaining < 0 && errno == EINTR);
    BOOL unchanged = !fstat(fd, &after) && before.st_dev == after.st_dev && before.st_ino == after.st_ino
        && before.st_size == after.st_size && before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec
        && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec;
    close(fd);
    return remaining == 0 && unchanged ? [data copy] : nil;
}

static inline NSDictionary *BBHStickerImage(NSData *data) {
    if (!data.length || data.length > BBHStickerMaxBytes) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;
    NSString *type = (__bridge NSString *)CGImageSourceGetType(source);
    NSUInteger count = CGImageSourceGetCount(source);
    const unsigned char *bytes = data.bytes;
    static const unsigned char iend[] = {0,0,0,0,0x49,0x45,0x4e,0x44,0xae,0x42,0x60,0x82};
    BOOL png = [type isEqual:@"public.png"], gif = [type isEqual:@"com.compuserve.gif"], jpeg = [type isEqual:@"public.jpeg"];
    BOOL complete = (png && data.length >= sizeof(iend) && !memcmp(bytes + data.length - sizeof(iend), iend, sizeof(iend)))
        || (gif && bytes[data.length - 1] == 0x3b)
        || (jpeg && data.length >= 2 && bytes[data.length - 2] == 0xff && bytes[data.length - 1] == 0xd9);
    BOOL valid = complete && count > 0 && count <= BBHStickerMaxFrames && CGImageSourceGetStatus(source) == kCGImageStatusComplete;
    NSDictionary *container = CFBridgingRelease(CGImageSourceCopyProperties(source, NULL));
    NSNumber *canvasWidth = container[(NSString *)kCGImagePropertyPixelWidth];
    NSNumber *canvasHeight = container[(NSString *)kCGImagePropertyPixelHeight];
    if (canvasWidth || canvasHeight) valid = valid && canvasWidth.unsignedIntegerValue > 0
        && canvasWidth.unsignedIntegerValue <= BBHStickerMaxDimension && canvasHeight.unsignedIntegerValue > 0
        && canvasHeight.unsignedIntegerValue <= BBHStickerMaxDimension;
    NSUInteger width = 0, height = 0; unsigned long long pixels = 0;
    for (NSUInteger index = 0; valid && index < count; index++) {
        NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, index, NULL));
        NSUInteger w = [properties[(NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
        NSUInteger h = [properties[(NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
        valid = w > 0 && h > 0 && w <= BBHStickerMaxDimension && h <= BBHStickerMaxDimension;
        if (!valid) break;
        NSDictionary *options = @{(NSString *)kCGImageSourceShouldCacheImmediately: @YES};
        CGImageRef frame = CGImageSourceCreateImageAtIndex(source, index, (__bridge CFDictionaryRef)options);
        NSUInteger decodedWidth = frame ? CGImageGetWidth(frame) : 0;
        NSUInteger decodedHeight = frame ? CGImageGetHeight(frame) : 0;
        valid = frame && decodedWidth > 0 && decodedWidth <= BBHStickerMaxDimension
            && decodedHeight > 0 && decodedHeight <= BBHStickerMaxDimension
            && CGImageSourceGetStatusAtIndex(source, index) == kCGImageStatusComplete;
        // ImageIO may return a composed GIF canvas instead of the delta frame.
        pixels += MAX((unsigned long long)w * h, (unsigned long long)decodedWidth * decodedHeight);
        if (pixels > BBHStickerMaxPixels) valid = NO;
        if (frame) CGImageRelease(frame);
        if (!index) {
            width = canvasWidth ? canvasWidth.unsignedIntegerValue : MAX(w, decodedWidth);
            height = canvasHeight ? canvasHeight.unsignedIntegerValue : MAX(h, decodedHeight);
        }
    }
    CFRelease(source);
    return valid ? @{@"width": @(width), @"height": @(height), @"frames": @(count),
                     @"extension": png ? @"png" : gif ? @"gif" : @"jpg"} : nil;
}

static inline NSString *BBHStickerDigest(NSData *data, BOOL md5) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; NSUInteger length = md5 ? CC_MD5_DIGEST_LENGTH : CC_SHA256_DIGEST_LENGTH;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (md5) CC_MD5(data.bytes, (CC_LONG)data.length, digest); else CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
#pragma clang diagnostic pop
    NSMutableString *result = [NSMutableString new];
    for (NSUInteger i = 0; i < length; i++) [result appendFormat:@"%02x", digest[i]];
    return result;
}

static inline NSString *BBHStickerSnapshot(NSData *data, NSString *source, NSString *extension, NSString *root) {
    int directory = BBHStickerDirectory(source.stringByDeletingLastPathComponent, root);
    if (directory < 0) return nil;
    NSString *name = [NSString stringWithFormat:@"bbh-sticker-%@.%@", NSUUID.UUID.UUIDString, extension];
    int fd = openat(directory, name.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) { close(directory); return nil; }
    NSUInteger offset = 0;
    while (offset < data.length) {
        ssize_t count = write(fd, (const unsigned char *)data.bytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        offset += (NSUInteger)count;
    }
    BOOL valid = offset == data.length && !fsync(fd);
    if (close(fd)) valid = NO;
    if (!valid) unlinkat(directory, name.fileSystemRepresentation, 0);
    close(directory);
    return valid ? [source.stringByDeletingLastPathComponent stringByAppendingPathComponent:name] : nil;
}

static inline void BBHStickerRemoveSnapshot(NSString *path, NSString *root) {
    if (!path) return;
    int directory = BBHStickerDirectory(path.stringByDeletingLastPathComponent, root);
    if (directory >= 0) { unlinkat(directory, path.lastPathComponent.fileSystemRepresentation, 0); close(directory); }
}

static inline id BBHStickerObject(id object, NSString *name) {
    return ((id (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(name));
}

// This metadata follows imsg's pinned user-generated sticker fixture. Geometry
// stays opaque here; this module never creates a target association or transform.
static inline void BBHStickerStamp(id transfer, NSData *data, NSDictionary *image, NSString *name, NSString *label) {
    NSString *bundle = @"com.apple.messages.MSMessageExtensionBalloonPlugin:0000000000:com.apple.Stickers.UserGenerated.MessagesExtension";
    NSString *cleanLabel = [[label ?: @"Sticker" componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet] componentsJoinedByString:@" "];
    if (!cleanLabel.length) cleanLabel = @"Sticker";
    NSDictionary *info = @{@"pid": bundle, @"safi": @0, @"sai": @"0", @"shash": BBHStickerDigest(data, YES),
        @"sid": name, @"sli": @"0", @"spv": @0, @"spw": @"163.73095703", @"sro": @"0.00000000",
        @"ssa": @"1.00000000", @"stickerEffectType": @(-1),
        @"suri": [@"sticker:///bluebubbles/" stringByAppendingString:BBHStickerDigest(data, NO)],
        @"sxs": @"0.50000000", @"sys": @"0.50000000"};
    NSDictionary *attribution = @{@"accessl": cleanLabel, @"bundle-id": bundle, @"name": @"Stickers",
        @"pgensh": image[@"height"], @"pgensw": image[@"width"],
        @"pgenszc": @{@"gm": @NO, @"iaig": @NO, @"mpw": @"600.000000", @"mth": @"100.000000",
                      @"mtw": @"100.000000", @"s": @"1.000000", @"st": @NO}};
    SEL sticker = NSSelectorFromString(@"setIsSticker:");
    if (BBHStickerMethod([transfer class], @"setIsSticker:", NO, "v", @[@(@encode(bool))]))
        ((void (*)(id, SEL, bool))objc_msgSend)(transfer, sticker, true);
    else ((void (*)(id, SEL, char))objc_msgSend)(transfer, sticker, 1);
    ((void (*)(id, SEL, id))objc_msgSend)(transfer, NSSelectorFromString(@"setStickerUserInfo:"), info);
    ((void (*)(id, SEL, id))objc_msgSend)(transfer, NSSelectorFromString(@"setAttributionInfo:"), attribution);
}

// Returns an exact constructed IMMessage GUID after one dispatch. Any error
// after registration may have an unknown outcome and must never trigger retry.
static inline NSString *BBHSendSticker(id chat, NSDictionary *request, NSString *root,
                                     id center, Class transferClass, Class itemClass, Class messageClass,
                                     NSString **outGUID) {
    if (outGUID) *outGUID = nil;
    if (BBH_EXPERIMENTAL_STICKERS != 1) return @"Experimental sticker sending is disabled";
    if (!BBHStickerRequestValid(request)) return @"Invalid standalone sticker request";
    NSString *snapshot = nil; BOOL registered = NO;
    @try {
        if (!chat || !center || !BBHStickerMethod([chat class], @"account", NO, "@", @[]))
            return @"Native sticker sending is unavailable";
        id account = BBHStickerObject(chat, @"account");
        if (!BBHStickerNativeABI([chat class], [account class], [center class], transferClass, itemClass, messageClass))
            return @"Native sticker sending is unavailable";
        if (![BBHStickerObject(chat, @"guid") isEqual:request[@"chatGuid"]]) return @"Native sticker chat is unavailable";
        id service = BBHStickerObject(account, @"serviceName");
        if (![service isKindOfClass:NSString.class] || ![service isEqual:@"iMessage"])
            return @"Stickers require a native iMessage chat";
        NSData *data = BBHStickerRead(request[@"filePath"], root);
        NSDictionary *image = BBHStickerImage(data);
        if (!image) return @"Invalid or inaccessible sticker image";
        snapshot = BBHStickerSnapshot(data, request[@"filePath"], image[@"extension"], root);
        if (!snapshot || ![BBHStickerRead(snapshot, root) isEqual:data]) {
            BBHStickerRemoveSnapshot(snapshot, root); return @"Unable to snapshot sticker image";
        }
        NSURL *url = [NSURL fileURLWithPath:snapshot];
        id transferGUID = ((id (*)(id, SEL, id))objc_msgSend)(center, NSSelectorFromString(@"guidForNewOutgoingTransferWithLocalURL:"), url);
        id transfer = BBHStickerString(transferGUID, 1024)
            ? ((id (*)(id, SEL, id))objc_msgSend)(center, NSSelectorFromString(@"transferForGUID:"), transferGUID) : nil;
        if (!transfer || ![transfer isKindOfClass:transferClass] || !BBHStickerTransferABI([transfer class])
            || ![BBHStickerObject(transfer, @"guid") isEqual:transferGUID]
            || ![BBHStickerObject(transfer, @"localURL") isEqual:url]) {
            BBHStickerRemoveSnapshot(snapshot, root); return @"Unable to prepare native sticker transfer";
        }
        NSString *filename = request[@"filename"] ?: [@"sticker." stringByAppendingString:image[@"extension"]];
        BBHStickerStamp(transfer, data, image, snapshot.lastPathComponent, request[@"stickerLabel"]);
        NSAttributedString *body = [[NSAttributedString alloc] initWithString:@"\ufffc" attributes:@{
            @"__kIMBaseWritingDirectionAttributeName": @"-1", @"__kIMFileTransferGUIDAttributeName": transferGUID,
            @"__kIMFilenameAttributeName": filename, @"__kIMMessagePartAttributeName": @0}];
        NSString *expectedGUID = NSUUID.UUID.UUIDString;
        id item = [[itemClass alloc] initWithSender:nil time:NSDate.date body:body attributes:nil
            fileTransferGUIDs:@[transferGUID] flags:0x100005ULL error:nil guid:expectedGUID threadIdentifier:nil];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSData *bodyData = [NSArchiver archivedDataWithRootObject:body];
#pragma clang diagnostic pop
        if (!bodyData.length) {
            BBHStickerRemoveSnapshot(snapshot, root); return @"Unable to construct native sticker message";
        }
        if (!item || ![item isKindOfClass:itemClass]
            || !BBHStickerMethod([item class], @"setBodyData:", NO, "v", @[@"@"])) {
            BBHStickerRemoveSnapshot(snapshot, root); return @"Unable to construct native sticker message";
        }
        ((void (*)(id, SEL, id))objc_msgSend)(item, NSSelectorFromString(@"setBodyData:"), bodyData);
        id message = ((id (*)(id, SEL, id, id, id))objc_msgSend)(messageClass,
            NSSelectorFromString(@"messageFromIMMessageItem:sender:subject:"), item, nil, nil);
        if (!message || !BBHStickerMethod([message class], @"guid", NO, "@", @[])
            || ![BBHStickerObject(message, @"guid") isEqual:expectedGUID]) {
            BBHStickerRemoveSnapshot(snapshot, root); return @"Unable to construct native sticker message";
        }
        registered = YES;
        ((void (*)(id, SEL, id))objc_msgSend)(center, NSSelectorFromString(@"registerTransferWithDaemon:"), transferGUID);
        ((void (*)(id, SEL, id))objc_msgSend)(chat, NSSelectorFromString(@"sendMessage:"), message);
        id actualGUID = BBHStickerObject(message, @"guid");
        if (![actualGUID isEqual:expectedGUID]) return @"Sticker dispatch outcome is unknown; do not retry";
        if (outGUID) *outGUID = [actualGUID copy];
        return nil;
    } @catch (NSException *exception) {
        (void)exception;
        if (!registered) BBHStickerRemoveSnapshot(snapshot, root);
        return registered ? @"Sticker dispatch outcome is unknown; do not retry" : @"Native sticker preparation failed";
    }
}

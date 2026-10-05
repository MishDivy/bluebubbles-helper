// Static inline PNG preparation. Originals remain unchanged; only private snapshots use these bytes.
#pragma once
#include <string.h>

@interface NSObject (BBHStickerGlyphInitializer)
- (instancetype)initWithImageContent:(NSData *)data;
@end

static inline BOOL BBHStickerGlyphABI(Class cls) {
    return BBHStickerMethod(cls, @"initWithImageContent:", NO, "@", @[@"@"])
        && BBHStickerMethod(cls, @"contentIdentifier", NO, "@", @[])
        && BBHStickerMethod(cls, @"imageContent", NO, "@", @[]);
}

static inline BOOL BBHStickerGlyphAvailable(void) {
    return BBHStickerGlyphABI(NSClassFromString(@"NSAdaptiveImageGlyph"));
}

static inline BOOL BBHStickerGlyphStaticPNG(NSData *data) {
    const unsigned char *bytes = data.bytes;
    static const unsigned char signature[] = {137, 80, 78, 71, 13, 10, 26, 10};
    if (data.length < 8 || memcmp(bytes, signature, 8)) return NO;
    NSUInteger cursor = 8; BOOL ended = NO;
    while (cursor < data.length) {
        if (data.length - cursor < 12) return NO;
        NSUInteger length = ((NSUInteger)bytes[cursor] << 24) | ((NSUInteger)bytes[cursor + 1] << 16)
            | ((NSUInteger)bytes[cursor + 2] << 8) | bytes[cursor + 3];
        if (length > data.length - cursor - 12) return NO;
        const unsigned char *type = bytes + cursor + 4;
        if (!memcmp(type, "acTL", 4) || !memcmp(type, "fcTL", 4) || !memcmp(type, "fdAT", 4)) return NO;
        cursor += length + 12;
        if (!memcmp(type, "IEND", 4)) { ended = !length && cursor == data.length; break; }
    }
    if (!ended) return NO;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return NO;
    NSDictionary *global = CFBridgingRelease(CGImageSourceCopyProperties(source, NULL));
    NSDictionary *frame = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);
    for (NSDictionary *properties in @[global ?: @{}, frame ?: @{}]) {
        NSDictionary *png = properties[(NSString *)kCGImagePropertyPNGDictionary];
        if (png[(NSString *)kCGImagePropertyAPNGDelayTime] || png[(NSString *)kCGImagePropertyAPNGUnclampedDelayTime]
            || png[(NSString *)kCGImagePropertyAPNGLoopCount]) return NO;
    }
    return YES;
}

typedef struct {
    void *data;
    size_t maximum;
    BOOL exceeded;
} BBHStickerGlyphOutput;

static inline size_t BBHStickerGlyphWrite(void *context, const void *buffer, size_t count) {
    BBHStickerGlyphOutput *output = context;
    NSMutableData *data = (__bridge NSMutableData *)output->data;
    if (output->exceeded || data.length > output->maximum || count > output->maximum - data.length) {
        output->exceeded = YES; return 0;
    }
    [data appendBytes:buffer length:count]; return count;
}

static inline NSData *BBHStickerGlyphPixels(CGImageRef image) {
    size_t width = image ? CGImageGetWidth(image) : 0, height = image ? CGImageGetHeight(image) : 0;
    if (!width || !height || width > BBHStickerMaxDimension || height > BBHStickerMaxDimension) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    if (!space) return nil;
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, width, height, 8, width * 4, space,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context); return data;
}

static inline NSData *BBHStickerGlyphPrepare(NSData *data, Class glyphClass, NSTimeInterval deadline) {
    if (BBH_EXPERIMENTAL_STICKERS != 1 || !data.length || data.length > BBHStickerMaxBytes
        || !BBHStickerGlyphABI(glyphClass) || NSProcessInfo.processInfo.systemUptime >= deadline) return nil;
    CGImageSourceRef source = NULL, reread = NULL;
    CGImageRef image = NULL, decoded = NULL;
    CGMutableImageMetadataRef metadata = NULL;
    CGDataConsumerRef consumer = NULL;
    CGImageDestinationRef destination = NULL;
    NSMutableData *output = [NSMutableData new];
    BBHStickerGlyphOutput bounded = {(__bridge void *)output, BBHStickerMaxBytes, NO};
    @try {
        if (!BBHStickerGlyphStaticPNG(data)) return nil;
        source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        if (!source || !CGImageSourceGetType(source) || !CFEqual(CGImageSourceGetType(source), CFSTR("public.png"))
            || CGImageSourceGetCount(source) != 1 || CGImageSourceGetStatus(source) != kCGImageStatusComplete) return nil;
        NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
        id width = properties[(NSString *)kCGImagePropertyPixelWidth], height = properties[(NSString *)kCGImagePropertyPixelHeight];
        for (id dimension in @[width ?: NSNull.null, height ?: NSNull.null]) {
            if (![dimension isKindOfClass:NSNumber.class] || [dimension integerValue] < 1
                || [dimension integerValue] > BBHStickerMaxDimension || [dimension doubleValue] != [dimension integerValue]) return nil;
        }
        id orientation = properties[(NSString *)kCGImagePropertyOrientation] ?: @1;
        if (![orientation isKindOfClass:NSNumber.class] || [orientation doubleValue] != [orientation integerValue]
            || [orientation integerValue] < 1 || [orientation integerValue] > 8) return nil;
        image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        NSData *before = BBHStickerGlyphPixels(image);
        if (!before || CGImageGetWidth(image) != [width unsignedIntegerValue] || CGImageGetHeight(image) != [height unsignedIntegerValue]
            || CGImageSourceGetStatusAtIndex(source, 0) != kCGImageStatusComplete
            || NSProcessInfo.processInfo.systemUptime >= deadline) return nil;
        NSString *identifier = NSUUID.UUID.UUIDString;
        metadata = CGImageMetadataCreateMutable();
        if (!metadata || !CGImageMetadataSetValueWithPath(metadata, NULL, CFSTR("tiff:DocumentName"),
            (__bridge CFStringRef)identifier)) return nil;
        CGDataConsumerCallbacks callbacks = {BBHStickerGlyphWrite, NULL};
        consumer = CGDataConsumerCreate(&bounded, &callbacks);
        destination = consumer ? CGImageDestinationCreateWithDataConsumer(consumer, CFSTR("public.png"), 1, NULL) : NULL;
        if (!destination) return nil;
        NSDictionary *options = @{(NSString *)kCGImagePropertyOrientation: orientation};
        CGImageDestinationAddImageAndMetadata(destination, image, metadata, (__bridge CFDictionaryRef)options);
        if (!CGImageDestinationFinalize(destination) || bounded.exceeded || !output.length
            || NSProcessInfo.processInfo.systemUptime >= deadline) return nil;
        reread = CGImageSourceCreateWithData((__bridge CFDataRef)output, NULL);
        if (!reread || !CGImageSourceGetType(reread) || !CFEqual(CGImageSourceGetType(reread), CFSTR("public.png"))
            || CGImageSourceGetCount(reread) != 1 || CGImageSourceGetStatus(reread) != kCGImageStatusComplete) return nil;
        NSDictionary *after = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(reread, 0, NULL));
        if (![after[(NSString *)kCGImagePropertyPixelWidth] isEqual:width]
            || ![after[(NSString *)kCGImagePropertyPixelHeight] isEqual:height]) return nil;
        decoded = CGImageSourceCreateImageAtIndex(reread, 0, NULL);
        if (!decoded || CGImageGetWidth(image) != CGImageGetWidth(decoded) || CGImageGetHeight(image) != CGImageGetHeight(decoded)
            || ![(after[(NSString *)kCGImagePropertyOrientation] ?: @1) isEqual:orientation]
            || [properties[(NSString *)kCGImagePropertyHasAlpha] boolValue] != [after[(NSString *)kCGImagePropertyHasAlpha] boolValue]
            || CGImageSourceGetStatusAtIndex(reread, 0) != kCGImageStatusComplete
            || ![before isEqual:BBHStickerGlyphPixels(decoded)] || NSProcessInfo.processInfo.systemUptime >= deadline) return nil;
        NSData *prepared = [output copy];
        id glyph = [[glyphClass alloc] initWithImageContent:prepared];
        if (![glyph isKindOfClass:glyphClass] || !BBHStickerGlyphABI([glyph class])) return nil;
        id actualIdentifier = ((id (*)(id, SEL))objc_msgSend)(glyph, NSSelectorFromString(@"contentIdentifier"));
        id actualData = ((id (*)(id, SEL))objc_msgSend)(glyph, NSSelectorFromString(@"imageContent"));
        return [actualIdentifier isKindOfClass:NSString.class] && [actualIdentifier isEqual:identifier]
            && [actualData isKindOfClass:NSData.class] && [actualData isEqual:prepared]
            && NSProcessInfo.processInfo.systemUptime < deadline ? prepared : nil;
    } @catch (NSException *exception) {
        (void)exception; return nil;
    } @finally {
        if (destination) CFRelease(destination);
        if (consumer) CFRelease(consumer);
        if (metadata) CFRelease(metadata);
        if (decoded) CGImageRelease(decoded);
        if (image) CGImageRelease(image);
        if (reread) CFRelease(reread);
        if (source) CFRelease(source);
    }
}

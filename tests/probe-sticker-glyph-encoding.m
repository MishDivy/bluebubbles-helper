// Generated images only. Public data APIs; no files, UI, transfers, or sends.
// Hypothesis source: https://zenn.dev/noppe/scraps/e08ce9a5a2c355 (first-person experiment).
#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

enum { MaxDimension = 618, MaxBytes = 500 * 1024 };

static void record(const char *name, BOOL value) {
    printf("%s=%s\n", name, value ? "true" : "false");
}

#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 150000
static CGImageRef syntheticImage(size_t width, size_t height, BOOL second) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    if (!space) return NULL;
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return NULL;
    unsigned char *bytes = CGBitmapContextGetData(context);
    for (size_t y = 0; y < height; y++) for (size_t x = 0; x < width; x++) {
        unsigned int alpha = x < width / 4 ? 0 : x >= 3 * width / 4 ? 255
            : (unsigned int)((x - width / 4) * 255 / (width / 2));
        unsigned int red = (unsigned int)(x * 255 / (width - 1));
        unsigned int green = (unsigned int)(y * 255 / (height - 1));
        unsigned int blue = ((x / 16 + y / 12) % 2) ? 211 : 47;
        if (second) { red = 255 - red; green = 255 - green; blue = 255 - blue; }
        size_t offset = (y * width + x) * 4;
        bytes[offset] = (unsigned char)(red * alpha / 255);
        bytes[offset + 1] = (unsigned char)(green * alpha / 255);
        bytes[offset + 2] = (unsigned char)(blue * alpha / 255);
        bytes[offset + 3] = (unsigned char)alpha;
    }
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context); return image;
}

static NSData *pixels(CGImageRef image) {
    size_t width = image ? CGImageGetWidth(image) : 0, height = image ? CGImageGetHeight(image) : 0;
    if (!width || !height || width > MaxDimension || height > MaxDimension) return nil;
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

static BOOL sameAlpha(NSData *left, NSData *right) {
    if (!left.length || left.length != right.length) return NO;
    const unsigned char *a = left.bytes, *b = right.bytes;
    for (NSUInteger index = 3; index < left.length; index += 4) if (a[index] != b[index]) return NO;
    return YES;
}

static BOOL channelError(NSData *left, NSData *right, BOOL alpha, unsigned int *maximum,
                         unsigned long long *sum, NSUInteger *samples) {
    if (!left.length || left.length != right.length) return NO;
    const unsigned char *a = left.bytes, *b = right.bytes;
    for (NSUInteger index = 0; index < left.length; index++) if ((index % 4 == 3) == alpha) {
        unsigned int difference = (unsigned int)abs((int)a[index] - (int)b[index]);
        *maximum = MAX(*maximum, difference); *sum += difference; (*samples)++;
    }
    return YES;
}

static BOOL alphaEndpointMatches(NSData *left, NSData *right, unsigned char endpoint) {
    if (!left.length || left.length != right.length) return NO;
    const unsigned char *a = left.bytes, *b = right.bytes; BOOL found = NO;
    for (NSUInteger index = 3; index < left.length; index += 4) if (a[index] == endpoint) {
        found = YES;
        if (b[index] != endpoint) return NO;
    }
    return found;
}

static size_t boundedWrite(void *context, const void *buffer, size_t count) {
    NSMutableData *data = (__bridge NSMutableData *)context;
    if (data.length > MaxBytes || count > MaxBytes - data.length) return 0;
    [data appendBytes:buffer length:count]; return count;
}

static NSData *encode(CGImageRef image, CGImageRef second, CFStringRef type, NSString *identifier, NSString *description) {
    NSMutableData *data = [NSMutableData new];
    CGDataConsumerCallbacks callbacks = {boundedWrite, NULL};
    CGDataConsumerRef consumer = CGDataConsumerCreate((__bridge void *)data, &callbacks);
    CGImageDestinationRef destination = consumer
        ? CGImageDestinationCreateWithDataConsumer(consumer, type, second ? 2 : 1, NULL) : NULL;
    if (consumer) CFRelease(consumer);
    if (!destination) return nil;
    CGMutableImageMetadataRef metadata = CGImageMetadataCreateMutable();
    BOOL valid = metadata && CGImageMetadataSetValueWithPath(metadata,
        NULL, CFSTR("tiff:DocumentName"), (__bridge CFStringRef)identifier);
    if (valid && description) valid = CGImageMetadataSetValueMatchingImageProperty(metadata,
        kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFImageDescription, (__bridge CFStringRef)description);
    if (valid) {
        if (second) CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)@{
            (NSString *)kCGImagePropertyPNGDictionary: @{(NSString *)kCGImagePropertyAPNGLoopCount: @2}});
        for (NSUInteger index = 0; index < (second ? 2UL : 1UL); index++) {
            NSMutableDictionary *options = [@{(NSString *)kCGImageDestinationLossyCompressionQuality: @1.0,
                (NSString *)kCGImagePropertyOrientation: @1} mutableCopy];
            if (second) options[(NSString *)kCGImagePropertyPNGDictionary] = @{
                (NSString *)kCGImagePropertyAPNGDelayTime: index ? @0.25 : @0.1,
                (NSString *)kCGImagePropertyAPNGUnclampedDelayTime: index ? @0.25 : @0.1};
            CGImageRef frame = index ? second : image;
            if (metadata) CGImageDestinationAddImageAndMetadata(destination, frame, metadata, (__bridge CFDictionaryRef)options);
            else CGImageDestinationAddImage(destination, frame, (__bridge CFDictionaryRef)options);
        }
        valid = CGImageDestinationFinalize(destination);
    }
    if (metadata) CFRelease(metadata);
    CFRelease(destination); return valid && data.length > 0 && data.length <= MaxBytes ? data : nil;
}
#endif

int main(void) {
    @autoreleasepool {
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 150000
        if (@available(macOS 15.0, *)) {
            CGImageRef original = NULL, second = NULL;
            @try {
                const char *names[] = {"own_id_png", "own_id_png_description", "own_id_heic", "own_id_heic_description"};
                BOOL valid = YES, encodedAll = YES;
                for (NSUInteger index = 0; index < 9; index++) {
                    BOOL animated = index == 8, heic = !animated && index % 4 >= 2;
                    size_t width = index < 4 ? 512 : index < 8 ? 384 : 32;
                    size_t height = index < 4 ? 512 : index < 8 ? 256 : 32;
                    printf("synthetic_case=%s\nsource_width=%lu\nsource_height=%lu\n",
                        animated ? "own_id_apng" : names[index % 4], (unsigned long)width, (unsigned long)height);
                    original = syntheticImage(width, height, NO);
                    if (animated) second = syntheticImage(width, height, YES);
                    if (!original || (animated && !second)) { record("synthetic_image_created", NO); return 3; }
                    NSData *originalPixels = pixels(original), *secondPixels = second ? pixels(second) : nil;
                    NSString *identifier = NSUUID.UUID.UUIDString;
                    NSString *description = !animated && index % 2 ? @"Synthetic generated sticker" : nil;
                    record("description_metadata_requested", description != nil);
                    NSData *data = encode(original, animated ? second : NULL,
                        heic ? CFSTR("public.heic") : CFSTR("public.png"), identifier, description);
                    record("encoded_within_limit", data != nil);
                    if (!data) { encodedAll = NO; CGImageRelease(original); original = NULL;
                        if (second) { CGImageRelease(second); second = NULL; } continue; }
                    printf("encoded_bytes=%lu\n", (unsigned long)data.length);
                    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
                    BOOL complete = source && CGImageSourceGetCount(source) == (animated ? 2UL : 1UL)
                        && CGImageSourceGetStatus(source) == kCGImageStatusComplete;
                    BOOL dimensions = complete, orientation = complete, alpha = complete, equal = complete, timing = complete, loop = complete;
                    unsigned int maximumError = 0; unsigned long long totalError = 0; NSUInteger errorSamples = 0;
                    unsigned int maximumAlphaError = 0; unsigned long long totalAlphaError = 0; NSUInteger alphaSamples = 0;
                    BOOL transparent = complete, opaque = complete;
                    for (NSUInteger frame = 0; complete && frame < (animated ? 2UL : 1UL); frame++) {
                        NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, frame, NULL));
                        BOOL declaredDimensions = [properties[(NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue] == width
                            && [properties[(NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue] == height;
                        if (!declaredDimensions) { dimensions = NO; alpha = NO; equal = NO; transparent = NO; opaque = NO; break; }
                        orientation = orientation && [(properties[(NSString *)kCGImagePropertyOrientation] ?: @1) isEqual:@1];
                        CGImageRef decoded = CGImageSourceCreateImageAtIndex(source, frame, NULL);
                        NSData *decodedPixels = pixels(decoded), *expected = frame ? secondPixels : originalPixels;
                        dimensions = dimensions && decodedPixels != nil && CGImageGetWidth(decoded) == width
                            && CGImageGetHeight(decoded) == height && CGImageSourceGetStatusAtIndex(source, frame) == kCGImageStatusComplete;
                        alpha = alpha && sameAlpha(expected, decodedPixels); equal = equal && [expected isEqual:decodedPixels];
                        channelError(expected, decodedPixels, NO, &maximumError, &totalError, &errorSamples);
                        channelError(expected, decodedPixels, YES, &maximumAlphaError, &totalAlphaError, &alphaSamples);
                        transparent = transparent && alphaEndpointMatches(expected, decodedPixels, 0);
                        opaque = opaque && alphaEndpointMatches(expected, decodedPixels, 255);
                        if (animated) {
                            NSDictionary *png = properties[(NSString *)kCGImagePropertyPNGDictionary];
                            NSNumber *delay = png[(NSString *)kCGImagePropertyAPNGUnclampedDelayTime] ?: png[(NSString *)kCGImagePropertyAPNGDelayTime];
                            timing = timing && [delay isKindOfClass:NSNumber.class] && fabs(delay.doubleValue - (frame ? 0.25 : 0.1)) < 0.000001;
                        }
                        if (decoded) CGImageRelease(decoded);
                    }
                    if (animated && complete) {
                        NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyProperties(source, NULL));
                        NSNumber *loops = properties[(NSString *)kCGImagePropertyPNGDictionary][(NSString *)kCGImagePropertyAPNGLoopCount];
                        loop = [loops isKindOfClass:NSNumber.class] && loops.doubleValue == 2;
                    }
                    record("frame_count_match", complete);
                    record("dimensions_match", dimensions); record("orientation_match", orientation); record("alpha_match", alpha);
                    record("decoded_pixels_equal", equal);
                    record("rgb_error_measured", errorSamples > 0);
                    printf("max_rgb_error=%u\nmean_rgb_error=%.9f\n", maximumError,
                        errorSamples ? (double)totalError / errorSamples : 0);
                    record("alpha_error_measured", alphaSamples > 0);
                    printf("max_alpha_error=%u\nmean_alpha_error=%.9f\n", maximumAlphaError,
                        alphaSamples ? (double)totalAlphaError / alphaSamples : 0);
                    record("transparent_alpha_preserved", transparent);
                    record("opaque_alpha_preserved", opaque);
                    if (animated) {
                        record("frame_order_preserved", equal && ![originalPixels isEqual:secondPixels]);
                        record("timing_match", timing); record("loop_match", loop);
                    }
                    if (source) CFRelease(source);
                    NSAdaptiveImageGlyph *glyph = [[NSAdaptiveImageGlyph alloc] initWithImageContent:data];
                    record("glyph_created", glyph != nil);
                    record("identifier_present", glyph.contentIdentifier.length > 0);
                    record("identifier_matches_own", [glyph.contentIdentifier isEqual:identifier]);
                    record("description_present", glyph.contentDescription.length > 0);
                    record("description_matches_own", description && [glyph.contentDescription isEqual:description]);
                    record("content_equals_encoded", [glyph.imageContent isEqual:data]);
                    valid = valid && dimensions && orientation && alpha && errorSamples > 0;
                    if (!heic) valid = valid && equal;
                    if (animated) valid = valid && equal && ![originalPixels isEqual:secondPixels] && timing && loop;
                    valid = valid && glyph && [glyph.contentIdentifier isEqual:identifier] && [glyph.imageContent isEqual:data];
                    CGImageRelease(original); original = NULL;
                    if (second) { CGImageRelease(second); second = NULL; }
                }
                return !encodedAll ? 2 : valid ? 0 : 3;
            } @catch (NSException *exception) {
                (void)exception; record("synthetic_encoding_probe_failed", YES); return 3;
            } @finally {
                if (original) CGImageRelease(original);
                if (second) CGImageRelease(second);
            }
        }
#endif
        record("glyph_api_available", NO); return 2;
    }
}

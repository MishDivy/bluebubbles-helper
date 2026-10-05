// Generated images only. Public data APIs; no files, UI, transfers, or sends.
// Hypothesis source: https://zenn.dev/noppe/scraps/e08ce9a5a2c355 (first-person experiment).
#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
#include <stdio.h>
#include <math.h>

enum { Dimension = 32, MaxBytes = 5 * 1024 * 1024 };

static void record(const char *name, BOOL value) {
    printf("%s=%s\n", name, value ? "true" : "false");
}

#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 150000
static CGImageRef syntheticImage(BOOL second) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, Dimension, Dimension, 8, Dimension * 4, space,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return NULL;
    CGContextClearRect(context, CGRectMake(0, 0, Dimension, Dimension));
    CGContextSetRGBFillColor(context, second ? 0.25 : 0.5, second ? 0.75 : 0.25, second ? 0.5 : 0.75, 0.5);
    CGContextFillRect(context, CGRectMake(0, 0, Dimension / 2, Dimension));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context); return image;
}

static NSData *pixels(CGImageRef image) {
    if (!image || CGImageGetWidth(image) != Dimension || CGImageGetHeight(image) != Dimension) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:Dimension * Dimension * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, Dimension, Dimension, 8, Dimension * 4, space,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextDrawImage(context, CGRectMake(0, 0, Dimension, Dimension), image);
    CGContextRelease(context); return data;
}

static BOOL sameAlpha(NSData *left, NSData *right) {
    if (!left.length || left.length != right.length) return NO;
    const unsigned char *a = left.bytes, *b = right.bytes;
    for (NSUInteger index = 3; index < left.length; index += 4) if (a[index] != b[index]) return NO;
    return YES;
}

static NSData *encode(CGImageRef image, CGImageRef second, CFStringRef type, NSString *identifier) {
    NSMutableData *data = [NSMutableData new];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, type, second ? 2 : 1, NULL);
    if (!destination) return nil;
    CGMutableImageMetadataRef metadata = identifier ? CGImageMetadataCreateMutable() : NULL;
    BOOL valid = !identifier || (metadata && CGImageMetadataSetValueWithPath(metadata,
        NULL, CFSTR("tiff:DocumentName"), (__bridge CFStringRef)identifier));
    if (valid) {
        if (second) CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)@{
            (NSString *)kCGImagePropertyPNGDictionary: @{(NSString *)kCGImagePropertyAPNGLoopCount: @2}});
        for (NSUInteger index = 0; index < (second ? 2UL : 1UL); index++) {
            NSMutableDictionary *options = [@{(NSString *)kCGImageDestinationLossyCompressionQuality: @1.0} mutableCopy];
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
                original = syntheticImage(NO); second = syntheticImage(YES);
                if (!original || !second) { record("synthetic_image_created", NO); return 3; }
                NSData *originalPixels = pixels(original);
                NSData *secondPixels = pixels(second);
                NSString *identifier = NSUUID.UUID.UUIDString;
                const char *names[] = {"png", "plain_heic", "heic_with_own_identifier", "png_with_own_identifier", "apng_with_own_identifier"};
                BOOL valid = YES, encodedAll = YES;
                for (NSUInteger index = 0; index < 5; index++) {
                    printf("synthetic_case=%s\n", names[index]);
                    BOOL animated = index == 4;
                    NSData *data = encode(original, animated ? second : NULL,
                        index == 1 || index == 2 ? CFSTR("public.heic") : CFSTR("public.png"), index >= 2 ? identifier : nil);
                    record("encoded_within_limit", data != nil);
                    if (!data) { encodedAll = NO; continue; }
                    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
                    BOOL complete = source && CGImageSourceGetCount(source) == (animated ? 2UL : 1UL)
                        && CGImageSourceGetStatus(source) == kCGImageStatusComplete;
                    BOOL dimensions = complete, alpha = complete, equal = complete, timing = complete, loop = complete;
                    for (NSUInteger frame = 0; complete && frame < (animated ? 2UL : 1UL); frame++) {
                        CGImageRef decoded = CGImageSourceCreateImageAtIndex(source, frame, NULL);
                        NSData *decodedPixels = pixels(decoded), *expected = frame ? secondPixels : originalPixels;
                        dimensions = dimensions && decodedPixels != nil && CGImageSourceGetStatusAtIndex(source, frame) == kCGImageStatusComplete;
                        alpha = alpha && sameAlpha(expected, decodedPixels); equal = equal && [expected isEqual:decodedPixels];
                        if (animated) {
                            NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, frame, NULL));
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
                    record("dimensions_match", dimensions); record("alpha_match", alpha);
                    record("decoded_pixels_equal", equal);
                    if (animated) {
                        record("frame_order_preserved", equal && ![originalPixels isEqual:secondPixels]);
                        record("timing_match", timing); record("loop_match", loop);
                    }
                    if (source) CFRelease(source);
                    NSAdaptiveImageGlyph *glyph = [[NSAdaptiveImageGlyph alloc] initWithImageContent:data];
                    record("glyph_created", glyph != nil);
                    record("identifier_present", glyph.contentIdentifier.length > 0);
                    record("identifier_matches_own", index >= 2 && [glyph.contentIdentifier isEqual:identifier]);
                    record("description_present", glyph.contentDescription.length > 0);
                    record("content_equals_encoded", [glyph.imageContent isEqual:data]);
                    valid = valid && dimensions && alpha;
                    if (animated) valid = valid && equal && ![originalPixels isEqual:secondPixels] && timing && loop;
                    if (index == 2) valid = valid && glyph && [glyph.contentIdentifier isEqual:identifier] && [glyph.imageContent isEqual:data];
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

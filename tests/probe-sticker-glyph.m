// Public data-object diagnostic only. No private frameworks, UI, transfers, or sends.
#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
#include <stdio.h>
#include <string.h>

enum { MaxBytes = 5 * 1024 * 1024, MaxDimension = 618, MaxFrames = 100, MaxPixels = 25000000 };

static BOOL decodable(NSData *data) {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return NO;
    NSString *type = (__bridge NSString *)CGImageSourceGetType(source);
    size_t count = CGImageSourceGetCount(source), pixels = 0;
    BOOL valid = [@[@"public.png", @"public.heic", @"public.heics", @"public.jpeg", @"com.compuserve.gif"] containsObject:type]
        && count > 0 && count <= MaxFrames && CGImageSourceGetStatus(source) == kCGImageStatusComplete;
    for (size_t index = 0; valid && index < count; index++) {
        NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, index, NULL));
        NSUInteger width = [properties[(NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
        NSUInteger height = [properties[(NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
        valid = width > 0 && height > 0 && width <= MaxDimension && height <= MaxDimension;
        if (!valid) break;
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, index, NULL);
        if (!image) { valid = NO; break; }
        size_t decodedWidth = CGImageGetWidth(image), decodedHeight = CGImageGetHeight(image);
        valid = decodedWidth > 0 && decodedHeight > 0 && decodedWidth <= MaxDimension && decodedHeight <= MaxDimension;
        pixels += decodedWidth * decodedHeight;
        valid = valid && pixels <= MaxPixels && CGImageSourceGetStatusAtIndex(source, index) == kCGImageStatusComplete;
        CGImageRelease(image);
    }
    CFRelease(source); return valid;
}

static BOOL summary(NSData *data) {
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return NO;
    NSString *type = (__bridge NSString *)CGImageSourceGetType(source);
    NSArray *types = @[@"public.png", @"public.heic", @"public.heics", @"public.jpeg", @"com.compuserve.gif"];
    const char *names[] = {"png", "heic", "heics", "jpeg", "gif"};
    NSUInteger format = [types indexOfObject:type];
    size_t count = CGImageSourceGetCount(source);
    NSDictionary *global = CFBridgingRelease(CGImageSourceCopyProperties(source, NULL));
    NSDictionary *first = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    BOOL timing = NO, loop = NO;
    NSArray *dictionaries = @[(NSString *)kCGImagePropertyPNGDictionary, (NSString *)kCGImagePropertyGIFDictionary,
        (NSString *)kCGImagePropertyHEICSDictionary];
    NSArray *delays = @[(NSString *)kCGImagePropertyAPNGDelayTime, (NSString *)kCGImagePropertyGIFDelayTime,
        (NSString *)kCGImagePropertyHEICSDelayTime];
    NSArray *unclamped = @[(NSString *)kCGImagePropertyAPNGUnclampedDelayTime, (NSString *)kCGImagePropertyGIFUnclampedDelayTime,
        (NSString *)kCGImagePropertyHEICSUnclampedDelayTime];
    NSArray *loops = @[(NSString *)kCGImagePropertyAPNGLoopCount, (NSString *)kCGImagePropertyGIFLoopCount,
        (NSString *)kCGImagePropertyHEICSLoopCount];
    for (NSUInteger kind = 0; kind < dictionaries.count; kind++) {
        NSDictionary *container = global[dictionaries[kind]];
        loop = loop || container[loops[kind]] != nil;
        if (kind == 2) timing = timing || container[(NSString *)kCGImagePropertyHEICSFrameInfoArray] != nil;
        for (size_t index = 0; index < count; index++) {
            NSDictionary *frame = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, index, NULL));
            NSDictionary *properties = frame[dictionaries[kind]];
            timing = timing || properties[delays[kind]] != nil || properties[unclamped[kind]] != nil;
            loop = loop || properties[loops[kind]] != nil;
        }
    }
    printf("source_format=%s\nframe_count=%zu\nwidth=%lu\nheight=%lu\ntiming_present=%s\nloop_present=%s\n",
        format == NSNotFound ? "unsupported" : names[format], count,
        (unsigned long)[first[(NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue],
        (unsigned long)[first[(NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue],
        timing ? "true" : "false", loop ? "true" : "false");
    CFRelease(source); return YES;
}

static NSData *syntheticPNG(void) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 32, 32, 8, 32 * 4, space,
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextSetRGBFillColor(context, 0.5, 0.25, 0.75, 0.5);
    CGContextFillRect(context, CGRectMake(0, 0, 16, 32));
    CGImageRef image = CGBitmapContextCreateImage(context);
    NSMutableData *data = [NSMutableData new];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, NULL);
    BOOL valid = image && destination;
    if (valid) { CGImageDestinationAddImage(destination, image, NULL); valid = CGImageDestinationFinalize(destination); }
    if (destination) CFRelease(destination);
    if (image) CGImageRelease(image);
    CGContextRelease(context); return valid ? data : nil;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        @try {
            NSData *data;
            if (argc == 2 && !strcmp(argv[1], "--synthetic")) data = syntheticPNG();
            else if (argc == 1) {
                NSMutableData *input = [NSMutableData new]; unsigned char buffer[8192]; size_t count;
                while ((count = fread(buffer, 1, sizeof(buffer), stdin)) > 0) {
                    if (count > MaxBytes - input.length) { puts("input_within_limit=false"); return 2; }
                    [input appendBytes:buffer length:count];
                }
                if (ferror(stdin)) { puts("input_read=false"); return 2; }
                data = input;
            } else { fputs("Usage: glyph probe [--synthetic], otherwise one image on stdin.\n", stderr); return 2; }
            BOOL decoded = data.length > 0 && data.length <= MaxBytes && decodable(data);
            printf("image_decoded=%s\n", decoded ? "true" : "false");
            if (!decoded) return 3;
            if (!summary(data)) { puts("source_summary_created=false"); return 3; }
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 150000
            if (@available(macOS 15.0, *)) {
                // PNG deliberately tests unsupported input; this is not a converter.
                NSAdaptiveImageGlyph *glyph = [[NSAdaptiveImageGlyph alloc] initWithImageContent:data];
                printf("glyph_created=%s\n", glyph ? "true" : "false");
                printf("identifier_present=%s\n", glyph.contentIdentifier.length ? "true" : "false");
                printf("description_present=%s\n", glyph.contentDescription.length ? "true" : "false");
                printf("image_content_equals_input=%s\n", [glyph.imageContent isEqual:data] ? "true" : "false");
                return 0;
            }
#endif
            puts("glyph_api_available=false"); return 2;
        } @catch (NSException *exception) {
            (void)exception; puts("glyph_probe_failed=true"); return 3;
        }
    }
}

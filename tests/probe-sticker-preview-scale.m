// Synthetic PNG data only. No sticker instances, files, or message objects.
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static NSData *png(NSUInteger width, NSUInteger height, BOOL alpha) {
    if (!width || !height || width > 320 || height > 320) return nil;
    CGColorSpaceRef color = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (!color) return nil;
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, color,
        (CGBitmapInfo)(alpha ? kCGImageAlphaPremultipliedLast : kCGImageAlphaNoneSkipLast));
    CGColorSpaceRelease(color); if (!context) return nil;
    CGContextSetRGBFillColor(context, 0.25, 0.5, 0.75, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    if (alpha) CGContextClearRect(context, CGRectMake(0, 0, width / 2, height));
    CGImageRef image = CGBitmapContextCreateImage(context); CGContextRelease(context);
    if (!image) return nil;
    NSMutableData *data = [NSMutableData new];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, NULL);
    if (!destination) { CGImageRelease(image); return nil; }
    CGImageDestinationAddImage(destination, image, NULL);
    BOOL encoded = CGImageDestinationFinalize(destination); CFRelease(destination); CGImageRelease(image);
    if (!encoded || !data.length || data.length > 1024 * 1024) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    BOOL valid = CGImageSourceGetCount(source) == 1 && CGImageSourceGetStatus(source) == kCGImageStatusComplete
        && [properties[(NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue] == width
        && [properties[(NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue] == height
        && [properties[(NSString *)kCGImagePropertyHasAlpha] boolValue] == alpha;
    CFRelease(source); return valid ? [data copy] : nil;
}

int main(void) {
#if !defined(__arm64__)
    fputs("This synthetic preview-scale probe requires arm64.\n", stderr); return 2;
#endif
    @autoreleasepool {
        if (!dlopen("/System/Library/PrivateFrameworks/IMCore.framework/IMCore", RTLD_NOW)
            || !dlopen("/System/iOSSupport/System/Library/PrivateFrameworks/ChatKit.framework/ChatKit", RTLD_NOW)) {
            fputs("Required framework unavailable.\n", stderr); return 1;
        }
        Class cls = objc_getClass("IMSticker");
        SEL selector = sel_registerName("calculatePreviewScaleWithTargetSize:imageData:");
        Method method = class_getClassMethod(cls, selector);
        if (!method || strcmp(method_getTypeEncoding(method), "d40@0:8{CGSize=dd}16@32") != 0) {
            fputs("Preview-scale ABI differs; no calls performed.\n", stderr); return 2;
        }
        const CGSize sources[] = {{64, 64}, {64, 96}, {96, 64}, {256, 128}};
        const CGSize targets[] = {{24, 24}, {64, 48}, {100, 100}};
        @try {
            for (NSUInteger index = 0; index < sizeof(sources) / sizeof(sources[0]); index++) {
                for (NSUInteger alpha = 0; alpha < 2; alpha++) {
                    NSData *data = png((NSUInteger)sources[index].width, (NSUInteger)sources[index].height, (BOOL)alpha);
                    if (!data) { fputs("Synthetic PNG generation failed.\n", stderr); return 3; }
                    for (NSUInteger target = 0; target < sizeof(targets) / sizeof(targets[0]); target++) {
                        double scale = ((double (*)(id, SEL, CGSize, id))objc_msgSend)(cls, selector, targets[target], data);
                        if (!isfinite(scale)) { fputs("Synthetic preview scale is nonfinite.\n", stderr); return 3; }
                        printf("preview-scale source=(%.0f,%.0f) alpha=%lu target=(%.0f,%.0f) value=%.17g\n",
                            sources[index].width, sources[index].height, (unsigned long)alpha,
                            targets[target].width, targets[target].height, scale);
                    }
                }
            }
        } @catch (NSException *exception) {
            (void)exception; fputs("Synthetic preview-scale calculation failed.\n", stderr); return 3;
        }
        puts("Only 24 generated PNG/target cases used; no sticker instances or files accessed.");
        return 0;
    }
}

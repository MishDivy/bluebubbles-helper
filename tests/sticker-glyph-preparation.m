// Generated public data objects only. No source files, private frameworks, transfers, or sends.
#import <AppKit/AppKit.h>
#import "BBHStickers.h"
#include <assert.h>
#include <stdio.h>

static NSData *PNG(NSUInteger width, NSUInteger height, BOOL alpha, NSUInteger orientation) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
        (CGBitmapInfo)(alpha ? kCGImageAlphaPremultipliedLast : kCGImageAlphaNoneSkipLast));
    CGColorSpaceRelease(space); assert(context);
    CGContextClearRect(context, CGRectMake(0, 0, width, height));
    CGContextSetRGBFillColor(context, 0.5, 0.25, 0.75, alpha ? 0.5 : 1);
    CGContextFillRect(context, CGRectMake(0, 0, alpha ? width / 2 : width, height));
    CGImageRef image = CGBitmapContextCreateImage(context);
    NSMutableData *data = [NSMutableData new];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, NULL);
    assert(image && destination);
    CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)@{(NSString *)kCGImagePropertyOrientation: @(orientation)});
    assert(CGImageDestinationFinalize(destination));
    CFRelease(destination); CGImageRelease(image); CGContextRelease(context); return data;
}

int main(void) {
    @autoreleasepool {
        Class glyphClass = NSClassFromString(@"NSAdaptiveImageGlyph");
        if (!BBHStickerGlyphABI(glyphClass)) {
            puts("SKIP: public glyph data API unavailable; no static preparation acceptance established."); return 0;
        }
        NSMutableSet *identifiers = [NSMutableSet new];
        for (NSArray *size in @[@[@32, @32], @[@31, @24], @[@24, @31], @[@618, @1]]) {
            for (NSNumber *alpha in @[@NO, @YES]) {
                for (NSUInteger orientation = 1; orientation <= 8; orientation++) {
                    NSData *source = PNG([size[0] unsignedIntegerValue], [size[1] unsignedIntegerValue], alpha.boolValue, orientation);
                    NSData *original = [source copy];
                    NSData *prepared = BBHStickerGlyphPrepare(source, glyphClass, NSProcessInfo.processInfo.systemUptime + 5);
                    assert(prepared.length && prepared.length <= BBHStickerMaxBytes && ![prepared isEqual:source] && [source isEqual:original]);
                    NSDictionary *image = BBHStickerImage(prepared);
                    assert([image[@"width"] isEqual:size[0]] && [image[@"height"] isEqual:size[1]] && [image[@"frames"] isEqual:@1]);
                    CGImageSourceRef output = CGImageSourceCreateWithData((__bridge CFDataRef)prepared, NULL);
                    CGImageMetadataRef metadata = CGImageSourceCopyMetadataAtIndex(output, 0, NULL);
                    NSString *identifier = metadata ? CFBridgingRelease(CGImageMetadataCopyStringValueWithPath(metadata, NULL, CFSTR("tiff:DocumentName"))) : nil;
                    assert(identifier.length && ![identifiers containsObject:identifier]); [identifiers addObject:identifier];
                    if (metadata) CFRelease(metadata); CFRelease(output);
                }
            }
        }
        NSData *png = PNG(32, 32, YES, 1);
        assert(!BBHStickerGlyphABI(Nil) && !BBHStickerGlyphABI(NSObject.class));
        assert(!BBHStickerGlyphPrepare(png, NSObject.class, NSProcessInfo.processInfo.systemUptime + 5));
        assert(!BBHStickerGlyphStaticPNG([NSData data]));
        assert(!BBHStickerGlyphStaticPNG([NSData dataWithBytes:"not a PNG" length:9]));
        unsigned char malformed[] = {137,80,78,71,13,10,26,10,255,255,255,255,'I','H','D','R',0,0,0,0};
        NSData *malformedPNG = [NSData dataWithBytes:malformed length:sizeof(malformed)];
        assert(!BBHStickerGlyphStaticPNG(malformedPNG));
        assert(!BBHStickerGlyphPrepare(malformedPNG, glyphClass, NSProcessInfo.processInfo.systemUptime + 5));
        assert(!BBHStickerGlyphPrepare(PNG(619, 1, YES, 1), glyphClass, NSProcessInfo.processInfo.systemUptime + 5));
        assert(!BBHStickerGlyphPrepare(png, glyphClass, NSProcessInfo.processInfo.systemUptime));
        assert(!BBHStickerGlyphPrepare([NSData data], glyphClass, NSProcessInfo.processInfo.systemUptime + 5));
        assert(!BBHStickerGlyphPrepare([NSMutableData dataWithLength:BBHStickerMaxBytes + 1], glyphClass, NSProcessInfo.processInfo.systemUptime + 5));
        // An acTL chunk remains animated input even with a declared frame count of one.
        unsigned char chunk[] = {0,0,0,8,'a','c','T','L',0,0,0,1,0,0,0,2,0,0,0,0};
        uint32_t crc = 0xffffffff;
        for (NSUInteger index = 4; index < 16; index++) {
            crc ^= chunk[index];
            for (NSUInteger bit = 0; bit < 8; bit++) crc = (crc >> 1) ^ ((crc & 1) ? 0xedb88320U : 0);
        }
        crc ^= 0xffffffff;
        for (NSUInteger index = 0; index < 4; index++) chunk[16 + index] = (unsigned char)(crc >> (24 - index * 8));
        NSMutableData *animated = [png mutableCopy];
        [animated replaceBytesInRange:NSMakeRange(33, 0) withBytes:chunk length:sizeof(chunk)];
        assert(!BBHStickerGlyphStaticPNG(animated));
        assert(!BBHStickerGlyphPrepare(animated, glyphClass, NSProcessInfo.processInfo.systemUptime + 5));
        puts("Static glyph preparation passed: own identity, source preservation, dimensions/orientation, opaque/alpha pixels, bounds and animation rejection. No send occurred.");
    }
    return 0;
}

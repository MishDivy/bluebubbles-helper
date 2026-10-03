// Image container metadata only for explicitly selected local fixture files.
// Never prints paths, artwork, descriptions, identifiers, or private transport data.
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#include <stdio.h>

static NSArray *auxiliaryTypes(NSDictionary *properties) {
    id values = properties[(__bridge NSString *)kCGImagePropertyAuxiliaryData];
    if (!values) return @[];
    if (![values isKindOfClass:NSArray.class] || [values count] > 100) return @[@"unsupported structure"];
    NSMutableArray *types = [NSMutableArray array];
    for (id entry in values) {
        id type = [entry isKindOfClass:NSDictionary.class] ? entry[(__bridge NSString *)kCGImagePropertyAuxiliaryDataType] : nil;
        if ([type isKindOfClass:NSString.class] && [type hasPrefix:@"urn:"] && [type length] < 256) [types addObject:type];
        else if ([type isKindOfClass:NSNumber.class]) [types addObject:@{@"numericType": type}];
        else if ([type isKindOfClass:NSString.class] && [type length] < 64)
            [types addObject:@{@"typeName": type}];
        else {
            NSMutableDictionary *fields = [NSMutableDictionary dictionary];
            if ([entry isKindOfClass:NSDictionary.class])
                for (NSString *key in @[@"Width", @"Height", @"Orientation", @"PixelFormat"])
                    if ([entry[key] isKindOfClass:NSNumber.class]) fields[key] = entry[key];
            [types addObject:@{@"unknownType": @YES, @"fields": fields,
                @"keys": [entry isKindOfClass:NSDictionary.class] ? [[entry allKeys] sortedArrayUsingSelector:@selector(compare:)] : @[]}];
        }
    }
    return types;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2 || argc > 11) return 2;
        for (int index = 1; index < argc; ++index) {
            NSString *path = [NSString stringWithUTF8String:argv[index]];
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
            if (![attributes[NSFileType] isEqual:NSFileTypeRegular]
                || [attributes[NSFileSize] unsignedLongLongValue] > 5 * 1024 * 1024) return 3;
            NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
            if (!data.length || data.length > 5 * 1024 * 1024) return 3;
            CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data,
                (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache: @NO});
            if (!source) return 4;
            size_t count = CGImageSourceGetCount(source);
            if (count > 100) { CFRelease(source); return 4; }
            NSString *type = (__bridge NSString *)CGImageSourceGetType(source);
            NSMutableDictionary *summary = [@{@"fixtureIndex": @(index), @"type": type ?: @"unknown",
                @"imageCount": @(count), @"primaryIndex": @(CGImageSourceGetPrimaryImageIndex(source))} mutableCopy];
            NSDictionary *global = CFBridgingRelease(CGImageSourceCopyProperties(source, NULL));
            summary[@"auxiliaryTypes"] = auxiliaryTypes(global);
            id contents = global[(__bridge NSString *)kCGImagePropertyFileContentsDictionary];
            id images = [contents isKindOfClass:NSDictionary.class] ? contents[(__bridge NSString *)kCGImagePropertyImages] : nil;
            NSMutableArray *fileAux = [NSMutableArray array];
            if ([images isKindOfClass:NSArray.class] && [images count] <= 100)
                for (id image in images) if ([image isKindOfClass:NSDictionary.class]) [fileAux addObject:auxiliaryTypes(image)];
            summary[@"fileAuxiliaryTypes"] = fileAux;
            NSMutableArray *alphaProbes = [NSMutableArray array];
            for (NSString *alphaType in @[@"urn:mpeg:hevc:2015:auxid:1", @"urn:mpeg:mpegB:cicp:systems:auxiliary:alpha"]) {
                NSDictionary *aux = CFBridgingRelease(CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, (__bridge CFStringRef)alphaType));
                NSMutableDictionary *probe = [@{@"type": alphaType, @"present": @(aux != nil)} mutableCopy];
                id description = aux[(__bridge NSString *)kCGImageAuxiliaryDataInfoDataDescription];
                if ([description isKindOfClass:NSDictionary.class]) {
                    NSMutableDictionary *numeric = [NSMutableDictionary dictionary];
                    for (NSString *key in @[@"Width", @"Height", @"PixelFormat", @"BytesPerRow"])
                        if ([description[key] isKindOfClass:NSNumber.class]) numeric[key] = description[key];
                    probe[@"description"] = numeric;
                }
                id payload = aux[(__bridge NSString *)kCGImageAuxiliaryDataInfoData];
                if ([payload isKindOfClass:NSData.class]) probe[@"byteCount"] = @([payload length]);
                [alphaProbes addObject:probe];
            }
            summary[@"alphaProbes"] = alphaProbes;
            NSMutableArray *frames = [NSMutableArray array];
            for (size_t frame = 0; frame < count; ++frame) {
                NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, frame, NULL));
                NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                entry[@"auxiliaryTypes"] = auxiliaryTypes(properties);
                for (NSString *key in @[@"PixelWidth", @"PixelHeight", @"Orientation", @"HasAlpha"])
                    if ([properties[key] isKindOfClass:NSNumber.class]) entry[key] = properties[key];
                for (NSString *key in @[@"{HEICS}", @"{PNG}", @"{GIF}"])
                    if ([properties[key] isKindOfClass:NSDictionary.class])
                        entry[key] = [[properties[key] allKeys] sortedArrayUsingSelector:@selector(compare:)];
                [frames addObject:entry];
            }
            summary[@"images"] = frames;
            NSData *output = [NSJSONSerialization dataWithJSONObject:summary options:0 error:nil];
            puts([[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding].UTF8String);
            CFRelease(source);
        }
        return 0;
    }
}

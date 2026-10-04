// Reads one explicitly selected server-staged asset using the helper's validators.
// Does not load IMCore, resolve a chat, prepare a transfer, or send a message.
#import "BBHStickers.h"
#include <stdio.h>

static void stage(const char *name, BOOL value) {
    printf("%s=%s\n", name, value ? "true" : "false");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) {
            fputs("Provide exactly one explicitly selected staged asset path.\n", stderr); return 2;
        }
        @try {
            NSString *root = BBHStickerRoot();
            NSString *path = [NSString stringWithUTF8String:argv[1]];
            BOOL rootValid = BBHStickerAbsolutePath(root);
            stage("root_path_valid", rootValid);
            NSString *directory = path.stringByDeletingLastPathComponent;
            NSString *folder = directory.lastPathComponent;
            BOOL pathValid = rootValid && BBHStickerAbsolutePath(path)
                && [directory.stringByDeletingLastPathComponent isEqual:root]
                && [[NSUUID alloc] initWithUUIDString:folder] != nil
                && BBHStickerFieldsValid(@{@"filePath": path, @"filename": path.lastPathComponent}, NO);
            stage("stage_path_valid", pathValid);
            if (!pathValid) return 2;
            int fd = BBHStickerDirectory(directory, root);
            BOOL directoryValid = fd >= 0;
            if (fd >= 0) close(fd);
            stage("directory_pass", directoryValid);
            NSData *data = directoryValid ? BBHStickerRead(path, root) : nil;
            stage("read_pass", data != nil);
            NSDictionary *image = data ? BBHStickerImage(data) : nil;
            stage("image_pass", image != nil);
            if (!image) return 3;
            NSString *extension = image[@"extension"];
            const char *format = [extension isEqual:@"png"] ? "PNG" : [extension isEqual:@"gif"] ? "GIF" : "JPEG";
            printf("format=%s width=%lu height=%lu frames=%lu\n", format,
                (unsigned long)[image[@"width"] unsignedIntegerValue],
                (unsigned long)[image[@"height"] unsignedIntegerValue],
                (unsigned long)[image[@"frames"] unsignedIntegerValue]);
            return 0;
        } @catch (NSException *exception) {
            (void)exception; fputs("Staged asset validation raised an exception.\n", stderr); return 3;
        }
    }
}

// The sandbox applies only to a disposable child and its synthetic fixture paths.
#import "BBHStickers.h"
#include <sandbox.h>
#include <sys/wait.h>
#include <assert.h>
#include <stdio.h>

static int CheckSandbox(NSString *container) {
    NSString *ancestor = [container stringByAppendingPathComponent:@"ancestor"];
    NSString *root = [ancestor stringByAppendingPathComponent:@"staging"];
    NSString *source = [root stringByAppendingPathComponent:@"source.png"];
    NSString *profile = [NSString stringWithFormat:@"(version 1)(allow default)(deny file-read-data(literal \"%@\"))", ancestor];
    char *error = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    int status = sandbox_init(profile.UTF8String, 0, &error);
    if (error) sandbox_free_error(error);
#pragma clang diagnostic pop
    if (status) { fputs("Synthetic sandbox setup failed.\n", stderr); return 2; }
    int legacy = open(ancestor.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    int legacyError = errno;
    if (legacy >= 0) close(legacy);
    assert(legacy < 0 && (legacyError == EPERM || legacyError == EACCES));
    NSData *bytes = [@"synthetic sticker bytes" dataUsingEncoding:NSUTF8StringEncoding];
    assert([BBHStickerRead(source, root) isEqual:bytes]);
    assert(!BBHStickerRead([root stringByAppendingPathComponent:@"leaf-symlink"], root));
    NSString *aliasRoot = [[container stringByAppendingPathComponent:@"ancestor-symlink"] stringByAppendingPathComponent:@"staging"];
    assert(!BBHStickerRead([aliasRoot stringByAppendingPathComponent:@"source.png"], aliasRoot));
    assert(!BBHStickerRead([root stringByAppendingPathComponent:@"writable/source.png"], root));
    assert(!BBHStickerRead([root stringByAppendingPathComponent:@"writable-file.png"], root));
    struct stat parent;
    assert(!stat("/private/tmp", &parent));
    if (parent.st_uid != getuid()) assert(!BBHStickerRead(source, @"/private/tmp"));
    else puts("Mismatched-root-owner assertion skipped: temporary root is owned by test runner.");
    NSString *snapshot = BBHStickerSnapshot(bytes, source, @"png", root);
    assert(snapshot && [BBHStickerRead(snapshot, root) isEqual:bytes]);
    BBHStickerRemoveSnapshot(snapshot, root);
    assert(access(snapshot.fileSystemRepresentation, F_OK) < 0 && errno == ENOENT);
    return 0;
}

static void Fixture(NSString *path, mode_t mode) {
    const char bytes[] = "synthetic sticker bytes";
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode);
    assert(fd >= 0 && write(fd, bytes, sizeof(bytes) - 1) == (ssize_t)sizeof(bytes) - 1);
    assert(!close(fd));
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 3 && !strcmp(argv[1], "--sandbox")) return CheckSandbox([NSString stringWithUTF8String:argv[2]]);
        assert(argc == 1);
        BOOL searchAvailable = NO;
#ifdef O_SEARCH
        if (@available(macOS 13.0, *)) searchAvailable = YES;
#endif
        if (searchAvailable) {
            char templatePath[] = "/private/tmp/bbh-sticker-sandbox.XXXXXXXX";
            assert(mkdtemp(templatePath)); NSString *container = [NSString stringWithUTF8String:templatePath];
            NSString *ancestor = [container stringByAppendingPathComponent:@"ancestor"];
            NSString *root = [ancestor stringByAppendingPathComponent:@"staging"];
            NSString *writable = [root stringByAppendingPathComponent:@"writable"];
            for (NSString *directory in @[ancestor, root, writable]) assert(!mkdir(directory.fileSystemRepresentation, 0700));
            NSString *source = [root stringByAppendingPathComponent:@"source.png"];
            NSString *writableSource = [writable stringByAppendingPathComponent:@"source.png"];
            NSString *writableFile = [root stringByAppendingPathComponent:@"writable-file.png"];
            for (NSString *path in @[source, writableSource, writableFile]) Fixture(path, 0600);
            assert(!chmod(writable.fileSystemRepresentation, 0777)); assert(!chmod(writableFile.fileSystemRepresentation, 0666));
            NSString *leafLink = [root stringByAppendingPathComponent:@"leaf-symlink"];
            NSString *ancestorLink = [container stringByAppendingPathComponent:@"ancestor-symlink"];
            assert(!symlink(source.fileSystemRepresentation, leafLink.fileSystemRepresentation));
            assert(!symlink(ancestor.fileSystemRepresentation, ancestorLink.fileSystemRepresentation));
            // Prepare all Objective-C values before fork; the child immediately execs.
            const char *argument = container.fileSystemRepresentation;
            pid_t child = fork(); assert(child >= 0);
            if (!child) { execl(argv[0], argv[0], "--sandbox", argument, (char *)NULL); _exit(127); }
            int status; assert(waitpid(child, &status, 0) == child);
            for (NSString *path in @[source, writableSource, writableFile, leafLink, ancestorLink]) assert(!unlink(path.fileSystemRepresentation));
            for (NSString *directory in @[writable, root, ancestor, container]) assert(!rmdir(directory.fileSystemRepresentation));
            assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
            puts("Sticker sandbox regression passed: denied ancestor read, bounded leaf read/snapshot, symlink and ownership/permission guards.");
            return 0;
        }
        puts("Sticker sandbox search-only regression skipped: requires macOS 13+ and O_SEARCH SDK support.");
        return 0;
    }
}

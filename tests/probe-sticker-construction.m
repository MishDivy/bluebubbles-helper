// Constructs synthetic messages only. Never resolves a chat or registers a transfer.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

@interface NSObject (StickerConstructionProbe)
- (instancetype)initWithSender:(id)sender time:(id)time text:(id)text
             fileTransferGUIDs:(id)transfers flags:(unsigned long long)flags error:(id)error
                          guid:(id)guid subject:(id)subject threadIdentifier:(id)thread;
@end

static BOOL matches(Class cls, const char *selector, const char *encoding) {
    Method method = cls ? class_getInstanceMethod(cls, sel_registerName(selector)) : NULL;
    return method && strcmp(method_getTypeEncoding(method), encoding) == 0;
}

static id object(id instance, const char *selector) {
    return ((id (*)(id, SEL))objc_msgSend)(instance, sel_registerName(selector));
}

static int failed(const char *phase) {
    fprintf(stderr, "Synthetic construction check failed: %s.\n", phase); return 3;
}

static void record(const char *name, BOOL value) {
    printf("%s=%s\n", name, value ? "true" : "false");
}

static BOOL requiredBody(id value, NSAttributedString *body) {
    if (![value isKindOfClass:NSAttributedString.class] || ![[value string] isEqual:body.string]) return NO;
    for (NSUInteger index = 0; index < body.length; index++) {
        for (NSString *key in @[@"__kIMFileTransferGUIDAttributeName", @"__kIMFilenameAttributeName",
            @"__kIMMessagePartAttributeName", @"__kIMEmojiImageAttributeName", @"__kIMBaseWritingDirectionAttributeName"]) {
            id actual = [value attribute:key atIndex:index effectiveRange:NULL];
            id expected = [body attribute:key atIndex:index effectiveRange:NULL];
            if (actual != expected && ![actual isEqual:expected]) return NO;
        }
    }
    return YES;
}

static BOOL archiveMatches(id value, NSAttributedString *body, BOOL requiredOnly) {
    if (![value isKindOfClass:NSData.class] || ![value length] || [value length] > 1024 * 1024) return NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    id decoded = [NSUnarchiver unarchiveObjectWithData:value];
#pragma clang diagnostic pop
    return requiredOnly ? requiredBody(decoded, body) : [decoded isEqual:body];
}

int main(void) {
    @autoreleasepool {
#if !defined(__arm64__)
        fputs("Construction probe requires arm64; no message constructed.\n", stderr); return 2;
#endif
        if (!dlopen("/System/Library/PrivateFrameworks/IMCore.framework/IMCore", RTLD_NOW)) return 1;
        Class messageClass = objc_getClass("IMMessage"), itemClass = objc_getClass("IMMessageItem");
        const char *initializer = "initWithSender:time:text:fileTransferGUIDs:flags:error:guid:subject:threadIdentifier:";
        if (!matches(messageClass, initializer, "@88@0:8@16@24@32@40Q48@56@64@72@80")
            || !matches(messageClass, "guid", "@16@0:8")
            || !matches(messageClass, "text", "@16@0:8")
            || !matches(messageClass, "fileTransferGUIDs", "@16@0:8")
            || !matches(messageClass, "flags", "Q16@0:8")
            || !matches(messageClass, "_imMessageItem", "@16@0:8")
            || !matches(itemClass, "body", "@16@0:8")
            || !matches(itemClass, "bodyData", "@16@0:8")) {
            fputs("Construction ABI differs; no message constructed.\n", stderr); return 2;
        }
        const char *phase = "synthetic body";
        @try {
            for (NSUInteger sample = 0; sample < 3; sample++) {
                NSUInteger count = sample == 0 ? 1 : 2;
                puts(sample == 0 ? "Synthetic standalone:" : sample == 1 ? "Synthetic row:" : "Synthetic composition:");
                NSMutableArray *transfers = [NSMutableArray new];
                NSString *text = sample == 2 ? @"prefix\ufffc\nsuffix\ufffc" : @"";
                NSMutableAttributedString *body = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
                    @"__kIMMessagePartAttributeName": @0, @"__kIMBaseWritingDirectionAttributeName": @(-1)}];
                NSUInteger marker = 0;
                for (NSUInteger index = 0; index < count; index++) {
                    NSString *transfer = [NSString stringWithFormat:@"synthetic-nonexistent-transfer-%lu", (unsigned long)index];
                    [transfers addObject:transfer];
                    NSMutableDictionary *attributes = [@{
                        @"__kIMFileTransferGUIDAttributeName": transfer,
                        @"__kIMMessagePartAttributeName": @0, @"__kIMEmojiImageAttributeName": @1,
                        @"__kIMBaseWritingDirectionAttributeName": @(-1)} mutableCopy];
                    if (sample == 0) attributes[@"__kIMFilenameAttributeName"] = @"synthetic.png";
                    if (sample == 2) {
                        NSRange range = [text rangeOfString:@"\ufffc" options:0 range:NSMakeRange(marker, text.length - marker)];
                        [body addAttributes:attributes range:range]; marker = NSMaxRange(range);
                    } else [body appendAttributedString:[[NSAttributedString alloc] initWithString:@"\ufffc" attributes:attributes]];
                }
                NSString *guid = NSUUID.UUID.UUIDString;
                phase = "constructor invocation";
                id message = [[messageClass alloc] initWithSender:nil time:NSDate.date text:body
                    fileTransferGUIDs:transfers flags:0x100005ULL error:nil guid:guid subject:nil threadIdentifier:nil];
                if (![message isKindOfClass:messageClass]) return failed("message class");
                phase = "message getters";
                if (![object(message, "guid") isEqual:guid]) return failed("message GUID");
                if (![object(message, "text") isEqual:body]) return failed("message attributed text");
                if (![object(message, "fileTransferGUIDs") isEqual:transfers]) return failed("ordered message transfers");
                if (((unsigned long long (*)(id, SEL))objc_msgSend)(message, sel_registerName("flags")) != 0x100005ULL)
                    return failed("message flags");
                phase = "message item getter";
                id item = object(message, "_imMessageItem");
                if (![item isKindOfClass:itemClass]) return failed("item class");
                if (!matches([item class], "body", "@16@0:8")
                    || !matches([item class], "bodyData", "@16@0:8")) return failed("actual item body ABI");
                phase = "initial item archive inspection";
                id initialArchive = object(item, "bodyData");
                record("initial_item_body_exact", [object(item, "body") isEqual:body]);
                record("initial_item_body_required_runs", requiredBody(object(item, "body"), body));
                record("initial_archive_nonempty", [initialArchive isKindOfClass:NSData.class] && [initialArchive length] > 0);
                record("initial_archive_decodes_exact", archiveMatches(initialArchive, body, NO));
                record("initial_archive_decodes_required_runs", archiveMatches(initialArchive, body, YES));
                if (![object(item, "body") isEqual:body] || !archiveMatches(initialArchive, body, NO))
                    return failed("initial item body semantics");
                phase = "reread item getters";
                id current = object(message, "_imMessageItem");
                if (![current isKindOfClass:itemClass]) return failed("reread item class");
                if (!matches([current class], "body", "@16@0:8")
                    || !matches([current class], "bodyData", "@16@0:8")) return failed("reread item body ABI");
                id currentArchive = object(current, "bodyData");
                record("same_item_object", current == item);
                record("reread_archive_bytes_match", [currentArchive isEqual:initialArchive]);
                record("reread_archive_nonempty", [currentArchive isKindOfClass:NSData.class] && [currentArchive length] > 0);
                record("reread_archive_decodes_exact", archiveMatches(currentArchive, body, NO));
                record("reread_archive_decodes_required_runs", archiveMatches(currentArchive, body, YES));
                record("reread_body_required_runs", requiredBody(object(current, "body"), body));
                if (!archiveMatches(currentArchive, body, NO)) return failed("reread archived item body semantics");
                if (![object(current, "body") isEqual:body]) return failed("reread attributed item body");
                if (![object(message, "guid") isEqual:guid]) return failed("reread message GUID");
            }
        } @catch (NSException *exception) {
            (void)exception; return failed(phase);
        }
        puts("Synthetic standalone, row and composition construction passed. No chat, account, or transfer was queried or registered; no send occurred.");
        return 0;
    }
}

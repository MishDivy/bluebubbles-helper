// Class metadata only. No instances, private-method calls, file transfers, or messages.
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

enum { MaxBytes = 32768, MaxLines = 128 };
static unsigned int outputBytes, outputLines;
static BOOL capped;

static void emit(const char *format, ...) {
    char line[1024];
    va_list arguments; va_start(arguments, format);
    int length = vsnprintf(line, sizeof(line), format, arguments); va_end(arguments);
    if (length < 0 || (size_t)length >= sizeof(line) || outputLines >= MaxLines - 1
        || (unsigned int)length > MaxBytes - 128 - outputBytes) { capped = YES; return; }
    fwrite(line, 1, (size_t)length, stdout);
    outputBytes += (unsigned int)length; outputLines++;
}

int main(void) {
    if (!dlopen("/System/Library/PrivateFrameworks/IMCore.framework/IMCore", RTLD_NOW)
        || !dlopen("/System/iOSSupport/System/Library/PrivateFrameworks/ChatKit.framework/ChatKit", RTLD_NOW)) {
        fputs("Required framework unavailable.\n", stderr); return 1;
    }
    // Exact lookups also report inherited selectors and explicit absences.
    const struct { const char *className; const char *selector; } exact[] = {
        {"IMFileTransfer", "previewGenerationState"}, {"IMFileTransfer", "setPreviewGenerationState:"},
        {"IMFileTransfer", "previewGenerationVersion"}, {"IMFileTransfer", "setPreviewGenerationVersion:"},
        {"IMFileTransfer", "emojiImageContentIdentifier"}, {"IMFileTransfer", "setEmojiImageContentIdentifier:"},
        {"IMFileTransfer", "emojiImageShortDescription"}, {"IMFileTransfer", "setEmojiImageShortDescription:"},
        {"IMFileTransfer", "isSticker"}, {"IMFileTransfer", "hideAttachment"},
        {"IMFileTransfer", "mimeType"}, {"IMFileTransfer", "transferState"},
        {"IMFileTransferCenter", "guidForNewOutgoingTransferWithLocalURL:"},
        {"IMFileTransferCenter", "transferForGUID:"},
        {"IMFileTransferCenter", "registerTransferWithDaemon:"},
        {"IMFileTransferCenter", "retargetTransfer:toPath:"},
        {"IMFileTransferCenter", "allFileTransfersAreInPreviewPreflightStage:"},
        {"IMFileTransferCenter", "setPreviewGeneratedPostAcquisitionForTransfer:value:"},
        {"IMMessage", "flags"}, {"IMMessage", "fileTransferGUIDs"},
        {"IMMessage", "hasInlineAttachments"}, {"IMMessage", "inlineAttachmentAttributesArray"},
        {"IMMessageItem", "flags"}, {"IMMessageItem", "_newChatItems"},
        {"IMAggregateAttachmentMessagePartChatItem", "aggregateAttachmentParts"}
    };
    for (size_t index = 0; index < sizeof(exact) / sizeof(exact[0]); index++) {
        Class cls = objc_getClass(exact[index].className);
        Method method = cls ? class_getInstanceMethod(cls, sel_registerName(exact[index].selector)) : NULL;
        const char *encoding = method ? method_getTypeEncoding(method) : "absent";
        if (!encoding || strnlen(encoding, 513) > 512) { capped = YES; continue; }
        emit("Exact %s -%s ABI=%s\n", exact[index].className, exact[index].selector, encoding);
    }
    const char *classes[] = {"IMFileTransfer", "IMFileTransferCenter", "IMMessage", "IMMessageItem", "IMStickerMessagePartChatItem",
                             "CKStickerMessagePartChatItem", "IMAggregateAttachmentMessagePartChatItem"};
    for (size_t index = 0; index < sizeof(classes) / sizeof(classes[0]); index++) {
        Class cls = objc_getClass(classes[index]);
        emit("Class %s: %s\n", classes[index], cls ? "present" : "absent");
        if (!cls) continue;
        Class superclass = class_getSuperclass(cls);
        const char *superName = superclass ? class_getName(superclass) : "none";
        if (superName && strnlen(superName, 257) <= 256) emit("Superclass %s: %s\n", classes[index], superName);
        else capped = YES;
    }
    fputs(capped ? "Row lifecycle metadata inventory capped; no methods invoked.\n"
                 : "Row lifecycle metadata inventory complete; no methods invoked.\n", stdout);
    return capped ? 2 : 0;
}

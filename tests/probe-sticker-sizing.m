// Class metadata only. No objects, private-method calls, or message access.
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <ctype.h>

enum { MaxBytes = 32768, MaxLines = 128, MaxMethods = 100, MaxScannedMethods = 4096 };
static unsigned int outputBytes, outputLines, methodRows;
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

static BOOL contains(const char *name, const char *token) {
    size_t length = strlen(token);
    for (const char *start = name; *start; start++) {
        size_t index = 0;
        while (index < length && start[index]
            && tolower((unsigned char)start[index]) == token[index]) index++;
        if (index == length) return YES;
    }
    return NO;
}

static BOOL relevant(const char *name) {
    const char *tokens[] = {"size", "scale", "layout", "geometry", "image", "dimension",
                            "frame", "bounds", "aspect", "intrinsic", "preview"};
    for (size_t index = 0; index < sizeof(tokens) / sizeof(tokens[0]); index++)
        if (contains(name, tokens[index])) return YES;
    return NO;
}

static int compareMethods(const void *left, const void *right) {
    return strcmp(sel_getName(method_getName(*(const Method *)left)),
                  sel_getName(method_getName(*(const Method *)right)));
}

static void inventory(Class cls, const char *name, BOOL factory) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(factory ? object_getClass(cls) : cls, &count);
    if (count > MaxScannedMethods) { emit("%s %c inventory exceeds scan limit\n", name, factory ? '+' : '-'); capped = YES; free(methods); return; }
    if (count) qsort(methods, count, sizeof(Method), compareMethods);
    for (unsigned int index = 0; index < count; index++) {
        const char *selector = sel_getName(method_getName(methods[index]));
        const char *encoding = method_getTypeEncoding(methods[index]);
        if (!selector || !encoding || strnlen(selector, 257) > 256 || strnlen(encoding, 513) > 512) {
            capped = YES; continue;
        }
        if (!relevant(selector)) continue;
        if (methodRows >= MaxMethods) { capped = YES; break; }
        emit("%s %c%s ABI=%s\n", name, factory ? '+' : '-', selector, encoding); methodRows++;
    }
    free(methods);
}

int main(void) {
    if (!dlopen("/System/Library/PrivateFrameworks/IMCore.framework/IMCore", RTLD_NOW)
        || !dlopen("/System/iOSSupport/System/Library/PrivateFrameworks/ChatKit.framework/ChatKit", RTLD_NOW)) {
        fputs("Required framework unavailable.\n", stderr); return 1;
    }
    const char *classes[] = {"IMSticker", "CKSticker", "CKStickerMediaObject",
                             "IMAssociatedStickerChatItem", "CKAssociatedStickerChatItem"};
    for (size_t index = 0; index < sizeof(classes) / sizeof(classes[0]); index++) {
        Class cls = objc_getClass(classes[index]);
        emit("Class %s: %s\n", classes[index], cls ? "present" : "absent");
        if (!cls) continue;
        Class superclass = class_getSuperclass(cls);
        const char *superName = superclass ? class_getName(superclass) : "none";
        if (superName && strnlen(superName, 257) <= 256) emit("Superclass %s: %s\n", classes[index], superName);
        else capped = YES;
        inventory(cls, classes[index], NO); inventory(cls, classes[index], YES);
    }
    // Leave room for a fixed completion marker even when the inventory is capped.
    fputs(capped ? "Sizing metadata inventory capped; no methods invoked.\n"
                 : "Sizing metadata inventory complete; no methods invoked.\n", stdout);
    return capped ? 2 : 0;
}

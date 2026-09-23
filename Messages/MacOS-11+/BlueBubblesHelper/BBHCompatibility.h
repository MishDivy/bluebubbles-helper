// Compatibility additions to the released 0.0.21 helper. No runtime swizzling.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <string.h>

static inline BOOL BBHMethodMatches(id target, SEL selector, NSArray<NSString *> *types) {
    if (![target respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature || strcmp(signature.methodReturnType, "v") != 0
        || signature.numberOfArguments != types.count + 2) return NO;
    for (NSUInteger i = 0; i < types.count; ++i) {
        if (strcmp([signature getArgumentTypeAtIndex:i + 2], types[i].UTF8String) != 0) return NO;
    }
    return YES;
}

// nil means the native method was dispatched, NOT that delivery was confirmed.
static inline NSString *BBHEditMessage(id chat, id message, id item, NSInteger index,
                                      NSAttributedString *text, NSAttributedString *fallback) {
    if (!chat || !message || !text || !fallback || index < 0) return @"Invalid edit arguments";
    SEL modern = NSSelectorFromString(@"editMessageItem:atPartIndex:withNewPartText:newPartTranslation:backwardCompatabilityText:");
    SEL previous = NSSelectorFromString(@"editMessageItem:atPartIndex:withNewPartText:backwardCompatabilityText:");
    SEL legacy = NSSelectorFromString(@"editMessage:atPartIndex:withNewPartText:backwardCompatabilityText:");
    @try {
        if (item && BBHMethodMatches(chat, modern, @[@"@", @(@encode(NSInteger)), @"@", @"@", @"@"])) {
            ((void (*)(id, SEL, id, NSInteger, id, id, id))objc_msgSend)(chat, modern, item, index, text, nil, fallback);
        } else if (item && BBHMethodMatches(chat, previous, @[@"@", @(@encode(NSInteger)), @"@", @"@"])) {
            ((void (*)(id, SEL, id, NSInteger, id, id))objc_msgSend)(chat, previous, item, index, text, fallback);
        } else if (BBHMethodMatches(chat, legacy, @[@"@", @(@encode(NSInteger)), @"@", @"@"])) {
            ((void (*)(id, SEL, id, NSInteger, id, id))objc_msgSend)(chat, legacy, message, index, text, fallback);
        } else {
            return @"No compatible edit method or message item";
        }
    } @catch (NSException *exception) {
        (void)exception;
        return @"Native edit method raised an exception"; // no message data in errors
    }
    return nil;
}

static inline NSString *BBHInviteParticipant(id chat, id handle) {
    if (!chat || !handle) return @"Invalid participant arguments";
    SEL modern = NSSelectorFromString(@"inviteParticipants:reason:");
    SEL legacy = NSSelectorFromString(@"inviteParticipantsToiMessageChat:reason:");
    @try {
        SEL selected = BBHMethodMatches(chat, modern, @[@"@", @"@"]) ? modern
            : BBHMethodMatches(chat, legacy, @[@"@", @"@"]) ? legacy : NULL;
        if (!selected) return @"No compatible participant invitation method";
        ((void (*)(id, SEL, id, id))objc_msgSend)(chat, selected, @[handle], nil);
    } @catch (NSException *exception) {
        (void)exception;
        return @"Native participant invitation raised an exception";
    }
    return nil;
}

static inline NSDictionary *BBHActionResponse(NSString *transaction, NSString *error) {
    if (!transaction) return nil;
    return error ? @{@"transactionId": transaction, @"error": error} : @{@"transactionId": transaction};
}

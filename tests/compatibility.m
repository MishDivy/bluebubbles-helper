#import "BBHCompatibility.h"
#include <assert.h>
#include <stdio.h>

@interface Fixture : NSObject
@property id object;
@property id text;
@property id fallback;
@property id translation;
@property id participants;
@property id reason;
@property NSInteger index;
@property NSUInteger calls;
@end
@implementation Fixture @end

@interface Modern : Fixture @end
@implementation Modern
- (void)editMessageItem:(id)item atPartIndex:(NSInteger)index withNewPartText:(id)text
    newPartTranslation:(id)translation backwardCompatabilityText:(id)fallback {
    self.object = item; self.index = index; self.text = text;
    self.translation = translation; self.fallback = fallback; self.calls++;
}
- (void)inviteParticipants:(id)participants reason:(id)reason {
    self.participants = participants; self.reason = reason; self.calls++;
}
@end

@interface Previous : Fixture @end
@implementation Previous
- (void)editMessageItem:(id)item atPartIndex:(NSInteger)index withNewPartText:(id)text backwardCompatabilityText:(id)fallback {
    self.object = item; self.index = index; self.text = text; self.fallback = fallback; self.calls++;
}
@end

@interface Legacy : Fixture @end
@implementation Legacy
- (void)editMessage:(id)message atPartIndex:(NSInteger)index withNewPartText:(id)text backwardCompatabilityText:(id)fallback {
    self.object = message; self.index = index; self.text = text; self.fallback = fallback; self.calls++;
}
- (void)inviteParticipantsToiMessageChat:(id)participants reason:(id)reason {
    self.participants = participants; self.reason = reason; self.calls++;
}
@end

@interface WrongSignature : Fixture @end
@implementation WrongSignature
- (void)inviteParticipants:(id)participants reason:(NSInteger)reason {
    (void)participants; (void)reason; self.calls++;
}
- (id)editMessageItem:(id)item atPartIndex:(NSInteger)index withNewPartText:(id)text
    newPartTranslation:(id)translation backwardCompatabilityText:(id)fallback {
    (void)item; (void)index; (void)text; (void)translation; (void)fallback;
    self.calls++; return nil;
}
@end

@interface Throwing : Modern @end
@implementation Throwing
- (void)inviteParticipants:(id)participants reason:(id)reason {
    (void)participants; (void)reason;
    [NSException raise:@"Fixture" format:@"private fixture details"];
}
- (void)editMessageItem:(id)item atPartIndex:(NSInteger)index withNewPartText:(id)text
    newPartTranslation:(id)translation backwardCompatabilityText:(id)fallback {
    (void)item; (void)index; (void)text; (void)translation; (void)fallback;
    [NSException raise:@"Fixture" format:@"private fixture details"];
}
@end

int main(void) {
    @autoreleasepool {
        id message = [NSObject new], item = [NSObject new], handle = [NSObject new];
        NSAttributedString *text = [[NSAttributedString alloc] initWithString:@"synthetic edit"];
        NSAttributedString *fallback = [[NSAttributedString alloc] initWithString:@"synthetic fallback"];
        Modern *modern = [Modern new]; Previous *previous = [Previous new]; Legacy *legacy = [Legacy new];
        for (Fixture *fixture in @[modern, previous, legacy]) {
            assert(BBHEditMessage(fixture, message, item, 3, text, fallback) == nil);
            assert(fixture.index == 3 && fixture.text == text && fixture.fallback == fallback);
            assert(fixture.calls == 1);
            assert(fixture.object == (fixture == legacy ? message : item));
        }
        assert(modern.translation == nil);
        for (Fixture *fixture in @[modern, legacy]) {
            assert(BBHInviteParticipant(fixture, handle) == nil);
            assert([fixture.participants isEqual:@[handle]] && fixture.reason == nil);
            assert(fixture.calls == 2);
        }
        WrongSignature *wrong = [WrongSignature new];
        for (id fixture in @[[NSObject new], wrong, [Throwing new]]) {
            NSString *editError = BBHEditMessage(fixture, message, item, 0, text, fallback);
            NSString *inviteError = BBHInviteParticipant(fixture, handle);
            assert(editError && inviteError);
            assert(![editError containsString:@"private"] && ![inviteError containsString:@"private"]);
        }
        assert(wrong.calls == 0);
        assert(BBHEditMessage(modern, nil, item, 0, text, fallback));
        assert(BBHEditMessage(modern, message, nil, 0, text, fallback));
        assert(BBHEditMessage(modern, message, item, -1, text, fallback));
        assert(BBHEditMessage(modern, message, item, 0, nil, fallback));
        assert(BBHInviteParticipant(nil, handle) && BBHInviteParticipant(modern, nil));
        assert(BBHActionResponse(nil, nil) == nil);
        assert(BBHActionResponse(nil, @"error") == nil);
        assert([BBHActionResponse(@"fixture", nil) isEqual:@{@"transactionId": @"fixture"}]);
        assert([BBHActionResponse(@"fixture", @"error")[@"error"] isEqual:@"error"]);
        puts("Compatibility tests passed: modern/previous/legacy, argument forwarding, nil inputs, unsupported signatures, exceptions, responses.");
    }
    return 0;
}

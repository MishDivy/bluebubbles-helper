# Custom reactions on the release compatibility branch

This backport adds only the native emoji tapback path to released helper 0.0.21,
on top of the existing edit/invitation fixes. It does not import the upstream
composition/transport rewrite, install anything, restart Messages, or enable
payload logging. Build only with `scripts/build-messages.sh`.

## Native contract and capability

The implementation follows [upstream development at a8961912](https://github.com/BlueBubblesApp/bluebubbles-helper/blob/a8961912da1a2cedfe5e4eb6fc5be6ca0569a684/Messages/MacOS-11%2B/BlueBubblesHelper/BlueBubblesHelper.m#L1111).
[PR 68](https://github.com/BlueBubblesApp/bluebubbles-helper/pull/68) was closed,
not merged: the maintainer directed its author to the already implemented native
emoji path. That path constructs an `IMEmojiTapback`, wraps an existing message
part in a `CKChatItem`, and calls `IMChat`'s native send method. The same path
with a different emoji requests replacement; removal passes the existing emoji
and sets `isRemoved` to true. Native delivery and replacement semantics still
require a controlled acceptance test.

The initial socket `ping` retains its existing fields and adds:

```json
"capabilities": {"customEmojiReactions": true, "stickerReactions": false}
```

`customEmojiReactions` is calculated from loaded classes and exact signatures:

| Receiver | Selector | Return / explicit argument ABI |
| --- | --- | --- |
| IMEmojiTapback instance | `initWithEmoji:isRemoved:` | object / object, C `bool` |
| CKChatItem class | `chatItemWithIMChatItem:balloonMaxWidth:` | object / object, CGFloat |
| CKChatItem class, alternative | `chatItemWithIMChatItem:balloonMaxWidth:fullMaxWidth:transcriptTraitCollection:overlayLayout:` | object / object, CGFloat, CGFloat, object, BOOL |
| IMChat instance | `sendTapback:forChatItem:` | void / object, object |

An absent class or changed signature means false, regardless of OS version.
The upstream source describes this path as macOS 26+. Earlier systems with a
different emoji API are deliberately not guessed. Availability describes an API,
not successful delivery. The handshake is recalculated on reconnect; if ChatKit
was not loaded at the initial ping, the advertised capability remains false until
reconnect. No extra framework is dynamically loaded by the helper. Each send also
checks the actual chat object's class and the construction signatures.

Wire fields remain `event: send-reaction`, `chatGuid`, `selectedMessageGuid`,
integer `partIndex`, `reactionType: emoji` or `-emoji`, and `reactionEmoji` holding
the entire Unicode sequence. Both add and remove require the emoji. The helper
requires one composed sequence of at most 128 UTF-16 units; the server additionally
checks that it is an emoji. The six existing named reactions retain their old
path. Unknown reaction types, including stickers, are rejected.

An absent/mismatched target part is an error; it never falls back to the entire
message. The helper samples `lastSentMessage.guid` before sending, then polls at
100 ms for up to two seconds for a changed identifier. It never returns the old
identifier as success. Timeout reports that dispatch happened but confirmation
did not; callers must not automatically retry. Because another concurrent send
can advance that field, the server must match the resulting DB row's chat,
sender, target GUID and part, type, and emoji before acknowledging it. This is
confirmation of a local reaction row, not proof of recipient delivery.

## Tests and acceptance boundary

`scripts/test-compatibility.sh` runs the existing edit/invitation suite and the
new synthetic reaction suite. CI already calls this script. Reaction coverage
includes both CK factories, send/replacement/removal argument forwarding, ZWJ
families, modifiers, flags, keycaps, variation selectors, unsupported signatures,
nil construction, missing/wrong part, exception privacy, and stale/late GUIDs.
The tests do not load Messages frameworks or use accounts.

`bash scripts/probe-reactions.sh` separately loads IMCore and ChatKit in an
isolated process and checks class metadata. It does not instantiate chats or
tapbacks, look up accounts, query Messages data, or send. A passing probe does
not establish that the injected helper advertises true in Messages, nor that
the native operation delivers. Run only as a coordinated diagnostic.
It also inventories the upstream-declared sticker factory/transfer selectors'
type encodings for research; these do not change the false sticker capability.

On systems where ChatKit is a Mac Catalyst framework, a plain macOS executable
cannot load it (`wrong platform to load into process`). Use
`bash scripts/probe-reactions.sh maccatalyst` with a selected SDK containing
`System/iOSSupport`. This builds the isolated probe for the supported
[`-target <arch>-apple-ios14.0-macabi` compiler environment](https://github.com/llvm/llvm-project/blob/main/clang/test/Driver/darwin-maccatalyst.c).
It does not bypass dyld's platform check or change the helper build target.
If the installed Command Line Tools SDK lacks Catalyst support, the probe
reports that missing prerequisite; do not infer native readiness from that.

Before any production replacement, use the reviewed deployment/rollback
procedure and a user-approved self-chat acceptance window. Exercise custom
emoji add, emoji-to-emoji replacement, standard-to-emoji and reverse, removal,
multipart nonzero-index attachments, rich-link bubbles, sender isolation,
restart/history hydration, and unknown/missing emoji fallback. Confirm the
local row and both clients' rendered state; do not infer success from a selector
or a build alone.

## Sticker feasibility: explicitly incomplete

Receive-side evidence separates three concepts:

| Kind | Evidence and handling |
| --- | --- |
| Unicode emoji tapback | 2006 add / 3006 remove; carries `associated_message_emoji` |
| Sticker tapback | 2007 add / 3007 remove; requires an asset, not an emoji string |
| Placed sticker | 1000; preserve separately from a sender's single tapback slot |
| Ordinary image attachment | Image bytes alone do not establish sticker or reaction status |

These mappings are implemented in the primary-source
[imessage-exporter message classifier](https://github.com/ReagentX/imessage-exporter/blob/develop/imessage-database/src/tables/messages/message.rs)
and [imessage-kit reaction model](https://github.com/photon-hq/imessage-kit/blob/main/src/domain/reaction.ts).
The latter explicitly names 1000 as placement. Do not infer a 1000 deletion code
by arithmetic or treat 3007 as removal of any arbitrary placed sticker.

[imessage-exporter's attachment reader](https://github.com/ReagentX/imessage-exporter/blob/develop/imessage-database/src/tables/attachment.rs)
uses `is_sticker`, attachment identity/MIME/UTI, `sticker_user_info` (source bundle
ID at `pid`), `attribution_info`, and `emoji_image_short_description`. Assets may
live in StickerCache as well as Attachments. Its
[sticker parser](https://github.com/ReagentX/imessage-exporter/blob/develop/imessage-database/src/message_types/sticker.rs)
distinguishes Genmoji, Memoji, user-created and app stickers, including effects
stored in HEIC metadata. A thumbnail is not the complete animated/effect asset.

The existing upstream headers expose `IMFileTransfer.isSticker/stickerUserInfo`,
`CKMediaObjectManager.mediaObjectWithSticker:stickerUserInfo:`,
`transferWithStickerFileURL:transferUserInfo:attributionInfo:`, and sticker
composition methods. These declarations do **not** establish the object schema,
source-library access, tapback constructor, placement transform, or removal
contract. None is called by this patch. There is no sticker capability claim.

A viable receive contract needs the original association type, reaction row GUID,
sender, target GUID/part, attachment GUID, available preview and original asset
routes, MIME/UTI, dimensions/animation status, and optional documented source /
description/effect fields. Keep unknown placement metadata available internally
until its schema is verified. Return missing-asset placeholders instead of
pretending a generic PNG is a native sticker. Serving received assets is separate
from browsing installed packs or the user's sticker library; the existing Bippy
PNG utility provides neither native library access nor a native send contract.

The next evidence needed is a user-approved, controlled self-chat fixture set:
one sticker sent normally, the same sticker as a tapback and as a placed overlay,
tapback replacement/removal, two overlays from one sender, overlay deletion,
an animated sticker, one effect-bearing sticker, and a sticker on a nonzero
multipart index. Record only those chosen fixture rows and attached metadata,
with consent and local protected storage; sanitize examples before committing.
Compare before/after association codes, attachment links and hashes, source
metadata, placement transforms and deletion behavior. Then inspect the runtime
signatures of the exact demonstrated native constructor/send/removal path.
Until those gaps are closed, full native sticker receive/send/removal remains
unfinished and `stickerReactions` must remain false.

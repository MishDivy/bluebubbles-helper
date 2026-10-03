# Experimental standalone and row sticker sending

This feature branch implements standalone stickers and one-message sticker rows in the
released helper's existing transport. Production builds keep sticker sending
disabled. The initial implementation used public reference source and synthetic
tests, without accessing an installed helper, account, Messages database, or
native conversation. Later, separately authorized read-only inspection of
user-created fixtures supplied the sanitized evidence below.

## Contract and capability

The event is `send-sticker`. Its `data` contains required nonempty `chatGuid` and
`filePath` strings, plus optional `filename` and `stickerLabel`. The helper rejects
every other field, including targets, part indexes, text, effects, and rows.
The filename is a basename of at most 255 UTF-16 units; the label is at most 150.
The helper checks the resolved native chat's GUID and account service name. Only
`iMessage` passes; a client-supplied GUID prefix cannot establish the service.

The separate `send-sticker-row` event accepts only `chatGuid` and `stickers`, an
ordered array of 2 to 10 objects containing `filePath` and optional `filename`
and `stickerLabel`. Each file uses the same validation limits as a standalone
sticker; their combined size cannot exceed 5 MiB. The helper validates every
source and prepares every snapshot and marked transfer before any registration.
It constructs one attributed body with one U+FFFC per sticker, distinct transfer
GUIDs in request order, and part index `0`, numeric writing direction `-1`, and
emoji-image attribute `1` on every character. One message initializer receives
the ordered transfer GUIDs, and one native send dispatches the row.

Success retains the existing helper response shape:

```json
{"transactionId":"transaction","identifier":"exact-constructed-message-guid"}
```

A successful row additionally returns `attachmentGuids`, the ordered native
transfer GUIDs used by that exact constructed message. The server must match
those GUIDs to the row's linked sticker attachments and, where the attributed
body is available, its ordered transfer runs and part/emoji-image attributes.
Transfer display names may differ from request filenames because the native
transfer points at a private snapshot. Errors return neither message nor
attachment GUIDs.

Every error uses a fixed string without native exception details, chat IDs, or
paths. The helper constructs an `IMMessageItem`, writes its attributed body as
typedstream data, wraps that item in an `IMMessage`, and requires that object's
GUID to equal the construction GUID before registering or sending. It reads the
same object after dispatch. It never consults `lastSentMessage`. This response
acknowledges local native dispatch; the server must verify the row and attachment,
and recipient delivery requires a controlled acceptance test.

`ping.capabilities` adds `stickerSending`, `stickerPlacement`, and `stickerRows`.
`stickerPlacement` and `stickerReactions` remain false. `stickerSending` and
`stickerRows` are true only
when `BBH_EXPERIMENTAL_STICKERS=1` at compile time and every used private selector
matches its full return and argument ABI. The guard covers the registry, chat,
account, transfer center, transfer, message item, and message factory/getter.
The sticker Boolean setter supports C `bool` and signed `char` encodings using
the corresponding function type; other scalar encodings fail. Runtime checks
repeat on the actual chat, account, center, transfer, and constructed message.
The unavailable `transferWithStickerFileURL:...` factory is not used.

## Asset and transfer handling

The server must stage the source under the actual process user's
`Library/Messages/Attachments/BlueBubbles` directory. The helper derives that
root from `getpwuid(getuid())`, never an environment variable or request field.
It walks all path components with `openat` and `O_NOFOLLOW`, requires owned
directories within the staging root without group/world write permission,
and accepts only owned regular files with one link. The bounded descriptor read
rejects empty files, oversized files, FIFOs, symlinks, traversal, and changed
size/modification time. An ancestor symlink also fails, including a symlinked
Messages or staging directory.

ImageIO identifies PNG/APNG, GIF, or JPEG from the bytes. The helper requires
a complete container, 1 to 100 frames, dimensions from 1 to 618 for each frame,
at most 500 KiB, and at most 25 million aggregate decoded pixels. Each frame is
decoded and checked for complete status before native preparation. The helper
writes the validated bytes to a new private exclusive snapshot in the same
staging directory and rechecks those bytes. It preserves source bytes, alpha,
and animation; it does not resize, convert, or re-encode an image.

The transfer initially points at that snapshot in the Messages Attachments tree.
Its native GUID and local URL must match. The helper sets `isSticker`,
`stickerUserInfo`, and `attributionInfo` before message construction and daemon
registration. Its standalone body contains one attachment placeholder at part 0
with the native transfer GUID, numeric writing direction `-1`, and
`__kIMEmojiImageAttributeName` set to `1`. The ordinary attachment implementation
remains separate and unchanged.

Preparation failures remove only the helper-created snapshots. Once registration
begins, any exception or changed GUID reports an unknown outcome and retains the
snapshots because Messages may still consume them. In a row, a failure while
registering the nth transfer prevents message dispatch and retains all snapshots;
it cannot establish whether any daemon registration completed. Callers must not automatically
retry. The helper leaves the caller's original staging file intact. There is no
fallback to an ordinary image. Crash recovery and age-based cleanup of abandoned
snapshots require a separately reviewed policy; this feature does not delete
existing staging files or transfer records.

## Provenance and remaining gates

The transfer metadata, validation limits, and item-first construction adapt
the MIT-licensed [openclaw/imsg revision
640f58f4](https://github.com/openclaw/imsg/tree/640f58f4f80220b10082eafe4d725049fe2acb77/Sources/IMsgHelper),
specifically `AttachmentHandlers.inc`, `AttachmentTransfers.inc`,
`StickerAssets.inc`, `MessageConstruction.inc`, and `IMCoreDeclarations.inc`.
The copyright and license are preserved in `third-party/imsg-LICENSE`.
The metadata describes the pinned user-generated sticker path; its geometry
fields remain opaque. The helper never creates a target association or exposes
a placement transform. This adaptation still requires native validation on the
chosen OS and controlled standalone fixtures. Existing macOS 27 probes found
sticker setters but did not establish delivery or metadata compatibility.

## Controlled fixture evidence

The user created these native iPad self-chat fixtures. Read-only inspection found
one three-sticker row represented by one message with three sticker attachments
and `part_count=1`. Its attributed body contains three U+FFFC characters, each
with a distinct transfer GUID and `__kIMMessagePartAttributeName=0`. All three
characters have `__kIMEmojiImageAttributeName=1` and writing direction `-1`.
A standalone Bippy sticker has the same body attributes. This evidence supports
the standalone emoji-image attribute and the row body with all attachments
in part 0. Row sending uses the experimental gate; production defaults keep it
disabled, and native row delivery still requires acceptance.

Two placements on one text message are independent rows, each with its own
attachment, association type `1000`, and a part-0 reference to the same target.
Neither placement body has `__kIMEmojiImageAttributeName`. Their sticker metadata
uses strings for `sro`, `ssa`, `spw`, `sxs`, `sys`, `sai`, and `sli`, a Boolean for
`sir`, and an integer for `spv`. Source keys include `pid`, `sid`, and `shash`.
Coordinate units and transform semantics remain unverified. Placement sending
and removal remain disabled.
[Apple's iPad guide](https://support.apple.com/guide/ipad/send-stickers-ipaddca01563/ipados)
describes Sticker Details, swipe left, Delete as removing the sticker on that
iPad only. This is a local deletion action, not evidence of remote unsend or a
type-1000 removal transport event. A controlled deletion observation must check
local and synced outcomes separately. After the user removed duplicate placements
and left one rotated sticker on the iPad, the sampled Mac placement rows and
their self-received copies remained present, with unchanged attachment visibility
and no retraction/update flags or new related removal event. This snapshot is
consistent with iPad-local removal; it does not establish a remote deletion API.

The observed row and standalone assets are HEIC; the placement assets are PNG.
The helper still accepts only PNG/APNG/GIF/JPEG. HEIC support needs separate
validation for decoding, metadata, effects, and byte preservation. The fixtures'
source and attribution identify Bippy; they do not establish a generic Apple
Stickers source identity. This correction does not change transfer source metadata.

The synced attachment rows have `is_outgoing=0` while their messages have
`is_from_me=1`. Attachment transfer direction cannot establish message authorship.
Confirmation uses message sender/chat identity and attachment linkage/sticker
status; it must not require the attachment's outgoing flag to match the message.

Fixture inspection must use explicit column and decoded-field allowlists, scoped
to the user's selected fixtures: message ownership, association type/part,
part count and attributed-body fields; attachment linkage, sticker status,
format/dimensions and transfer direction; and approved source/geometry fields
from `sticker_user_info` and attribution. Never select, decode, or print
`attachment.user_info`, which contains private transport material. Never use
`SELECT *`. Keep private identifiers, raw message text, hashes, artwork, and
transport metadata out of committed documentation and fixtures. The account
above records structure and field types only.

## Validation and acceptance

On 2026-10-03, an isolated Mac Catalyst class-metadata probe on macOS 27.0.1
(26A434, arm64) found the `IMStickerTapback` transfer-GUID/Boolean initializer,
the `IMTapbackSender` chat/part initializer, and its object-returning `send` method.
It also found the association-aware `IMMessage` constructor with an `NSRange`.
The corresponding `IMMessageItem` association setters were absent. These are ABI
observations, not proof of delivery. `scripts/probe-stickers.sh maccatalyst`
reproduces the metadata inventory without constructing private-framework objects,
reading accounts or messages, injecting code, or sending anything. Its temporary
executable is removed on exit. CI compiles the probe but does not run it.

Build and synthetic checks use the safe scripts, which never install or restart:

```sh
./scripts/test-compatibility.sh
./scripts/build-messages.sh
BBH_EXPERIMENTAL_STICKERS=1 ./scripts/build-messages.sh
```

The experimental build writes to `build/messages-experimental-stickers`, separate
from the default artifact. CI runs synthetic tests with both macro values and
compiles both builds without publishing. Linux can check shell syntax and diffs;
the Objective-C and ImageIO tests require macOS and have not run on this Linux
workstation. Tests use generated images, temporary files, and synthetic objects;
they never load private Messages frameworks or query real data.

The metadata-only `scripts/probe-reactions.sh` also lists every selector used by
the standalone sticker candidate. It does not create accounts, chats, transfers
or messages. Run it on the target Mac only during a coordinated diagnostic;
CI compiles this probe but does not execute it. Its exit status still describes
emoji API availability, not sticker readiness. Compare the printed sticker
signatures with `BBHStickers.h` before attempting native acceptance.

Before deployment, require a native compile, synthetic test results, read-only
signature evidence, artifact provenance, rollback preparation, and the user's
approved acceptance window. A controlled standalone fixture must verify the
exact row, chat, sender, service, `is_sticker`, metadata, attachment bytes and both
clients' rendering, including animation and transparency. The helper's capability
advertises a matching API, not successful delivery.

Full parity still needs native send-path acceptance and separately approved
fixture coverage for hydration, placement transforms, removal,
2007/3007 sticker tapbacks and replacement, multipart targets, animation,
and effects. Preserve observed association types and opaque metadata until those
schemas and native constructor/removal signatures are verified. Do not derive
placement removal codes by arithmetic or repurpose emoji reaction payloads.

# Experimental sticker sending

This feature branch implements standalone stickers, one-message sticker rows,
targeted placements, and sticker tapbacks in the
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
paths. On the legacy ABI, the helper constructs an `IMMessageItem`, writes its
attributed body as typedstream data, and wraps it in an `IMMessage`. On the direct
initializer ABI, it constructs an `IMMessage` from immutable attributed text and
ordered transfer GUIDs, then checks its generated item's body and bounded,
nonempty serialized body data. Both paths require the constructed message's GUID
to equal the construction GUID before registering or sending. The helper reads
the same message object after dispatch. It never consults `lastSentMessage`. This response
acknowledges local native dispatch; the server must verify the row and attachment,
and recipient delivery requires a controlled acceptance test.

`ping.capabilities` adds `stickerSending`, `stickerPlacement`, and `stickerRows`.
`stickerSending` and
`stickerRows` are true only
when `BBH_EXPERIMENTAL_STICKERS=1` at compile time and every used private selector
matches its full return and argument ABI. The guard covers the registry, chat,
account, transfer center, transfer, message item, and selected message constructor
and getters. An exact legacy ABI takes precedence over the exact direct ABI.
A constructor failure cannot switch paths or trigger another send attempt.
The sticker Boolean setter supports C `bool` and signed `char` encodings using
the corresponding function type; other scalar encodings fail. Runtime checks
repeat on the actual chat, account, center, transfer, and constructed message.
The unavailable `transferWithStickerFileURL:...` factory is not used.

## Direct construction compatibility evidence

An isolated metadata probe on macOS 27.0.1 found the legacy
`IMMessage +messageFromIMMessageItem:sender:subject:` factory absent. Every other
standalone and row guard matched, including the message-item initializer's object
`error` argument. The replacement five-argument factory has additional
`accountController` and `itemCreator` dependencies whose nil behavior is unknown;
this implementation does not use it.

The verified direct initializer is
`initWithSender:time:text:fileTransferGUIDs:flags:error:guid:subject:threadIdentifier:`,
with arm64 encoding `@88@0:8@16@24@32@40Q48@56@64@72@80`.
The isolated `tests/probe-sticker-construction.m` uses only generated standalone
and two-item row bodies and nonexistent synthetic transfer IDs. Native
construction retained the explicit GUID, flags, attributed text and transfer
order. Initial and repeated `_imMessageItem` reads contained nonempty typedstream
archives that decoded exactly to those generated bodies, including every required
per-character attribute. The getter returned different item objects. An explicitly
stamped archive did not persist; regenerated native archives still decoded to the
same body. The final probe, which performed no archive writes, passed for both
standalone and row bodies. The modern path therefore leaves
serialization to the verified native initializer and does not stamp a transient
item. The legacy path retains its explicit archive write.

This probe did not resolve chats or accounts, create or register file transfers,
or send messages. Construction and serialization evidence do not establish
recipient delivery or sticker rendering; controlled self-chat acceptance remains
required. The unrelated placement path is unchanged.

### Read-only staged asset diagnostic

`bash scripts/probe-sticker-asset.sh "$explicit_staged_path"` reads exactly one
operator-selected attempted upload. Select it separately by the known attempt
time and file metadata; the probe does not discover files or choose a recent one.
It derives the actual account's staging root with `BBHStickerRoot` and accepts
only a safe basename directly inside one UUID staging directory under that root.
It uses the helper's exact `BBHStickerDirectory`, `BBHStickerRead`, and
`BBHStickerImage` functions. Output contains only stage booleans and, after full
validation, the allowlisted format, dimensions, and frame count. It never prints
paths, filenames, content, hashes, native exception details, or message data.

The diagnostic links public frameworks only and performs no transfer preparation,
registration, chat lookup, or send. Its runner creates and removes only its own
temporary executable directory; it does not alter the selected asset. Compatibility
checks compile this probe without executing it or reading any staged files.

For the explicitly selected self-chat attempt on 2026-10-04, the isolated asset
probe exited `0`: root, staging path, directory, bounded read, and image validation
all passed. ImageIO identified a 512 by 512 PNG with one frame. The operator
confirmed cleanup of the isolated source and executable. This run used the SSH
execution context; it does not establish that Messages has the same sandbox or
entitlement access. Transfer preparation, construction in the installed helper,
registration, and sending remain unproven for that attempt.

## Targeted sticker tapbacks

`send-sticker-tapback` accepts `chatGuid`, `selectedMessageGuid`, required integer
`partIndex`, `filePath`, and optional `filename` and `stickerLabel`. It adds or
replaces the caller's sticker tapback using `IMStickerTapback` and `IMTapbackSender`.
`remove-sticker-tapback` accepts only `chatGuid`, `selectedMessageGuid`, `partIndex`,
and mandatory `reactionGuid`. Neither operation accepts a caller-supplied native
transfer GUID. Both reject extra fields.

Before reading an asset or registering a transfer, the helper checks that the
native chat stores the requested message, loads that exact GUID, and resolves
one matching native part with a nonempty, nonoverflowing range. Lookup settles
once on the main queue and has a ten-second deadline. A late or repeated native
callback cannot trigger preparation or sending. Multipart attachment aggregates
use their verified native parts; the helper never falls back to another part.

Removal reads only the selected part's current visible associated chat items.
It unwraps only the known native acknowledgment aggregate, with a 256-item bound.
One own live sticker reaction of type `2007` must match the requested target,
part, and `reactionGuid`. The helper obtains its transfer GUID from the native
tapback, constructs the native removed counterpart, and requires its type to be
`3007`. It checks the current reaction again before dispatch. This stale-request
guard is not a cross-process transaction; native replacement/removal behavior
still needs controlled acceptance. Removal does not upload, snapshot, allocate,
or register an attachment.

Add/replace uses the same bounded ImageIO validation, no-follow staging reads,
private snapshots, and transfer ABI checks as standalone sending. The tapback
metadata follows the pinned imbridge tapback path, including its user-generated
source identity and nil attribution. It does not claim to identify Bippy or any
other sticker pack. Exported native constants identify `pid` as a sticker pack
GUID, not a bundle-ID field. Metadata compatibility remains an acceptance gate.

Both operations return only the GUID on the exact `IMMessage` returned by
`IMTapbackSender.send`. A nil result, wrong class, missing GUID, or exception
after registration/dispatch is an unknown outcome that must not trigger retry.
The helper never reads `lastSentMessage`. The server must confirm native chat,
authorship, association type/target/part, and sticker linkage against that GUID.
`stickerReactions` requires the experimental flag and the exact target, transfer,
tapback, sender, associated-item, and acknowledgment-aggregate ABIs. The capability
describes available APIs, not successful delivery.

The constructors and tapback transfer metadata adapt the Apache-2.0
[imbridge 0010 patch](https://github.com/christianblandford/imbridge/blob/df8c9601b05f2fc2daef070a07f4f883cee350ba/helper/patches/0010-sticker-tapbacks.patch).
`third-party/imbridge-NOTICE` preserves its attribution and records this fork's
changes; the repository's `LICENSE` contains Apache-2.0.

## Targeted sticker placements

`send-sticker-placement` accepts `chatGuid`, `selectedMessageGuid`, integer
`partIndex`, `filePath`, optional `filename` and `stickerLabel`, and required
`placement: {x, y, scale, rotation, parentWidth}`. Every geometry value must be a
finite non-Boolean number. The application accepts x/y center fractions from
`-4` to `4`, scale from `0.01` to `4`, rotation from `-2π` to `2π` radians, and
parent preview width from `1` to `4096` points. These are implementation limits,
not Apple's documented supported domain. Extra fields fail validation.

The shared target lookup resolves the exact chat, message, and native part before
asset preparation. The helper requires the part's current nonempty range to match
the loaded range. It preserves the existing pinned imsg user-generated source and
attribution metadata, rather than mixing in imbridge's different attribution
schema. All five supplied geometry values replace the source's opaque geometry
fields as locale-independent strings with 17 significant digits. Layout intents
`sai`/`sli` use the observed string `"0"`; `spv` uses numeric `0`, and `sir` is false.
The receiver must tolerate either numeric or numeric-string geometry/version
values observed across native sources. Intrinsic scale sizing still needs native
visual acceptance.

The helper constructs one association-aware `IMMessage` with type `1000`, target
`p:<part>/<guid>`, the native part range, summary `{eogcd: 3, ust: true}`, and flags
`0x5`. Its body contains one U+FFFC, the exact transfer GUID, part `0`, writing
direction `-1`, and no emoji-image attribute. It writes that body to the constructed
message item's typedstream and requires the exact supplied construction GUID
before registration. The standalone/row path uses flags `0x100005`; both flag
sets follow the pinned native reference and require acceptance on the target OS.

Success returns the exact constructed message GUID after one dispatch. Preparation
failures clean only the new snapshot; registration or send failures keep it and
report an unknown outcome with no retry. `stickerPlacement` requires the
experimental flag and exact registry, target, transfer, message-item, chat-send,
and association-aware constructor ABIs. The absent item association setters are
not used. Each placement creates an independent message; this API does not edit
or remotely remove an existing placement.

The associated constructor adapts the Apache-2.0
[imbridge 0009 patch](https://github.com/christianblandford/imbridge/blob/df8c9601b05f2fc2daef070a07f4f883cee350ba/helper/patches/0009-stickers.patch),
with source attribution in `third-party/imbridge-NOTICE`.

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

Directory traversal uses search-only descriptors when the SDK defines `O_SEARCH`
and the runtime is macOS 13 or later. The [published Ventura XNU header](https://github.com/apple-oss-distributions/xnu/blob/xnu-8792.41.9/bsd/sys/fcntl.h)
defines this mode separately from data reads; the published Big Sur and Monterey
headers do not. macOS 11/12 and older SDK builds retain the existing read-only
directory walk. This conservative availability gate does not retry a denied
search-only open with different flags. Every component still uses no-follow
descriptors and the same metadata checks; leaf reads still require read permission
and pass all ownership, size, link-count and stability checks.

A read-only policy check of the live Messages process on 2026-10-04 allowed
metadata access along the attempted staging path and data access to Messages'
attachment staging directories and the selected file, but denied data reads on
three higher-level ancestors. This explains why a traversal that opens each
ancestor for reading can fail even when direct access to the staged file is
allowed. The isolated regression in `tests/sticker-sandbox.m` applies a profile
only to its disposable child and synthetic fixtures. It checks that a legacy
ancestor read fails while bounded leaf reads and snapshot creation/read/removal
work, and checks the existing symlink, ownership and writable-path restrictions.
It does not query or change Messages, account state, or sandbox policy for another
process. Live helper acceptance remains separate from this regression.

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
The metadata describes the pinned user-generated sticker path. Standalone and
row sends keep its opaque geometry fields; placement sends replace them with
validated caller values as described above. This adaptation requires native validation on the
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
Those fixtures alone did not establish coordinate units or transform semantics.
Experimental placement construction is implemented; native removal is not.
The later synthetic probe observations below describe the geometry evidence
collected since the initial fixture inspection.
[Apple's iPad guide](https://support.apple.com/guide/ipad/send-stickers-ipaddca01563/ipados)
describes Sticker Details, swipe left, Delete as removing the sticker on that
iPad only. This is a local deletion action, not evidence of remote unsend or a
type-1000 removal transport event. A controlled deletion observation must check
local and synced outcomes separately. After the user removed duplicate placements
and left one rotated sticker on the iPad, the sampled Mac placement rows and
their self-received copies remained present, with unchanged attachment visibility
and no retraction/update flags or new related removal event. This snapshot is
consistent with iPad-local removal; it does not establish a remote deletion API.

A later iPad picker action created another type-1000 association, this time with
`sir=true`. Its separate outgoing and self-received rows remained after the user
deleted one copy through Sticker Details. This snapshot shows no related removal
event; it does not prove that every sticker deletion is local. Keep these
independent sticker messages separate from the single-actor type-2007 tapback
slot. Never remove a type-1000 sticker through the type-3007 endpoint.

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

A later scoped observation found both position-version-0 numeric strings and
position-version-1 numeric values. Receive code must accept both finite forms;
the earlier observation does not define every version's field types. Exported
IMSharedUtilities constants identify `sli`/`sai` as layout intents, `spw` as parent
preview width, `sxs`/`sys` as position scalars, `ssa` as scale, and `sro` as
rotation. `pid` is a pack GUID; `sbid` is a bundle ID. These names came from the
installed framework's static constants, not private attachment transport data.

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

The separate `geometry` probe mode uses synthetic inputs with two native class
layout methods. It checks their full arm64 ABIs and the geometry struct's named
field types before calling them. With layout intents 0, position scalars identify
the sticker center as a fraction of the parent rectangle and rotation is in
radians. The transform scales by current parent width divided by parent preview
width. The descriptor's own sticker scale does not change these two methods'
output; intrinsic sticker sizing and orientation still need separate checks.
This probe creates no message, chat, transfer, or view objects and never sends.

The `sizing` mode inventories only size, scale, layout, image and geometry-related
method names and type encodings declared on `IMSticker`, `CKSticker`,
`CKStickerMediaObject`, `IMAssociatedStickerChatItem` and
`CKAssociatedStickerChatItem`, plus their superclass names. It does not enumerate
inherited methods. It creates no instances and invokes no private
methods. Output is capped at 100 method rows, 128 lines and 32 KiB; a cap produces
exit status 2 and an explicit incomplete marker. Missing classes are reported.
Run `bash scripts/probe-stickers.sh maccatalyst sizing` only during a coordinated
diagnostic. Compatibility CI compiles this mode without executing it.

The sizing and expanded geometry modes compiled and ran in isolated diagnostics
on macOS 27.0.1 (26A434, arm64), both with exit status 0. The runner removed each
temporary executable and directory. `CKSticker` was absent. `IMSticker` exposed
the class method `calculatePreviewScaleWithTargetSize:imageData:` with ABI
`d40@0:8{CGSize=dd}16@32`, and its target-size instance method. The other scoped
classes exposed preview shading, geometry refresh or size-that-fits methods.
These signatures do not establish an intrinsic sizing formula.

The separate `preview-scale` mode calls only that verified `IMSticker` class
method after checking the exact ABI and arm64 architecture. It generates static
PNG data in memory for four square/non-square source sizes, three small target
sizes, and opaque versus half-transparent pixels: 24 fixed cases. Source
dimensions are at most 320 per side and encoded PNG data at most 1 MiB. It prints
only synthetic dimensions, alpha flags, target sizes and finite returned scales.
It creates no sticker, transfer, message, account, chat or view instances and
accesses no files or user artwork. CI compiles it without running it. Its native
compile required an explicit bitmap-enum cast for clang's strict warnings and
the same ChatKit framework load used by the sizing inventory. With those source
corrections, the isolated macOS 27.0.1 run passed the exact ABI guard, then
reported the fixed synthetic-calculation failure and exited 3. The protected
block includes PNG generation and the class-method call, so its output does not
identify the exact failing step.
The matrix did not complete and produced no usable sizing results. Exception
details were not printed; the runner cleaned its temporary files on every run.
The console context may be insufficient, but the cause is not proven. This probe
does not establish preview scale, intrinsic sticker size or a received-layout
formula. Do not initialize UI objects or apps, or relax the guards to pursue this
failure. Controlled device sizing acceptance remains required; no further native
probes are planned for this diagnostic window.

The expanded geometry probe also checks synthetic reaction-layout coordinates
for indices 0 through 5, both parent directions, zero insets and three nonzero
inset tuples. These calls use the existing exact ABI guards. It also checks native
dictionary roundtrips. On the tested OS,
`IMSticker.geometryDescriptorFromUserInfoDictionary:` returned a parent width
equal to the supplied layout intent, ignoring the supplied `spw`, for both
numeric and string dictionaries. Other position/scale/rotation fields survived.
This class-method observation does not establish how a real transcript item
loads its geometry. Do not rewrite source metadata to reproduce it or claim
pixel-accurate rendering from the class layout calculations alone.

For the synthetic parent rectangle `(0,0,200,100)` and zero insets, the verified
reaction-location method returned:

| Index | Parent fromMe=false | Parent fromMe=true |
| --- | --- | --- |
| 0 | (152,76) | (0,76) |
| 1 | (0,-24) | (152,-24) |
| 2 | (176,52) | (-24,52) |
| 3 | (-24,0) | (176,0) |
| 4 | (152,52) | (0,52) |
| 5 | (0,0) | (152,0) |

Horizontal insets of 12 left and 20 right moved left-side x coordinates by +12
and right-side coordinates by -20. Top inset 8 moved top-side y coordinates by
+8; bottom inset 16 moved bottom-side coordinates by -16. These are synthetic
class-method results, not evidence of how received type-1000 `sir=true` stickers
get their indices. Intrinsic sticker sizing and received-index assignment still
require separate evidence.

The `tapback` mode constructs two `IMStickerTapback` descriptors with a synthetic,
nonexistent transfer GUID after verifying the exact initializer and getter ABIs.
On the same Mac, their native types were `2007` and `3007` for the false and true
removal flags. It creates no sender, transfer, chat, account, or message. This
confirms that those descriptor types exist alongside the observed type-1000
picker stickers; it does not establish how recipients display either send path.

`tests/probe-sticker-container.m` is a separate public ImageIO diagnostic. It
accepts only explicitly selected fixture paths and prints bounded container
counts, dimensions, alpha flags and auxiliary type/shape metadata. It does not
print paths, artwork, descriptions, content identifiers or transport data. Run it
only for the user's approved fixtures, never as a library scan. CI compiles it
but does not run it against private files.

For the selected row and standalone fixtures, ImageIO exposed one 320-by-320
HEIC image with alpha and orientation 1. Its sole untyped auxiliary descriptor
contained only width, height, orientation and pixel format `L008`, matching the
main dimensions. ImageIO's auxiliary-data lookup returned no data for either
known alpha URN. That observation supports only a narrowly checked raster
preview, not an inferred auxiliary type or preservation of unknown effects.
All selected fixtures omitted `stickerEffectType`. Original attachment bytes
must remain available independently of any derived preview.

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

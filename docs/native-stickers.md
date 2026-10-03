# Experimental standalone sticker sending

This feature branch implements one standalone native sticker per request in the
released helper's existing transport. Production builds keep sticker sending
disabled. No installed helper, account, Messages database, or native conversation
was accessed or changed during implementation.

## Contract and capability

The event is `send-sticker`. Its `data` contains required nonempty `chatGuid` and
`filePath` strings, plus optional `filename` and `stickerLabel`. The helper rejects
every other field, including targets, part indexes, text, effects, and rows.
The filename is a basename of at most 255 UTF-16 units; the label is at most 150.
The helper checks the resolved native chat's GUID and account service name. Only
`iMessage` passes; a client-supplied GUID prefix cannot establish the service.

Success retains the existing helper response shape:

```json
{"transactionId":"transaction","identifier":"exact-constructed-message-guid"}
```

Every error uses a fixed string without native exception details, chat IDs, or
paths. The helper constructs an `IMMessageItem`, writes its attributed body as
typedstream data, wraps that item in an `IMMessage`, and requires that object's
GUID to equal the construction GUID before registering or sending. It reads the
same object after dispatch. It never consults `lastSentMessage`. This response
acknowledges local native dispatch; the server must verify the row and attachment,
and recipient delivery requires a controlled acceptance test.

`ping.capabilities` adds `stickerSending`, `stickerPlacement`, and `stickerRows`.
The latter two and `stickerReactions` remain false. `stickerSending` is true only
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
with the native transfer GUID. The ordinary attachment implementation remains
separate and unchanged.

Preparation failures remove only the helper-created snapshot. Once registration
begins, any exception or changed GUID reports an unknown outcome and retains the
snapshot because Messages may still consume it. Callers must not automatically
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

Before deployment, require a native compile, synthetic test results, read-only
signature evidence, artifact provenance, rollback preparation, and the user's
approved acceptance window. A controlled standalone fixture must verify the
exact row, chat, sender, service, `is_sticker`, metadata, attachment bytes and both
clients' rendering, including animation and transparency. The helper's capability
advertises a matching API, not successful delivery.

Full parity needs separately approved native fixtures for standalone sticker
rows and hydration, placements and multiple overlays, transforms, removal,
2007/3007 sticker tapbacks and replacement, multipart targets, animation,
and effects. Preserve observed association types and opaque metadata until those
schemas and native constructor/removal signatures are verified. Do not derive
placement removal codes by arithmetic or repurpose emoji reaction payloads.

# Editing and participant invitation compatibility

The fork's canonical tested production branch is `main`, promoted from
`feature/custom-reactions` at `0a9072f1172bc46f1a33a2bc58b8df05cd8e81ef`.
It is based on released helper **0.0.21**, commit
`2163c5aa39e56077d2f3e510808ac20b0703843b`, not the broader rewrite on master.
Preserve `master` as the separate upstream rewrite line. Build an exact reviewed
commit; do not merge the rewrite merely to deploy. The branch promotion retains
the pinned helper identity above and does not change the installed binary.

The original shipped helper's arm64/arm64e `__text` and `__cstring` sections were
compared with the 0.0.21 release and matched. File hashes differ because the
server distribution re-signs the helper.

## Changes

- Editing chooses an available, signature-checked native method. The newer
  method receives a nil translation argument; old method variants remain.
- Adding a participant chooses `inviteParticipants:reason:` where available,
  falling back to the older name. Existing eligibility checks are retained.
- Unsupported signatures and native exceptions return a generic error without
  message/contact details. Edit acknowledgement follows native dispatch rather
  than preceding the asynchronous message lookup. It is **not delivery proof**.
- Four existing integer values accidentally declared as pointers are corrected
  so the released code compiles with current clang. No new features are added.
- Removal, polls, sticker rendering and server-side timeout verification are not
  fixed by this patch. Do not infer support from a menu item or generic HTTP 200.

The upstream development branch includes similar selector support but has
[reported transaction-nil crashes](https://github.com/BlueBubblesApp/bluebubbles-helper/issues/72).
Those rewritten paths are not brought into this release-based patch.

## VS Code and builds

Open this repository in VS Code. The included tasks run offline tests and build
on macOS (locally or through VS Code Remote SSH). Editing works on Linux/Windows,
but native compilation needs macOS Command Line Tools and SDK private-framework
stubs. No full Xcode, CocoaPods install, account login or downloaded dependency
is needed: the existing socket sources are already tracked by upstream.

```sh
./scripts/test-compatibility.sh
./scripts/build-messages.sh
./scripts/probe-macos.sh
```

Build output is ignored under `build/messages/`. The build produces arm64 and
arm64e slices and an ad-hoc signature; this is not an official notarized release.
The test uses synthetic objects only. The separate read-only probe inspects
method signatures on the real Mac; it never creates chats or sends messages.

Do **not** use the old Xcode Play/build workflow as a harmless check: its build
phases copy files and terminate Messages. The new scripts never install,
restart, change security settings or run production message actions. Deployed
builds omit DEBUG because upstream debug logs can contain private message data.

## Installation and future updates

Deployment belongs in `divy-mac-utils/deploy/services/bluebubbles.md`, including
the candidate commit/hash, pre-change backup, exact installed paths and recovery.
Do not write into an installed application from the fork's build scripts.

A manual helper replacement invalidates BlueBubbles' vendor resource seal. Keep
the original helper/checksum and restore them for rollback; do not disable
Gatekeeper/SIP or re-sign the whole server. A server upgrade can replace the
custom helper. Re-audit before applying again; no auto-updater is installed.

Before upstreaming, rebase/reimplement the relevant changes against current
master and run its full checks separately. Before deployment, require tests,
signature probe, verified provenance and rollback. After deployment require the
owner to test a fresh self-chat edit and the intended group invitation. Native
API acceptance, socket connection and stable PIDs are not proof of delivery.

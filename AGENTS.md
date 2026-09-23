# Personal compatibility branch

- Keep master aligned with upstream. The fix/macos-edit-and-invite branch is
  based on released helper 0.0.21 (2163c5aa39e56077d2f3e510808ac20b0703843b),
  deliberately not the later broad rewrite on master.
- Scope changes to Messages/MacOS-11+, its tests and build tooling. Do not modify
  FaceTime, MacOS-10, account state or the upstream transport without a new need.
- Build with scripts/build-messages.sh and test with scripts/test-compatibility.sh.
  Upstream Xcode build phases can copy/install artifacts and kill Messages; do
  not run them as a harmless build. Our scripts never deploy or restart.
- Test with synthetic objects, offline. Never send/edit messages or change real
  participants as a health check. User acceptance is separate from unit tests.
- Do not enable DEBUG in deployed builds: upstream debug logging includes private
  message payloads. Never commit logs, messages, credentials or private host data.
- Deployment belongs in divy-mac-utils's BlueBubbles service record, with exact
  hashes, protected backup, rollback and an approved interruption window.
- Preserve user changes. No automatic upgrades, re-signing the entire server,
  SIP/Gatekeeper changes, or unattended replacement of the helper.

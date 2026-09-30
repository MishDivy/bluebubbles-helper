# Fork branch policy

- main is this fork's canonical tested production branch, promoted from
  feature/custom-reactions at 0a9072f1172bc46f1a33a2bc58b8df05cd8e81ef.
  It is based on released helper 0.0.21 (2163c5aa39e56077d2f3e510808ac20b0703843b).
- Preserve master as the separate upstream rewrite line. Integrating that rewrite
  requires its own review and tests; changing a default branch is not deployment.
- Keep deployment pinned to the reviewed helper commit and artifact hash. The
  branch promotion does not replace or rebuild the installed helper.
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

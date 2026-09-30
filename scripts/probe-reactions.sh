#!/bin/bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
[[ $(uname -s) == Darwin ]] || { echo 'Requires macOS Command Line Tools.' >&2; exit 2; }
probe_flags=()
case "${1:-macos}" in
    macos) ;;
    maccatalyst)
        sdk=$(xcrun --sdk macosx --show-sdk-path)
        support="$sdk/System/iOSSupport"
        [[ -d "$support/System/Library/Frameworks" && -d "$support/usr/lib" ]] || {
            echo 'The selected SDK lacks Mac Catalyst support; select an Xcode SDK with iOSSupport.' >&2
            exit 2
        }
        # A genuine Catalyst executable is required to load Catalyst ChatKit.
        # This changes only the isolated probe's target, never Messages/dyld.
        probe_flags=(-target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$sdk"
            -isystem "$support/usr/include" -iframework "$support/System/Library/Frameworks"
            -L"$support/usr/lib" -F"$support/System/Library/Frameworks")
        ;;
    *) echo 'Usage: bash scripts/probe-reactions.sh [macos|maccatalyst]' >&2; exit 2 ;;
esac
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/bbh-reactions-probe.XXXXXXXX")
trap 'rm -f "$probe_dir/probe"; rmdir "$probe_dir"' EXIT
xcrun clang "${probe_flags[@]}" -fobjc-arc -fblocks -Wall -Wextra -Werror -framework Foundation \
    -I"$root/Messages/MacOS-11+/BlueBubblesHelper" \
    "$root/tests/probe-reactions.m" -o "$probe_dir/probe"
"$probe_dir/probe"

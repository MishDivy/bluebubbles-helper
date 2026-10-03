#!/bin/bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
[[ $(uname -s) == Darwin ]] || { echo 'Requires macOS Command Line Tools.' >&2; exit 2; }
flags=(-fobjc-arc -fblocks -Wall -Wextra -Werror)
case "${1:-macos}" in
    macos) ;;
    maccatalyst)
        sdk=$(xcrun --sdk macosx --show-sdk-path)
        support="$sdk/System/iOSSupport"
        [[ -d "$support/System/Library/Frameworks" && -d "$support/usr/lib" ]] || {
            echo 'The selected SDK lacks Mac Catalyst support.' >&2; exit 2;
        }
        flags+=(-target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$sdk"
            -isystem "$support/usr/include" -iframework "$support/System/Library/Frameworks"
            -L"$support/usr/lib" -F"$support/System/Library/Frameworks")
        ;;
    *) echo 'Usage: bash scripts/probe-stickers.sh [macos|maccatalyst] [metadata|geometry]' >&2; exit 2 ;;
esac
case "${2:-metadata}" in
    metadata) source_file="$root/tests/probe-stickers.m" ;;
    geometry) source_file="$root/tests/probe-sticker-geometry.m" ;;
    *) echo 'Probe must be metadata or geometry.' >&2; exit 2 ;;
esac
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/bbh-stickers-probe.XXXXXXXX")
trap 'rm -f "$probe_dir/probe"; rmdir "$probe_dir"' EXIT
xcrun clang "${flags[@]}" -framework Foundation -framework CoreGraphics -framework QuartzCore \
    "$source_file" -o "$probe_dir/probe"
"$probe_dir/probe"

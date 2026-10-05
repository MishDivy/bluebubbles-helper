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
    *) echo 'Usage: bash scripts/probe-stickers.sh [macos|maccatalyst] [metadata|sizing|preview-scale|geometry|tapback|construction|row-lifecycle|glyph|glyph-encoding] [--synthetic]' >&2; exit 2 ;;
esac
case "${2:-metadata}" in
    metadata) source_file="$root/tests/probe-stickers.m" ;;
    sizing) source_file="$root/tests/probe-sticker-sizing.m" ;;
    preview-scale) source_file="$root/tests/probe-sticker-preview-scale.m" ;;
    geometry) source_file="$root/tests/probe-sticker-geometry.m" ;;
    tapback) source_file="$root/tests/probe-sticker-tapback.m" ;;
    construction) source_file="$root/tests/probe-sticker-construction.m" ;;
    row-lifecycle) source_file="$root/tests/probe-sticker-row-lifecycle.m" ;;
    glyph)
        [[ "${1:-macos}" == macos ]] || { echo 'Glyph data diagnostic requires the native macOS AppKit target.' >&2; exit 2; }
        [[ $# -le 3 && ( $# -lt 3 || "$3" == --synthetic ) ]] || { echo 'Glyph mode accepts only optional --synthetic.' >&2; exit 2; }
        source_file="$root/tests/probe-sticker-glyph.m"
        flags+=(-framework AppKit)
        ulimit -c 0
        ;;
    glyph-encoding)
        [[ "${1:-macos}" == macos && $# -le 2 ]] || { echo 'Glyph encoding diagnostic requires macos and no extra arguments.' >&2; exit 2; }
        source_file="$root/tests/probe-sticker-glyph-encoding.m"
        flags+=(-framework AppKit)
        ulimit -c 0
        ;;
    *) echo 'Unknown probe mode.' >&2; exit 2 ;;
esac
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/bbh-stickers-probe.XXXXXXXX")
trap 'rm -f "$probe_dir/probe"; rmdir "$probe_dir"' EXIT
xcrun clang "${flags[@]}" -framework Foundation -framework CoreGraphics -framework QuartzCore -framework ImageIO \
    "$source_file" -o "$probe_dir/probe"
if [[ "${2:-metadata}" == glyph && "${3:-}" == --synthetic ]]; then
    "$probe_dir/probe" --synthetic
else
    "$probe_dir/probe"
fi

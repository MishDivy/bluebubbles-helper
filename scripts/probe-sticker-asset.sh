#!/bin/bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
[[ $# -eq 1 ]] || { echo 'Provide exactly one explicitly selected staged asset path.' >&2; exit 2; }
[[ $(uname -s) == Darwin ]] || { echo 'Requires macOS Command Line Tools.' >&2; exit 2; }
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/bbh-sticker-asset-probe.XXXXXXXX")
trap 'rm -f "$probe_dir/probe"; rmdir "$probe_dir"' EXIT
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -framework Foundation -framework ImageIO -framework CoreGraphics \
    -I"$root/Messages/MacOS-11+/BlueBubblesHelper" \
    "$root/tests/probe-sticker-asset.m" -o "$probe_dir/probe"
"$probe_dir/probe" "$1"

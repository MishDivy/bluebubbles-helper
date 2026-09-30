#!/bin/bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
[[ $(uname -s) == Darwin ]] || { echo 'Requires macOS Command Line Tools.' >&2; exit 2; }
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/bbh-reactions-probe.XXXXXXXX")
trap 'rm -f "$probe_dir/probe"; rmdir "$probe_dir"' EXIT
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -framework Foundation \
    -I"$root/Messages/MacOS-11+/BlueBubblesHelper" \
    "$root/tests/probe-reactions.m" -o "$probe_dir/probe"
"$probe_dir/probe"

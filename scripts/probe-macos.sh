#!/bin/bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
[[ $(uname -s) == Darwin ]] || { echo 'Requires macOS Command Line Tools.' >&2; exit 2; }
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/bbh-signature-probe.XXXXXXXX")
trap 'rm -f "$probe_dir/probe"; rmdir "$probe_dir"' EXIT
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation \
    "$root/tests/probe-macos.m" -o "$probe_dir/probe"
"$probe_dir/probe"

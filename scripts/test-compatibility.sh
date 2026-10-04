#!/bin/bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
[[ $(uname -s) == Darwin ]] || { echo 'Requires macOS Command Line Tools.' >&2; exit 2; }
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bbh-compat-test.XXXXXXXX")
trap 'rm -f "$test_dir/compat-test" "$test_dir/reactions-test" "$test_dir/stickers-test" "$test_dir/sticker-tapbacks-test" "$test_dir/probe-build-check"; rmdir "$test_dir"' EXIT
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -framework Foundation \
    -I"$root/Messages/MacOS-11+/BlueBubblesHelper" \
    "$root/tests/compatibility.m" -o "$test_dir/compat-test"
"$test_dir/compat-test"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -framework Foundation \
    -I"$root/Messages/MacOS-11+/BlueBubblesHelper" \
    "$root/tests/reactions.m" -o "$test_dir/reactions-test"
"$test_dir/reactions-test"
for experimental in 0 1; do
    xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-deprecated-declarations \
        -DBBH_EXPERIMENTAL_STICKERS="$experimental" -framework Foundation -framework ImageIO -framework CoreGraphics \
        -I"$root/Messages/MacOS-11+/BlueBubblesHelper" \
        "$root/tests/stickers.m" -o "$test_dir/stickers-test"
    "$test_dir/stickers-test"
    xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-deprecated-declarations \
        -DBBH_EXPERIMENTAL_STICKERS="$experimental" -framework Foundation -framework ImageIO -framework CoreGraphics \
        -I"$root/Messages/MacOS-11+/BlueBubblesHelper" \
        "$root/tests/sticker-tapbacks.m" -o "$test_dir/sticker-tapbacks-test"
    "$test_dir/sticker-tapbacks-test"
done
# Compile the metadata probe without loading private frameworks or running it.
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -framework Foundation \
    -I"$root/Messages/MacOS-11+/BlueBubblesHelper" \
    "$root/tests/probe-reactions.m" -o "$test_dir/probe-build-check"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -framework Foundation \
    "$root/tests/probe-stickers.m" -o "$test_dir/probe-build-check"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation \
    "$root/tests/probe-sticker-sizing.m" -o "$test_dir/probe-build-check"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation -framework CoreGraphics -framework ImageIO \
    "$root/tests/probe-sticker-preview-scale.m" -o "$test_dir/probe-build-check"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -framework Foundation \
    -framework CoreGraphics -framework QuartzCore \
    "$root/tests/probe-sticker-geometry.m" -o "$test_dir/probe-build-check"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -framework Foundation \
    "$root/tests/probe-sticker-tapback.m" -o "$test_dir/probe-build-check"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -framework Foundation \
    "$root/tests/probe-sticker-construction.m" -o "$test_dir/probe-build-check"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -framework Foundation -framework ImageIO -framework CoreGraphics \
    -I"$root/Messages/MacOS-11+/BlueBubblesHelper" \
    "$root/tests/probe-sticker-asset.m" -o "$test_dir/probe-build-check"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation -framework ImageIO \
    "$root/tests/probe-sticker-container.m" -o "$test_dir/probe-build-check"

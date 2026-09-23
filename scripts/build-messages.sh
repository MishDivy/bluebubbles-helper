#!/bin/bash
# Compile only: bypass upstream Xcode phases that copy files and kill Messages.
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
[[ $(uname -s) == Darwin ]] || { echo 'Requires macOS Command Line Tools.' >&2; exit 2; }
out="$root/build/messages"
src="$root/Messages/MacOS-11+/BlueBubblesHelper"
pod="$root/Messages/MacOS-11+/Pods/CocoaAsyncSocket/Source/GCD"
sdk=$(xcrun --sdk macosx --show-sdk-path)
mkdir -p "$out"
xcrun clang -dynamiclib -fobjc-arc -fmodules -fblocks -O2 -DNDEBUG \
    -Wno-nullability-completeness -Wno-deprecated-declarations \
    -arch arm64 -arch arm64e -mmacosx-version-min=11.0 -isysroot "$sdk" \
    -fmodules-cache-path="$out/module-cache" \
    -I"$src" -I"$src/ZKSwizzle" -I"$pod" -include "$src/PrefixHeader.pch" \
    -F"$sdk/System/Library/PrivateFrameworks" \
    -framework Foundation -framework AppKit -framework CoreServices -framework Security \
    -framework CFNetwork -framework CoreFoundation -framework CoreLocation -framework CoreSpotlight \
    -framework IMCore -framework IMSharedUtilities -framework IMDPersistence -framework IDS -framework FMF \
    -install_name @rpath/BlueBubblesHelper.dylib \
    "$src/BlueBubblesHelper.m" "$src/NetworkController.m" "$src/CTBlockDescription.m" \
    "$src/VettedAliasDictionary.m" "$src/ZKSwizzle/ZKSwizzle.m" "$pod/GCDAsyncSocket.m" \
    -o "$out/BlueBubblesHelper.dylib"
codesign --force --sign - "$out/BlueBubblesHelper.dylib"
codesign --verify --strict "$out/BlueBubblesHelper.dylib"
lipo -archs "$out/BlueBubblesHelper.dylib"
shasum -a 256 "$out/BlueBubblesHelper.dylib"
printf '%s\n' 'Build only; no installed helper changed and no process restarted.'

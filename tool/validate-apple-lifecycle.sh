#!/bin/bash
set -euo pipefail
platform="$1"
flutter precache --"$platform"
flutter_root="$(dirname "$(dirname "$(command -v flutter)")")"
engine="$flutter_root/bin/cache/artifacts/engine"
if [[ "$platform" == ios ]]; then
  sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
  target=arm64-apple-ios15.0
  framework="$(find "$engine/ios-release" -path '*/ios-arm64/Flutter.framework' -type d | head -1)"
else
  sdk="$(xcrun --sdk macosx --show-sdk-path)"
  target=arm64-apple-macos13.0
  framework="$(find "$engine" -path '*darwin*release*' -name FlutterMacOS.framework -type d | head -1)"
fi
[[ -d "$framework" ]] || { echo 'Flutter framework not found'; exit 1; }
mkdir -p build/native-sdk
make -C native-source/media_kit_video/common/darwin HEADERS_DESTDIR="$PWD/build/native-sdk/Headers"
cat > build/native-sdk/bridging.h <<'HEADER'
#include "mpv/client.h"
#include "mpv/render.h"
#include "mpv/render_gl.h"
HEADER
common="$PWD/native-source/media_kit_video/common/darwin/Classes/plugin"
plugin="$PWD/native-source/media_kit_video/$platform/media_kit_video/Sources/media_kit_video/plugin"
sources=("$common"/*.swift "$plugin/TextureHW.swift")
if [[ "$platform" == ios ]]; then
  sources+=("$plugin/gles"/*.swift)
else
  sources+=("$plugin/gl"/*.swift "$plugin/Utils.swift")
fi
xcrun swiftc -sdk "$sdk" -target "$target" -swift-version 5 -O \
  -F "$(dirname "$framework")" -I "$PWD/build/native-sdk/Headers" \
  -import-objc-header "$PWD/build/native-sdk/bridging.h" \
  -emit-object -whole-module-optimization -module-name media_kit_video \
  -o "build/native-sdk/renderer-$platform.o" "${sources[@]}"
file "build/native-sdk/renderer-$platform.o"
echo "Compiled $platform renderer with actual Apple SDK and Flutter 3.47.6 framework"

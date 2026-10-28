#!/usr/bin/env bash
# Exercise the production packaging step without Xcode or an FFmpeg build.
set -euo pipefail
package_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
work="$(mktemp -d -t bilisail-framework-test.XXXXXX)"
work="$(cd "$work" && pwd -P)"
trap 'rm -rf -- "$work"' EXIT
fixture="$work/package with spaces"
mkdir -p "$fixture/tool"
cp "$package_dir/tool/package-apple-framework.sh" "$fixture/tool/"

for target in ios-arm64 macos-arm64 macos-x64; do
  platform="${target%-*}"
  prebuilt="$fixture/native/prebuilt/$target"
  mkdir -p "$prebuilt/BiliMux.framework"
  printf '%s binary\n' "$target" > "$prebuilt/BiliMux.framework/BiliMux"
  info="$package_dir/native/Info.plist"
  if [[ "$platform" == ios ]]; then info="$package_dir/native/Info.ios.plist"; fi
  cp "$info" "$prebuilt/BiliMux.framework/Info.plist"
  for record in COPYING.LGPLv2.1 source.txt configure.log; do
    printf '%s %s\n' "$target" "$record" > "$prebuilt/$record"
  done
  framework="$fixture/$platform/Frameworks/BiliMux.framework"
  # Reproduce the old output, then rebuild twice to cover retained build dirs.
  mkdir -p "$framework/Resources" "$framework/_CodeSignature"
  printf 'stale\n' > "$framework/Resources/configure.log"
  printf 'stale\n' > "$framework/_CodeSignature/CodeResources"
  for attempt in 1 2; do
    bash "$fixture/tool/package-apple-framework.sh" "$target"
    cmp "$prebuilt/BiliMux.framework/BiliMux" "$framework/BiliMux"
    cmp "$info" "$framework/Info.plist"
    [[ ! -e "$framework/_CodeSignature" && ! -e "$framework/Versions" ]]
    resources="$framework/Resources"
    if [[ "$platform" == ios ]]; then
      [[ ! -e "$resources" ]]
      resources="$framework"
    fi
    for record in COPYING.LGPLv2.1 source.txt configure.log; do
      cmp "$prebuilt/$record" "$resources/$record"
    done
    [[ "$(find "$framework" -type f | wc -l | tr -d ' ')" == 5 ]]
  done
done
echo 'Apple framework packaging checks passed (iOS arm64, macOS arm64/x64, rebuild twice).'

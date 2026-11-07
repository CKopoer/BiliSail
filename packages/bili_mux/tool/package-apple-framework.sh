#!/usr/bin/env bash
set -euo pipefail
target="${1:?usage: package-apple-framework.sh ios-arm64|macos-arm64|macos-x64}"
case "$target" in
  ios-arm64) apple_platform=ios ;;
  macos-arm64|macos-x64) apple_platform=macos ;;
  *) echo "Unsupported Apple framework target: $target" >&2; exit 1 ;;
esac
package_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
prebuilt="$package_dir/native/prebuilt/$target"
pod_parent="$package_dir/$apple_platform/Frameworks"
mkdir -p "$pod_parent"
# Only replace this package's generated framework, including stale Resources
# and signatures from an earlier build. Do not follow a redirected parent.
[[ "$(cd "$pod_parent" && pwd -P)" == "$pod_parent" ]] || {
  echo 'Apple framework output must stay inside the package' >&2; exit 1;
}
pod_framework="$pod_parent/BiliMux.framework"
rm -rf -- "$pod_framework"
binary_dir="$pod_framework"
resources="$pod_framework"
if [[ "$apple_platform" == macos ]]; then
  # macOS uses versioned frameworks; Xcode rejects a root-level Info.plist.
  binary_dir="$pod_framework/Versions/A"
  resources="$binary_dir/Resources"
  mkdir -p "$binary_dir"
  ln -s A "$pod_framework/Versions/Current"
  ln -s Versions/Current/BiliMux "$pod_framework/BiliMux"
  ln -s Versions/Current/Resources "$pod_framework/Resources"
fi
# iOS keeps its shallow bundle, with the plist and records beside the binary.
mkdir -p "$resources"
cp "$prebuilt/BiliMux.framework/BiliMux" "$binary_dir/BiliMux"
cp "$prebuilt/BiliMux.framework/Info.plist" "$resources/Info.plist"
for record in COPYING.LGPLv2.1 source.txt configure.log; do
  cp "$prebuilt/$record" "$resources/$record"
done

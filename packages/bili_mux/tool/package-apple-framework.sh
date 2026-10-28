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
mkdir -p "$pod_framework"
cp "$prebuilt/BiliMux.framework/BiliMux" "$pod_framework/BiliMux"
cp "$prebuilt/BiliMux.framework/Info.plist" "$pod_framework/Info.plist"
resources="$pod_framework/Resources"
# iOS frameworks are flat. A Resources directory selects the macOS bundle
# layout, whose Info.plist lookup does not use our root-level iOS plist.
if [[ "$apple_platform" == ios ]]; then resources="$pod_framework"; fi
mkdir -p "$resources"
for record in COPYING.LGPLv2.1 source.txt configure.log; do
  cp "$prebuilt/$record" "$resources/$record"
done

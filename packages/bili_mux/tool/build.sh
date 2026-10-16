#!/usr/bin/env bash
set -euo pipefail
make_tool=make
if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == mingw* ]]; then
  export PATH="/ucrt64/bin:/usr/bin:$PATH"
  # FFmpeg Makefiles contain MSYS paths; native Windows make cannot read them.
  make_tool=/usr/bin/make
  [[ -x "$make_tool" ]] || { echo 'Install the MSYS2 make package in this MSYS root' >&2; exit 1; }
fi

target="${1:?usage: build.sh windows-x64|android-arm64|macos-arm64|linux-x64}"
package_dir="$(cd "$(dirname "$0")/.." && pwd)"
repo_dir="$(cd "$package_dir/../.." && pwd)"
cache="$repo_dir/build/download_mux"
version=n9.0.2
archive_sha=6e374ed621e48faa40639307dff48ba6fe574a509977956d2cce9669b7cc27e9

cc=cc
cxx=c++
strip_tool=strip
link_flags=()
configure_flags=()
cxx_flags=()
output_name=libbili_mux.so
case "$target" in
  windows-x64)
    export PATH="/ucrt64/bin:/usr/bin:$PATH"
    cc=gcc
    cxx=g++
    configure_flags+=(--target-os=mingw32 --arch=x86_64 --cc=gcc)
    link_flags+=(-static -Wl,--exclude-all-symbols)
    output_name=bili_mux.dll
    ;;
  android-arm64)
    ndk="${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to NDK 28.2.13676358}"
    # Convert paths only at the shell boundary on a Windows host.
    if command -v cygpath >/dev/null; then ndk="$(cygpath -u "$ndk")"; fi
    case "$(uname -s)" in
      Linux*) host=linux-x86_64 ;;
      Darwin*) host=darwin-x86_64 ;;
      MSYS*|MINGW*) host=windows-x86_64 ;;
      *) echo 'Unsupported NDK host' >&2; exit 1 ;;
    esac
    toolchain="$ndk/toolchains/llvm/prebuilt/$host/bin"
    export PATH="$toolchain:$PATH"
    cc="$toolchain/clang"
    cxx="$toolchain/clang++"
    strip_tool="$toolchain/llvm-strip"
    android_flags="--target=aarch64-linux-android24 --sysroot=$ndk/toolchains/llvm/prebuilt/$host/sysroot"
    configure_flags+=(--target-os=android --arch=aarch64 --enable-cross-compile
      --disable-mediacodec --disable-jni
      "--cc=$cc" "--cxx=$cxx" "--ar=$toolchain/llvm-ar" "--ranlib=$toolchain/llvm-ranlib"
      "--extra-cflags=$android_flags" "--extra-ldflags=$android_flags")
    cxx_flags+=(--target=aarch64-linux-android24 "--sysroot=$ndk/toolchains/llvm/prebuilt/$host/sysroot")
    # 16 KiB page alignment is required on recent Android devices.
    link_flags+=(-static-libstdc++ -Wl,-z,max-page-size=16384
      "-Wl,--version-script=$package_dir/native/exports.map" -Wl,-Bsymbolic)
    ;;
  macos-arm64)
    [[ "$(uname -s)" == Darwin ]] || { echo 'macOS requires an Xcode host' >&2; exit 1; }
    cc="$(xcrun -f clang)"
    cxx="$(xcrun -f clang++)"
    strip_tool="$(xcrun -f strip)"
    macos_sdk="$(xcrun --sdk macosx --show-sdk-path)"
    configure_flags+=(--target-os=darwin --arch=aarch64 --enable-cross-compile
      "--cc=$cc" "--sysroot=$macos_sdk"
      "--extra-cflags=-arch arm64 -mmacosx-version-min=12.0"
      "--extra-ldflags=-arch arm64 -mmacosx-version-min=12.0")
    # Direct Xcode compiler paths need an explicit SDK for headers and libSystem.
    # Keep this array populated for macOS Bash 3.2 with nounset enabled.
    cxx_flags+=(-arch arm64 -mmacosx-version-min=12.0 -isysroot "$macos_sdk")
    link_flags+=(
      -Wl,-install_name,@rpath/BiliMux.framework/BiliMux
      "-Wl,-exported_symbols_list,$package_dir/native/exports.macos")
    output_name=BiliMux
    ;;
  linux-x64)
    configure_flags+=(--target-os=linux --arch=x86_64)
    link_flags+=("-Wl,--version-script=$package_dir/native/exports.map" -Wl,-Bsymbolic)
    ;;
  *) echo "Unsupported target: $target" >&2; exit 1 ;;
esac


# Cache only relocatable final outputs. Never restore CMake/FFmpeg object trees.
hash_file() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d ' ' -f 1
  else shasum -a 256 "$1" | cut -d ' ' -f 1; fi
}
fingerprint() {
  printf '%s\n' "$target" "$archive_sha" "${ImageOS:-}" "${ImageVersion:-}" "$(uname -sm)"
  for file in "$package_dir"/native/* "$package_dir"/tool/*.sh "$repo_dir/tool/build-download-mux.ps1"; do
    [[ ! -f "$file" ]] || hash_file "$file"
  done
  "$cc" --version
  "$cxx" --version
  "$strip_tool" --version 2>/dev/null || true
  "$make_tool" --version
  # MSYS runtime/CRT/header packages can change without a GCC version change.
  if [[ "$target" == windows-x64 ]]; then /usr/bin/pacman -Q; fi
  if [[ "$target" == android-arm64 ]]; then cat "$ndk/source.properties"; fi
  if [[ "$target" == macos-arm64 ]]; then
    xcodebuild -version
    xcrun --sdk macosx --show-sdk-version
    xcrun --sdk macosx --show-sdk-build-version
  fi
  printf '%s\n' "${CFLAGS:-}" "${CXXFLAGS:-}" "${LDFLAGS:-}" "${SDKROOT:-}" "${MACOSX_DEPLOYMENT_TARGET:-}"
}
key_file="$(mktemp)"
fingerprint > "$key_file"
cache_key="$(hash_file "$key_file")"
rm -f "$key_file"
if [[ "${2:-}" == --cache-key ]]; then
  echo "key=mux-v1-$target-$cache_key"
  exit 0
fi
SECONDS=0
trap 'echo "[timing] mux total: ${SECONDS}s"' EXIT

mkdir -p "$cache/source" "$cache/$target" "$package_dir/native/prebuilt/$target"
archive="$cache/$version.tar.gz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 --connect-timeout 30 --max-time 600 \
    "https://codeload.github.com/FFmpeg/FFmpeg/tar.gz/refs/tags/$version" \
    --output "$archive.tmp"
  mv "$archive.tmp" "$archive"
fi
if command -v sha256sum >/dev/null; then
  actual_sha="$(sha256sum "$archive" | cut -d ' ' -f 1)"
else
  actual_sha="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
fi
[[ "$actual_sha" == "$archive_sha" ]] || { echo 'FFmpeg source hash mismatch' >&2; exit 1; }



output_dir="$package_dir/native/prebuilt/$target"
entry="$cache/cache/$target/$cache_key"
required=(configure.log COPYING.LGPLv2.1 source.txt)
if [[ "$target" == macos-arm64 ]]; then
  required+=(BiliMux.framework/BiliMux BiliMux.framework/Info.plist)
else
  required+=("$output_name")
fi
if [[ "$target" == windows-x64 ]]; then
  required+=(bili_mux.LGPL.txt bili_mux.source.txt bili_mux.configuration.txt)
fi
valid=true
for file in "${required[@]}"; do
  if [[ ! -s "$entry/$file" || ! -f "$entry/$file.sha256" ]] ||
     [[ "$(hash_file "$entry/$file")" != "$(cat "$entry/$file.sha256")" ]]; then valid=false; break; fi
done
if $valid; then
  echo "[cache] mux verified hit: $cache_key"
  for file in "${required[@]}"; do
    mkdir -p "$output_dir/$(dirname "$file")"
    cp "$entry/$file" "$output_dir/$file"
  done
  if [[ "$target" == macos-arm64 ]]; then
    pod_framework="$package_dir/macos/Frameworks/BiliMux.framework"
    mkdir -p "$pod_framework/Resources"
    cp "$output_dir/BiliMux.framework/"* "$pod_framework/"
    cp "$output_dir/"{COPYING.LGPLv2.1,source.txt,configure.log} "$pod_framework/Resources/"
  fi
  exit 0
fi
echo "[cache] mux miss or invalid entry: $cache_key; rebuilding"
# A changed fingerprint must not reuse stale configure/object/source files.
rm -rf "$cache/$target" "$cache/source"
mkdir -p "$cache/$target" "$cache/source"
tar -xf "$archive" -C "$cache/source" --strip-components=1
stage_start=$SECONDS

cd "$cache/$target"
# Library-only build: no ffmpeg command-line front end or filter/resample libs.
"$cache/source/configure" \
  --disable-everything --disable-autodetect --disable-network \
  --disable-programs --disable-doc --disable-debug --disable-x86asm \
  --disable-avdevice --disable-avfilter --disable-swresample --disable-swscale \
  --enable-static --disable-shared --enable-pic --enable-small \
  --enable-demuxer=mov,matroska --enable-muxer=mp4,matroska --enable-protocol=file \
  --enable-parser=aac,h264,hevc,av1 \
  --enable-bsf=aac_adtstoasc,extract_extradata \
  --extra-cflags='-Os -fvisibility=hidden -ffunction-sections -fdata-sections' \
  "${configure_flags[@]}" > configure.log 2>&1
echo "[timing] mux configure: $((SECONDS-stage_start))s"
stage_start=$SECONDS
"$make_tool" -j"${BILI_MUX_JOBS:-4}" > build.log 2>&1

echo "[timing] mux compile: $((SECONDS-stage_start))s"
stage_start=$SECONDS
gc_flag=-Wl,--gc-sections
shared_flag=-shared
if [[ "$target" == macos-arm64 ]]; then gc_flag=-Wl,-dead_strip; shared_flag=-dynamiclib; fi
"$cxx" -std=c++17 -O2 -fvisibility=hidden -ffunction-sections -fdata-sections \
  -fPIC "$shared_flag" "${cxx_flags[@]}" "$package_dir/native/bili_mux.cpp" \
  -I"$cache/source" -I. \
  libavformat/libavformat.a libavcodec/libavcodec.a libavutil/libavutil.a \
  -o "$output_name" "$gc_flag" "${link_flags[@]}" \
  $(sed -n 's/^EXTRALIBS-avformat=//p;s/^EXTRALIBS-avcodec=//p;s/^EXTRALIBS-avutil=//p' ffbuild/config.mak) \
  > link.log 2>&1

if [[ "$target" == macos-arm64 ]]; then
  "$strip_tool" -x "$output_name"
  framework="$package_dir/native/prebuilt/macos-arm64/BiliMux.framework"
  mkdir -p "$framework"
  cp "$output_name" "$framework/BiliMux"
  cp "$package_dir/native/Info.plist" "$framework/Info.plist"
else
  "$strip_tool" --strip-unneeded "$output_name"
  cp "$output_name" "$package_dir/native/prebuilt/$target/$output_name"
fi
cp configure.log "$package_dir/native/prebuilt/$target/configure.log"
cp "$cache/source/COPYING.LGPLv2.1" "$package_dir/native/prebuilt/$target/COPYING.LGPLv2.1"
echo "$version $archive_sha" > "$package_dir/native/prebuilt/$target/source.txt"
if [[ "$target" == windows-x64 ]]; then
  cp "$package_dir/native/prebuilt/$target/COPYING.LGPLv2.1" "$package_dir/native/prebuilt/$target/bili_mux.LGPL.txt"
  cp "$package_dir/native/prebuilt/$target/source.txt" "$package_dir/native/prebuilt/$target/bili_mux.source.txt"
  cp "$package_dir/native/prebuilt/$target/configure.log" "$package_dir/native/prebuilt/$target/bili_mux.configuration.txt"
fi
if [[ "$target" == macos-arm64 ]]; then
  pod_framework="$package_dir/macos/Frameworks/BiliMux.framework"
  mkdir -p "$pod_framework/Resources"
  cp "$output_name" "$pod_framework/BiliMux"
  cp "$package_dir/native/Info.plist" "$pod_framework/Info.plist"
  cp "$package_dir/native/prebuilt/$target/COPYING.LGPLv2.1" "$pod_framework/Resources/"
  cp "$package_dir/native/prebuilt/$target/source.txt" "$pod_framework/Resources/"
  cp "$package_dir/native/prebuilt/$target/configure.log" "$pod_framework/Resources/"
fi
echo "Built $target: $output_name"

echo "[timing] mux link and stage: $((SECONDS-stage_start))s"
rm -rf "$entry"
mkdir -p "$entry"
for file in "${required[@]}"; do
  [[ -s "$output_dir/$file" ]] || { echo "Missing mux output: $file" >&2; exit 1; }
  mkdir -p "$entry/$(dirname "$file")"
  cp "$output_dir/$file" "$entry/$file"
  hash_file "$entry/$file" > "$entry/$file.sha256"
done

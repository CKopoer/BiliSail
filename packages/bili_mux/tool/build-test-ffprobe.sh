#!/usr/bin/env bash
set -euo pipefail

[[ "$(uname -s)" == Linux ]] || { echo 'The test probe requires a Linux host.' >&2; exit 1; }
package_dir="$(cd "$(dirname "$0")/.." && pwd)"
repo_dir="$(cd "$package_dir/../.." && pwd)"
cache="$repo_dir/build/download_mux"
source_record="$package_dir/native/prebuilt/linux-x64/source.txt"
[[ -f "$cache/source/configure" && -f "$source_record" ]] || {
  echo 'Run build.sh linux-x64 first to verify and prepare the pinned FFmpeg source.' >&2
  exit 1
}

# The oracle uses the same verified source as the component. It stays in the
# test build directory and is never included in application assets.
build_dir="$cache/test-ffprobe-linux-x64"
mkdir -p "$build_dir"
cd "$build_dir"
"$cache/source/configure" \
  --disable-everything --disable-autodetect --disable-network \
  --disable-doc --disable-debug --disable-x86asm \
  --disable-ffmpeg --disable-ffplay --enable-ffprobe \
  --disable-avdevice --disable-avfilter --disable-swresample --disable-swscale \
  --enable-static --disable-shared \
  --enable-demuxer=mov --enable-protocol=file \
  --enable-parser=aac,h264,hevc,av1 > configure.log 2>&1
expected_version="$(cut -d ' ' -f 1 "$source_record")"
# An extracted source tree inside this checkout otherwise inherits the app's
# Git description instead of the FFmpeg release revision.
make -j"${BILI_MUX_JOBS:-4}" REVISION="${expected_version#n}" ffprobe > build.log 2>&1
./ffprobe -version > version.txt
grep -Fq "ffprobe version ${expected_version#n} " version.txt || {
  echo 'The test probe does not match the component source version.' >&2
  exit 1
}
sed -n '1p' version.txt

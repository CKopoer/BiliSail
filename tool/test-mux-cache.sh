#!/usr/bin/env bash
# Run on a Linux build host. Uses an isolated checkout subset, not user outputs.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/packages/bili_mux" "$work/tool"
cp -R "$repo/packages/bili_mux/native" "$repo/packages/bili_mux/tool" "$work/packages/bili_mux/"
cp "$repo/tool/build-download-mux.ps1" "$work/tool/"
script="$work/packages/bili_mux/tool/build.sh"
key="$(bash "$script" linux-x64 --cache-key)"
changed="$(CFLAGS=-DBILI_CACHE_TEST bash "$script" linux-x64 --cache-key)"
[[ "$key" != "$changed" ]]
printf '\n// cache invalidation test\n' >> "$work/packages/bili_mux/native/bili_mux.cpp"
[[ "$key" != "$(bash "$script" linux-x64 --cache-key)" ]]
bash "$script" linux-x64 | tee "$work/cold.log"
grep -q 'mux miss or invalid' "$work/cold.log"
bash "$script" linux-x64 | tee "$work/hot.log"
grep -q 'mux verified hit' "$work/hot.log"
# Corruption must fail SHA verification, then rebuild successfully.
entry=("$work"/build/download_mux/cache/linux-x64/*)
printf 'corrupt' > "${entry[0]}/libbili_mux.so"
bash "$script" linux-x64 | tee "$work/repair.log"
grep -q 'mux miss or invalid' "$work/repair.log"
rm "${entry[0]}/configure.log"
bash "$script" linux-x64 | tee "$work/missing.log"
grep -q 'mux miss or invalid' "$work/missing.log"
bash "$script" linux-x64 | tee "$work/repaired-hot.log"
grep -q 'mux verified hit' "$work/repaired-hot.log"
echo 'Mux cache checks passed: source/options invalidation, cold/hot, corruption/missing recovery.'

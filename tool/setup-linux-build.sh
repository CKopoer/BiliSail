#!/usr/bin/env bash
# Download caches do not replace apt's package verification or Flatpak updates.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -sm)" != 'Linux x86_64' ]] ||
   ! grep -Eq '^ID="?ubuntu"?$' /etc/os-release ||
   ! grep -Eq '^VERSION_ID="?24\.04"?$' /etc/os-release; then
  echo 'Linux packaging dependencies require Ubuntu 24.04 x64' >&2
  exit 1
fi
cache_root="${BILISAIL_LINUX_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bilisail/linux}"
mkdir -p "$cache_root/apt"
# GitHub's mirrorlist prefers Azure. A responding but very slow mirror need
# not hit APT's inactivity timeout, so prefer the official primary archive.
if [[ "${GITHUB_ACTIONS:-}" == true && -f /etc/apt/apt-mirrors.txt ]]; then
  sudo python3 "$repo/tool/linux-apt-mirrors.py" /etc/apt/apt-mirrors.txt
fi

run_stage() {
  local label="$1" started=$SECONDS result=0
  shift
  printf '::group::%s\n' "$label"
  "$@" || result=$?
  printf '%s finished in %ss (exit %s)\n' "$label" "$((SECONDS - started))" "$result"
  echo '::endgroup::'
  return "$result"
}

apt_options=(-o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30)
run_stage 'APT index update' sudo apt-get "${apt_options[@]}" -o APT::Update::Error-Mode=any update
run_stage 'APT dependency install' sudo apt-get "${apt_options[@]}" -o "Dir::Cache::archives=$cache_root/apt" \
  -o APT::Keep-Downloaded-Packages=true install -y \
  clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libva-wayland2 \
  gobject-introspection libgirepository1.0-dev librsvg2-common glib-networking \
  patchelf desktop-file-utils flatpak flatpak-builder

flatpak_refs="$(python3 - "$repo/linux/packaging/dev.bilisail.bilisail.json" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
for field in ("runtime", "sdk"):
    print(f'{manifest[field]}//{manifest["runtime-version"]}')
PY
)"
mapfile -t refs <<< "$flatpak_refs"
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
run_stage 'Flatpak Runtime and SDK' flatpak install --user --or-update --assumeyes --noninteractive flathub "${refs[@]}"

# Fetch tools before the dependency-cache checkpoint, even if packaging later fails.
source "$repo/tool/linux-downloads.sh"
run_stage 'Pinned Linux packaging tools' prepare_linux_packaging_tools "$cache_root/tool-staging"

#!/usr/bin/env bash
# Run the output plugin bundled in the already hash-verified linuxdeploy image.
# AppDir population, RPATH repair and dependency validation happen beforehand.
build_appimage_from_appdir() (
  set -euo pipefail
  local image="$1" appdir="$2" tools="$3" plugin
  [[ ! -e "$tools" ]] || { echo "AppImage tools already exist: $tools" >&2; exit 1; }
  mkdir -p "$tools"
  if ! (cd "$tools" && "$image" --appimage-extract > extraction.log 2>&1); then
    cat "$tools/extraction.log" >&2
    return 1
  fi
  plugin="$tools/squashfs-root/plugins/linuxdeploy-plugin-appimage/usr/bin/linuxdeploy-plugin-appimage"
  [[ -x "$plugin" && -x "$(dirname "$plugin")/appimagetool" ]] || {
    echo 'The pinned linuxdeploy image is missing its AppImage output tools' >&2
    return 1
  }
  "$plugin" --appdir "$appdir"
)

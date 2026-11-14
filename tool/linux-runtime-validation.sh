#!/bin/sh
# Run inside the installed Flatpak Runtime, not the SDK or host.
set -eu
root=${1:-/app}
export LC_ALL=C
export LD_LIBRARY_PATH="$root/usr/bin/lib:$root/usr/lib"
[ -f "$root/usr/bin/bilisail" ] || {
  echo "Missing executable: $root/usr/bin/bilisail" >&2
  exit 1
}
webkit="$root/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1"
for component in WebKitWebProcess WebKitNetworkProcess injected-bundle/libwebkit2gtkinjectedbundle.so; do
  [ -s "$webkit/$component" ] || { echo "Missing WebKitGTK component: $component" >&2; exit 1; }
done
find "$root/usr" -type f \( -name '*.so*' -o -name 'WebKit*Process' -o -path "$root/usr/bin/bilisail" \) \
  -exec sh -c '
    failed=0
    for binary do
      # The glob also matches data such as org.gnome.desktop.sound.gschema.xml.
      # Match the host AppDir checker: only ELF files have loader dependencies.
      magic=$(head -c 4 "$binary") || {
        printf "Cannot read dependency candidate: %s\n" "$binary" >&2
        failed=1
        continue
      }
      if [ "$magic" != "$(printf "\177ELF")" ]; then
        case "$binary" in
          */usr/bin/bilisail|*/WebKit*Process)
            printf "Executable is not ELF: %s\n" "$binary" >&2
            failed=1 ;;
        esac
        continue
      fi
      status=0
      result=$(ldd "$binary" 2>&1) || status=$?
      if [ "$status" -ne 0 ] || printf "%s\n" "$result" | grep -q "not found"; then
        printf "Dependency check failed: %s (ldd exit %s)\n%s\n" \
          "$binary" "$status" "$result" >&2
        failed=1
      fi
    done
    exit "$failed"
  ' sh {} +
echo 'Installed Flatpak Runtime dependency checks passed.'

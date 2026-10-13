#!/bin/bash
# Explicit filename workaround. The payload remains Intel core103, not core105.
# Never replace an existing upstream c104/c105 file.
bm_wifi_compat_aliases() {
  local directory="$1" base="$2" version target="$2-c103.ucode" link
  [[ "$base" =~ ^iwlwifi-(gl-c0-fm-c0|bz-b0-fm-c0)$ ]] || {
    echo "Unsupported firmware family for the core103 filename workaround" >&2; return 1;
  }
  [ -s "$directory/$target" ] && [ ! -L "$directory/$target" ] || {
    echo "Missing genuine core103 payload: $target" >&2; return 1;
  }
  for version in 104 105; do
    link="$directory/$base-c$version.ucode"
    if [ -e "$link" ]; then continue; fi
    [ ! -L "$link" ] || { echo "Broken firmware alias: $link" >&2; return 1; }
    ln -s "$target" "$link" || return 1
    echo "COMPATIBILITY alias: $base-c$version.ucode -> $target (actual firmware remains core103)"
  done
}

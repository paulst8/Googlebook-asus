#!/bin/bash
# Shared read-only target checks. No disk changes here.
bm_partition_number() {
  local disk="$1" label="$2" override="${3:-}" row name partlabel number
  local -a matches=()
  while read -r name partlabel; do
    [ "$partlabel" = "$label" ] || continue
    number="${name##*p}"
    [[ "$number" =~ ^[0-9]+$ ]] || continue
    matches+=("$number")
  done < <(lsblk -ln -o NAME,PARTLABEL "$disk")
  [ "${#matches[@]}" -eq 1 ] || { echo "Expected one $label partition on $disk; found ${#matches[@]}" >&2; return 1; }
  [ -z "$override" ] || [ "$override" = "${matches[0]}" ] || { echo "USERDATA_PART does not match $label" >&2; return 1; }
  printf '%s\n' "${matches[0]}"
}

bm_require_ubuntu_disk() {
  local disk="$1" root rootdisk
  root=$(findmnt -nro SOURCE /) || return 1
  rootdisk=$(lsblk -dnro PKNAME "$root") || return 1
  [ -n "$rootdisk" ] && [ "$disk" = "/dev/$rootdisk" ] || {
    echo "Refusing: target must be the disk containing running Ubuntu (direct partition required)" >&2
    return 1
  }
}

bm_disk_by_serial() {
  local serial="$1" name found_serial transport
  local -a matches=()
  [ -n "$serial" ] || { echo "SSD serial is empty" >&2; return 1; }
  while read -r name found_serial transport; do
    [ "$found_serial" = "$serial" ] && [ "$transport" = nvme ] || continue
    matches+=("/dev/$name")
  done < <(lsblk -dnro NAME,SERIAL,TRAN)
  [ "${#matches[@]}" -eq 1 ] || { echo "Expected one NVMe disk with the configured serial; found ${#matches[@]}" >&2; return 1; }
  printf '%s\n' "${matches[0]}"
}

# Maintenance commands must keep /boot and EFI on the configured Ubuntu SSD.
bm_require_boot_host() {
  local disk root efi
  disk=$(bm_disk_by_serial "${SSD_SERIAL:-}") || return 1
  bm_require_ubuntu_disk "$disk" || return 1
  root=$(findmnt -nro SOURCE /) || return 1
  [ "$(findmnt -nro SOURCE -T /boot)" = "$root" ] || { echo 'Separate /boot is unsupported' >&2; return 1; }
  efi=$(findmnt -nro SOURCE /boot/efi) || return 1
  [ "/dev/$(lsblk -dnro PKNAME "$efi")" = "$disk" ] || { echo 'EFI is on another disk' >&2; return 1; }
  [ -f /etc/default/grub.d/99-googlebook.cfg ] &&
    grep -qx 'GRUB_DISABLE_OS_PROBER=true' /etc/default/grub.d/99-googlebook.cfg || {
      echo 'Run bm-ubuntu-grub.sh first to disable cross-disk OS probing' >&2; return 1;
    }
}

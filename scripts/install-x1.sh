#!/usr/bin/env bash
# Install the x1-9thgen NixOS configuration on a blank ThinkPad X1 Carbon.
#
# This script intentionally requires the disk as an argument and asks for an
# explicit confirmation before partitioning it. It must be run from a NixOS
# installer as root, with the repository stored outside /mnt.

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: install-x1.sh --disk DEVICE [--repo DIRECTORY] [--target DIRECTORY] [--yes]

Partition, format, and install the x1-9thgen configuration on DEVICE.

Options:
  --disk DEVICE       Whole internal disk, for example /dev/nvme0n1 (required)
  --repo DIRECTORY    Fleet checkout (default: repository containing this script)
  --target DIRECTORY  Temporary install mount point (default: /mnt)
  --yes               Skip typed confirmations (still requires --disk)
  -h, --help          Show this help
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

DISK=''
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TARGET='/mnt'
ASSUME_YES=0

while (($# > 0)); do
    case "$1" in
        --disk)
            (($# >= 2)) || die "--disk requires a device"
            DISK=$2
            shift 2
            ;;
        --repo)
            (($# >= 2)) || die "--repo requires a directory"
            REPO_DIR=$2
            shift 2
            ;;
        --target)
            (($# >= 2)) || die "--target requires a directory"
            TARGET=$2
            shift 2
            ;;
        --yes)
            ASSUME_YES=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1 (use --help for usage)"
            ;;
    esac
done

[[ -n "$DISK" ]] || die "--disk is required (use --help for usage)"
[[ $EUID -eq 0 ]] || die "run this script as root from a NixOS installer"
[[ -d /sys/firmware/efi ]] || die "the installer must be booted in UEFI mode"

REPO_DIR="$(cd -- "$REPO_DIR" && pwd -P)" \
    || die "repository directory does not exist: $REPO_DIR"
[[ -f "$REPO_DIR/flake.nix" ]] || die "not a fleet repository: $REPO_DIR"

mkdir -p -- "$TARGET"
TARGET="$(cd -- "$TARGET" && pwd -P)"
[[ "$REPO_DIR" != "$TARGET" && "$REPO_DIR" != "$TARGET"/* ]] \
    || die "the repository must be outside the install target ($TARGET)"

if mountpoint -q -- "$TARGET"; then
    die "install target is already mounted: $TARGET"
fi
if [[ -n "$(find "$TARGET" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    die "install target is not empty: $TARGET"
fi

DISK="$(readlink -f -- "$DISK")" || die "cannot resolve disk: $DISK"
[[ -b "$DISK" ]] || die "not a block device: $DISK"
[[ "$(lsblk -ndo TYPE -- "$DISK")" == 'disk' ]] \
    || die "--disk must identify a whole disk, not a partition: $DISK"
if lsblk -nrpo MOUNTPOINT -- "$DISK" | awk 'NF { found = 1 } END { exit found ? 0 : 1 }'; then
    die "a partition on $DISK is mounted; unmount it before continuing"
fi
[[ ! -e /dev/mapper/cryptroot ]] \
    || die '/dev/mapper/cryptroot already exists; close it before continuing'

case "$DISK" in
    /dev/nvme*|/dev/mmcblk*)
        EFI_PART="${DISK}p1"
        ROOT_PART="${DISK}p2"
        ;;
    *)
        EFI_PART="${DISK}1"
        ROOT_PART="${DISK}2"
        ;;
esac

for command in \
    awk btrfs cryptsetup find mount mountpoint mkfs.btrfs mkfs.fat \
    findmnt nix nixos-enter nixos-generate-config nixos-install parted \
    partprobe readlink umount udevadm; do
    command -v "$command" >/dev/null 2>&1 \
        || die "required command is not available: $command"
done

printf '\nThe following disk will be ERASED:\n\n'
lsblk -e7 -o NAME,TYPE,SIZE,FSTYPE,LABEL,UUID,MODEL,MOUNTPOINTS -- "$DISK"
printf '\nNew partitions: %s (EFI), %s (encrypted root)\n' "$EFI_PART" "$ROOT_PART"

if ((ASSUME_YES == 0)); then
    printf '\nThis destroys all data on %s. Type exactly "ERASE %s" to continue: ' \
        "$DISK" "$DISK"
    read -r confirmation
    [[ "$confirmation" == "ERASE $DISK" ]] \
        || die 'confirmation did not match; nothing was changed'
fi

# Keep the mapping and mounts private to this script. On any failure the trap
# unmounts the target and closes the mapping, leaving the disk installable.
GENERATED_DIR=''
cleanup() {
    local status=$?
    set +e
    if mountpoint -q -- "$TARGET"; then
        umount -R -- "$TARGET"
    fi
    if [[ -e /dev/mapper/cryptroot ]]; then
        cryptsetup close cryptroot
    fi
    if [[ -n "$GENERATED_DIR" && -d "$GENERATED_DIR" ]]; then
        rm -rf -- "$GENERATED_DIR"
    fi
    exit "$status"
}
trap cleanup EXIT

parted --script -- "$DISK" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 1GiB \
    set 1 esp on \
    mkpart primary 1GiB 100%
partprobe "$DISK"
udevadm settle
[[ -b "$EFI_PART" && -b "$ROOT_PART" ]] \
    || die "partition devices did not appear: $EFI_PART and $ROOT_PART"

mkfs.fat -F 32 -n EFI "$EFI_PART"
cryptsetup luksFormat --label NIXOS-LUKS "$ROOT_PART"
cryptsetup open "$ROOT_PART" cryptroot
mkfs.btrfs -L NIXOS /dev/mapper/cryptroot

mount /dev/mapper/cryptroot "$TARGET"
btrfs subvolume create "$TARGET/@"
btrfs subvolume create "$TARGET/@home"
btrfs subvolume create "$TARGET/@log"
btrfs subvolume create "$TARGET/@sync"
btrfs subvolume create "$TARGET/@swap"
umount "$TARGET"

mount -o subvol=@,compress=zstd,ssd /dev/mapper/cryptroot "$TARGET"
mkdir -p "$TARGET/home" "$TARGET/var/log" "$TARGET/boot"
mount -o subvol=@home,compress=zstd,ssd /dev/mapper/cryptroot "$TARGET/home"
mount -o subvol=@log,compress=zstd,ssd /dev/mapper/cryptroot "$TARGET/var/log"
mkdir -p "$TARGET/home/iindesa/Shared" "$TARGET/swap"
mount -o subvol=@sync,compress=zstd,ssd /dev/mapper/cryptroot "$TARGET/home/iindesa/Shared"
mount -o subvol=@swap,compress=zstd,ssd /dev/mapper/cryptroot "$TARGET/swap"
btrfs filesystem mkswapfile --size 32768M --uuid clear "$TARGET/swap/swapfile"
RESUME_OFFSET="$(btrfs inspect-internal map-swapfile -r "$TARGET/swap/swapfile")"
[[ "$RESUME_OFFSET" =~ ^[0-9]+$ ]] \
    || die "could not determine the Btrfs hibernation resume offset"
mount "$EFI_PART" "$TARGET/boot"

printf '\nCreated 32 GiB encrypted swapfile with resume offset: %s\n' "$RESUME_OFFSET"
printf '\nMounted target filesystem:\n'
findmnt -R "$TARGET"

GENERATED_DIR="$(mktemp -d /tmp/x1-hardware.XXXXXXXX)"
nixos-generate-config --root "$TARGET" --dir "$GENERATED_DIR"
cp -- "$GENERATED_DIR/hardware-configuration.nix" \
    "$REPO_DIR/hosts/x1-9thgen/hardware-configuration.nix"

HARDWARE_FILE="$REPO_DIR/hosts/x1-9thgen/hardware-configuration.nix"
sed -i '$d' "$HARDWARE_FILE"
cat >> "$HARDWARE_FILE" <<EOF

  # The swapfile was created during installation; this offset is specific to
  # this filesystem and is required for hibernation resume.
  boot.resumeDevice = "/dev/disk/by-label/NIXOS";
  boot.kernelParams = [ "resume_offset=$RESUME_OFFSET" ];
}
EOF

printf '\nGenerated hardware configuration:\n'
cat "$REPO_DIR/hosts/x1-9thgen/hardware-configuration.nix"

(
    cd -- "$REPO_DIR"
    nix flake check --no-write-lock-file
)

if ((ASSUME_YES == 0)); then
    printf '\nReview the generated hardware file above and in the repository.\n'
    printf 'Open another terminal to edit it if needed, then press Enter to install: '
    read -r
fi

nixos-install --root "$TARGET" --flake "${REPO_DIR}#x1-9thgen"

# Keep the checkout in the installed system for future nixos-rebuild commands.
mkdir -p "$TARGET/etc/nixos"
rm -rf -- "$TARGET/etc/nixos/fleet"
cp -a -- "$REPO_DIR" "$TARGET/etc/nixos/fleet"

printf '\nSet the password for the iindesa user before rebooting.\n'
nixos-enter --root "$TARGET" -c 'passwd iindesa'

sync
printf '\nInstallation complete. The target will be unmounted and cryptroot closed.\n'

#!/usr/bin/env bash
# Create or reuse an encrypted-Btrfs swapfile and record its resume offset.
# The target root and its /swap subvolume must already be mounted.

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: configure-btrfs-hibernation.sh --root TARGET --config FILE [--size MIB]

Create a Btrfs swapfile on TARGET/swap and add its machine-specific
resume_offset to a NixOS configuration file.

The root filesystem and the @swap subvolume must already be mounted at TARGET.
The default swapfile size is 32768 MiB (32 GiB).
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

ROOT=''
CONFIG=''
SIZE=32768

while (($# > 0)); do
    case "$1" in
        --root)
            (($# >= 2)) || die "--root requires a directory"
            ROOT=$2
            shift 2
            ;;
        --config)
            (($# >= 2)) || die "--config requires a Nix file"
            CONFIG=$2
            shift 2
            ;;
        --size)
            (($# >= 2)) || die "--size requires a size in MiB"
            SIZE=$2
            shift 2
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

[[ -n "$ROOT" ]] || die "--root is required"
[[ -n "$CONFIG" ]] || die "--config is required"
[[ -d "$ROOT" ]] || die "root directory does not exist: $ROOT"
[[ -f "$CONFIG" ]] || die "configuration file does not exist: $CONFIG"
[[ "$SIZE" =~ ^[1-9][0-9]*$ ]] || die "size must be a positive integer in MiB"

for command in btrfs findmnt sed; do
    command -v "$command" >/dev/null 2>&1 \
        || die "required command is not available: $command"
done

mountpoint() {
    findmnt -T "$1" -n >/dev/null 2>&1
}

mountpoint "$ROOT" || die "target root is not mounted: $ROOT"
mountpoint "$ROOT/swap" || die "the @swap subvolume must be mounted at: $ROOT/swap"

SWAPFILE="$ROOT/swap/swapfile"
if [[ ! -e "$SWAPFILE" ]]; then
    btrfs filesystem mkswapfile \
        --size "${SIZE}M" \
        --uuid clear \
        "$SWAPFILE"
fi

RESUME_OFFSET="$(btrfs inspect-internal map-swapfile -r "$SWAPFILE")"
[[ "$RESUME_OFFSET" =~ ^[0-9]+$ ]] \
    || die "could not determine the Btrfs hibernation resume offset"

if grep -q 'resume_offset=' "$CONFIG"; then
    sed -i -E \
        "s/resume_offset=[0-9]+/resume_offset=$RESUME_OFFSET/" \
        "$CONFIG"
else
    sed -i '$d' "$CONFIG"
    cat >> "$CONFIG" <<EOF

  # Generated from the physical Btrfs swapfile during provisioning.
  boot.kernelParams = [ "resume_offset=$RESUME_OFFSET" ];
}
EOF
fi

printf 'Swapfile:       %s\n' "$SWAPFILE"
printf 'Resume offset:  %s\n' "$RESUME_OFFSET"
printf 'Updated config: %s\n' "$CONFIG"

#!/usr/bin/env bash
# Create or reuse an encrypted-Btrfs swapfile and record its resume offset.
# The target root and its mounted /swap subvolume must already be verified.

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: configure-btrfs-hibernation.sh --root TARGET --config FILE [--size MIB]

Create a Btrfs swapfile on TARGET/swap and update the one-line
boot.kernelParams assignment in FILE with its machine-specific resume offset.

TARGET and TARGET/swap must both be exact Btrfs mount points. FILE should be
the host's dedicated resume-offset.nix module, not a generated hardware file.
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
            (($# >= 2)) || die '--root requires a directory'
            ROOT=$2
            shift 2
            ;;
        --config)
            (($# >= 2)) || die '--config requires a Nix file'
            CONFIG=$2
            shift 2
            ;;
        --size)
            (($# >= 2)) || die '--size requires a size in MiB'
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

[[ -n "$ROOT" ]] || die '--root is required'
[[ -n "$CONFIG" ]] || die '--config is required'
[[ "$ROOT" == /* && -d "$ROOT" ]] || die "root must be an existing absolute directory: $ROOT"
[[ -f "$CONFIG" ]] || die "configuration file does not exist: $CONFIG"
[[ "$SIZE" =~ ^[1-9][0-9]*$ ]] || die 'size must be a positive integer in MiB'

for command in btrfs findmnt grep sed cp mv mktemp; do
    command -v "$command" >/dev/null 2>&1 \
        || die "required command is not available: $command"
done

is_mountpoint() {
    findmnt --mountpoint "$1" --noheadings >/dev/null 2>&1
}

is_mountpoint "$ROOT" || die "target root is not an exact mount point: $ROOT"
is_mountpoint "$ROOT/swap" \
    || die "the @swap subvolume must be an exact mount point at: $ROOT/swap"
[[ "$(findmnt -n --mountpoint "$ROOT" --output FSTYPE)" == btrfs ]] \
    || die "target root is not mounted as Btrfs: $ROOT"
[[ "$(findmnt -n --mountpoint "$ROOT/swap" --output FSTYPE)" == btrfs ]] \
    || die "swap subvolume is not mounted as Btrfs: $ROOT/swap"

PARAM_PATTERN='^[[:space:]]*boot\.kernelParams[[:space:]]*=[[:space:]]*\[[^]]*\];[[:space:]]*(#.*)?$'
grep -Eq "$PARAM_PATTERN" "$CONFIG" \
    || die 'config must contain a one-line boot.kernelParams = [ ... ]; assignment'

SWAPFILE="$ROOT/swap/swapfile"
if [[ ! -e "$SWAPFILE" ]]; then
    btrfs filesystem mkswapfile \
        --size "${SIZE}M" \
        --uuid clear \
        "$SWAPFILE"
fi

RESUME_OFFSET="$(btrfs inspect-internal map-swapfile -r "$SWAPFILE")"
[[ "$RESUME_OFFSET" =~ ^[0-9]+$ ]] \
    || die 'could not determine the Btrfs hibernation resume offset'

CONFIG_TMP=$(mktemp "${CONFIG}.XXXXXX")
trap 'rm -f -- "$CONFIG_TMP"' EXIT
cp -p -- "$CONFIG" "$CONFIG_TMP"
sed -i -E \
    "s|^([[:space:]]*)boot\\.kernelParams[[:space:]]*=.*$|\\1boot.kernelParams = [ \\\"resume_offset=$RESUME_OFFSET\\\" ];|" \
    "$CONFIG_TMP"
grep -Fq "boot.kernelParams = [ \"resume_offset=$RESUME_OFFSET\" ];" "$CONFIG_TMP" \
    || die 'failed to update the resume-offset module'
mv -- "$CONFIG_TMP" "$CONFIG"
trap - EXIT

printf 'Swapfile:       %s\n' "$SWAPFILE"
printf 'Resume offset:  %s\n' "$RESUME_OFFSET"
printf 'Updated config: %s\n' "$CONFIG"

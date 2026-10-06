#!/usr/bin/env bash
# Install a fleet host with nixos-anywhere and the shared Disko layout.
# This formats the configured disk; do not run without an independently
# verified backup and an explicit decision to replace the current installation.

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: install-host.sh --host HOST --target-host USER@ADDRESS --identity-file FILE

Install a registered HOST over SSH with nixos-anywhere. HOST must have a
<HOST>-install flake output, a host configuration, and a resume-offset module.
Disko erases the configured disk. The script requires an SSH key already
authorized on the target and root access or passwordless sudo. Normal-user
passwords are discovered from the selected NixOS configuration and entered
interactively after installation. No passwords or private keys are stored in
the repository.

The destructive installer runs only after an interactive preflight. The script
prints the resolved disk and requires the exact confirmation:
  ERASE HOST USER@ADDRESS /dev/DEVICE
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

HOST=''
TARGET=''
IDENTITY=''

while (($# > 0)); do
    case "$1" in
        --host)
            (($# >= 2)) || die '--host requires a value'
            HOST=$2
            shift 2
            ;;
        --target-host)
            (($# >= 2)) || die '--target-host requires USER@ADDRESS'
            TARGET=$2
            shift 2
            ;;
        --identity-file|-i)
            (($# >= 2)) || die '--identity-file requires a path'
            IDENTITY=$2
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

[[ -t 0 ]] || die 'run this installer from an interactive terminal'
[[ "$HOST" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] \
    || die '--host must be a lowercase host name (letters, numbers, and hyphens)'
INSTALL_CONFIG="${HOST}-install"
[[ "$TARGET" == *@* && "$TARGET" != *@ && "$TARGET" != @* ]] \
    || die '--target-host must be in USER@ADDRESS form'
[[ -n "$IDENTITY" ]] || die '--identity-file is required for the multi-stage install'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel) \
    || die 'could not find the fleet Git repository'
cd "$REPO_ROOT"

IDENTITY=$(realpath -- "$IDENTITY") || die "identity file not found: $IDENTITY"
[[ -f "$IDENTITY" && -r "$IDENTITY" ]] || die "identity file is not readable: $IDENTITY"
case "$IDENTITY" in
    "$REPO_ROOT"/*) die 'keep private identity files outside the repository' ;;
esac

for path in flake.nix flake.lock modules/disko-layout.nix modules/storage.nix \
    modules/restic-backup.nix scripts/install-host.sh "hosts/$HOST/configuration.nix" \
    "hosts/$HOST/resume-offset.nix"; do
    git ls-files --error-unmatch "$path" >/dev/null 2>&1 \
        || die "$path must be tracked by Git before installing with this flake"
done

for command in git jq nix ssh realpath; do
    command -v "$command" >/dev/null 2>&1 || die "required command is unavailable: $command"
done

DISK=$(nix eval --raw ".#nixosConfigurations.$INSTALL_CONFIG.config.disko.devices.disk.main.device") \
    || die "could not evaluate the Disko device for $HOST"
[[ "$DISK" =~ ^/dev/[A-Za-z0-9._/+:-]+$ ]] || die "unexpected Disko device path: $DISK"

TARGET_USER=${TARGET%%@*}
TARGET_ADDRESS=${TARGET#*@}
[[ -n "$TARGET_USER" && -n "$TARGET_ADDRESS" ]] || die 'invalid target host'

printf 'Target:       %s\n' "$TARGET"
printf 'Host config:  %s\n' "$HOST"
printf 'Disk to erase: %s\n\n' "$DISK"
printf 'The target currently reports this block device:\n'
ssh -o BatchMode=yes -i "$IDENTITY" -o IdentitiesOnly=yes "$TARGET" \
    "if [ \"\$(id -u)\" -eq 0 ]; then test -b '$DISK' && lsblk -dn -o NAME,SIZE,MODEL '$DISK'; else sudo -n test -b '$DISK' && sudo -n lsblk -dn -o NAME,SIZE,MODEL '$DISK'; fi" \
    || die 'SSH key access, the target disk, or root/passwordless-sudo access failed'

printf '\nPreflight: evaluating the flake and building the installer and system closures...\n'
nix flake check --no-write-lock-file
nix build --no-link ".#nixosConfigurations.$INSTALL_CONFIG.config.system.build.diskoScript"
nix build --no-link ".#nixosConfigurations.$INSTALL_CONFIG.config.system.build.toplevel"

# The Nix expression is intentionally single-quoted to prevent shell expansion.
# shellcheck disable=SC2016
NORMAL_USERS_JSON=$(nix eval --json --no-write-lock-file \
    --apply 'users: builtins.filter (name: (users.${name}.isNormalUser or false)) (builtins.attrNames users)' \
    ".#nixosConfigurations.$INSTALL_CONFIG.config.users.users") \
    || die "could not discover normal users for $HOST"
NORMAL_USERS=$(jq -er '.[] | strings' <<<"$NORMAL_USERS_JSON") \
    || die "no normal users were found for $HOST"
mapfile -t INITIAL_USERS <<<"$NORMAL_USERS"
for user in "${INITIAL_USERS[@]}"; do
    [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]] \
        || die "unexpected normal-user name in $HOST configuration: $user"
done

EXPECTED="ERASE $HOST $TARGET $DISK"
printf '\nWARNING: nixos-anywhere will erase every partition and all data on %s.\n' "$DISK" >&2
printf 'This includes existing operating systems, home directories, Timeshift snapshots, and local backups.\n' >&2
printf 'Type exactly: %s\n> ' "$EXPECTED" >&2
IFS= read -r CONFIRM
[[ "$CONFIRM" == "$EXPECTED" ]] || die 'confirmation did not match; nothing was installed'

NIXOS_ANYWHERE=(nix run .#nixos-anywhere --)
ssh_kexec_options=(
    -o UserKnownHostsFile=/dev/null
    -o StrictHostKeyChecking=no
    -o IdentitiesOnly=yes
    -i "$IDENTITY"
)

printf '\nStarting kexec and Disko formatting for %s...\n' "$HOST"
"${NIXOS_ANYWHERE[@]}" \
    --flake ".#$INSTALL_CONFIG" \
    --target-host "$TARGET" \
    -i "$IDENTITY" \
    --build-on local \
    --phases kexec,disko \
    --disko-mode disko

INSTALLER_TARGET="root@$TARGET_ADDRESS"
printf '\nReading the new Btrfs swapfile resume offset from the installer...\n'
RESUME_OFFSET=$(ssh "${ssh_kexec_options[@]}" "$INSTALLER_TARGET" \
    'btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile') \
    || die 'could not read the resume offset; the target is already formatted and remains in the installer'
[[ "$RESUME_OFFSET" =~ ^[0-9]+$ ]] \
    || die "installer returned an invalid resume offset: $RESUME_OFFSET"

OFFSET_FILE="$REPO_ROOT/hosts/$HOST/resume-offset.nix"
OFFSET_TMP=$(mktemp "$OFFSET_FILE.XXXXXX")
trap 'rm -f -- "$OFFSET_TMP"' EXIT
cat > "$OFFSET_TMP" <<EOF
{ ... }:

{
  # Generated from the physical Btrfs swapfile during nixos-anywhere setup.
  boot.kernelParams = [ "resume_offset=$RESUME_OFFSET" ];
}
EOF
chmod --reference="$OFFSET_FILE" "$OFFSET_TMP"
mv -- "$OFFSET_TMP" "$OFFSET_FILE"
trap - EXIT

printf 'Resume offset recorded in %s.\n' "${OFFSET_FILE#"$REPO_ROOT"/}"
printf 'Rechecking and building the final host configuration...\n'
nix flake check --no-write-lock-file
nix build --no-link ".#nixosConfigurations.$INSTALL_CONFIG.config.system.build.toplevel"

printf '\nInstalling the system without rebooting so account passwords can be set...\n'
"${NIXOS_ANYWHERE[@]}" \
    --flake ".#$INSTALL_CONFIG" \
    --target-host "$INSTALLER_TARGET" \
    -i "$IDENTITY" \
    --build-on local \
    --phases install

for user in "${INITIAL_USERS[@]}"; do
    printf '\nSet the initial password for %s (entered only on the target):\n' "$user"
    ssh -tt "${ssh_kexec_options[@]}" "$INSTALLER_TARGET" \
        "nixos-enter --root /mnt -c 'passwd $user'"
done

printf '\nRebooting into the installed system...\n'
"${NIXOS_ANYWHERE[@]}" \
    --flake ".#$INSTALL_CONFIG" \
    --target-host "$INSTALLER_TARGET" \
    -i "$IDENTITY" \
    --build-on local \
    --phases reboot

cat <<EOF

Installation completed for $HOST.
The NixOS configuration keeps root SSH disabled. Because a fresh installation
has no Tailscale state, use the local console to authenticate Tailscale before
expecting fleet SSH access. The generated resume offset is a local Git change
in hosts/$HOST/resume-offset.nix; retain it for this disk and commit it with the
configuration when appropriate.
EOF

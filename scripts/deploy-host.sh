#!/usr/bin/env bash
# Validate, remotely build, and activate one registered fleet host.

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: deploy-host.sh --host HOST [--target-user USER] [--repo DIRECTORY]

Validate the fleet flake, then build and activate HOST over SSH. The target is
also used as the build host. An interactive terminal is required for sudo.

Options:
  --host HOST          Active host name from the fleet registry (required)
  --target-user USER   Remote account (default: iindesa)
  --repo DIRECTORY    Fleet checkout (default: repository containing this script)
  -h, --help          Show this help
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

HOST=''
TARGET_USER='iindesa'
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

while (($# > 0)); do
    case "$1" in
        --host)
            (($# >= 2)) || die '--host requires a value'
            HOST=$2
            shift 2
            ;;
        --target-user)
            (($# >= 2)) || die '--target-user requires a value'
            TARGET_USER=$2
            shift 2
            ;;
        --repo)
            (($# >= 2)) || die '--repo requires a directory'
            REPO_DIR=$2
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

[[ "$HOST" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && "$HOST" != *-install ]] \
    || die '--host must be a registered host name, not an installer output'
[[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] \
    || die '--target-user must be a valid Unix account name'
REPO_DIR="$(cd -- "$REPO_DIR" && pwd -P)" \
    || die "repository directory does not exist: $REPO_DIR"
[[ -f "$REPO_DIR/flake.nix" ]] || die "not a fleet repository: $REPO_DIR"
[[ -t 0 && -t 1 ]] || die 'run this script from an interactive terminal'

for command in git nix nixos-rebuild; do
    command -v "$command" >/dev/null 2>&1 \
        || die "required command is not available: $command"
done

CONFIGURED_HOSTNAME=$(nix eval --no-write-lock-file --raw \
    "$REPO_DIR#nixosConfigurations.$HOST.config.networking.hostName") \
    || die "host '$HOST' is not a registered active NixOS configuration"
[[ "$CONFIGURED_HOSTNAME" == "$HOST" ]] \
    || die "configuration '$HOST' declares unexpected hostname '$CONFIGURED_HOSTNAME'"

git -C "$REPO_DIR" diff --check
nix flake check --no-write-lock-file "$REPO_DIR"

printf '\nDeploying %s from %s\n' "$HOST" "$REPO_DIR"
printf 'The remote sudo password will be requested next.\n\n'

exec nixos-rebuild switch \
    --flake "$REPO_DIR#$HOST" \
    --build-host "$TARGET_USER@$HOST" \
    --target-host "$TARGET_USER@$HOST" \
    --sudo \
    --ask-sudo-password

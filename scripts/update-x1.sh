#!/usr/bin/env bash
# Build and activate the current x1-9thgen configuration remotely.
#
# The X1 is used as both the build host and target host. This avoids copying
# unsigned locally-built store paths to a target whose Nix daemon requires
# signatures. Activation still requires the iindesa sudo password.

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: update-x1.sh [--repo DIRECTORY]

Validate the fleet flake, then build and activate x1-9thgen over SSH.
The remote host is both the Nix build host and deployment target. An
interactive terminal is required because sudo asks for the iindesa password.

Options:
  --repo DIRECTORY  Fleet checkout (default: repository containing this script)
  -h, --help        Show this help
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

while (($# > 0)); do
    case "$1" in
        --repo)
            (($# >= 2)) || die "--repo requires a directory"
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

REPO_DIR="$(cd -- "$REPO_DIR" && pwd -P)" \
    || die "repository directory does not exist: $REPO_DIR"
[[ -f "$REPO_DIR/flake.nix" ]] || die "not a fleet repository: $REPO_DIR"
[[ -t 0 && -t 1 ]] || die "run this script from an interactive terminal"

for command in git nix nixos-rebuild; do
    command -v "$command" >/dev/null 2>&1 \
        || die "required command is not available: $command"
done

git -C "$REPO_DIR" diff --check
nix flake check --no-write-lock-file "$REPO_DIR"

printf '\nUpdating x1-9thgen from %s\n' "$REPO_DIR"
printf 'The remote sudo password will be requested next.\n\n'

exec nixos-rebuild switch \
    --flake "$REPO_DIR#x1-9thgen" \
    --build-host iindesa@x1-9thgen \
    --target-host iindesa@x1-9thgen \
    --sudo \
    --ask-sudo-password

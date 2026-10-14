#!/usr/bin/env bash
# Enroll the current fleet account in OpenAI ChatGPT/Codex subscription auth.

set -Eeuo pipefail
umask 077

usage() {
    cat <<'EOF'
Usage: enroll-openclaw-openai.sh [--device-code] [--profile-id PROFILE_ID]

Sign in to OpenAI using ChatGPT/Codex subscription OAuth and save the profile
in this OpenClaw instance's runtime state. This does not use an API key or
modify the Nix-managed model configuration.

Options:
  --device-code          Use the device-code flow instead of the browser callback
  --profile-id ID        Save under a specific OpenClaw auth profile ID
  -h, --help             Show this help

Environment overrides:
  OPENCLAW_ENROLL_USER   Required account (default: iindesa)
  OPENCLAW_CONFIG_PATH   Config file (default: /etc/openclaw/openclaw.json)
  OPENCLAW_STATE_DIR     Runtime state (default: $HOME/.openclaw)
  OPENCLAW_ENV_FILE      Gateway EnvironmentFile (default: /run/agenix/openclaw-gateway-env)
  OPENCLAW_BIN           CLI command or path (default: openclaw)
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

USE_DEVICE_CODE=0
PROFILE_ID=''
while (($# > 0)); do
    case "$1" in
        --device-code)
            USE_DEVICE_CODE=1
            shift
            ;;
        --profile-id)
            (($# >= 2)) || die '--profile-id requires a value'
            PROFILE_ID=$2
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

[[ -t 0 && -t 1 ]] || die 'run this script from an interactive terminal'
((EUID != 0)) || die 'do not run as root; run it as the account that owns the OpenClaw state'

EXPECTED_USER=${OPENCLAW_ENROLL_USER:-iindesa}
CURRENT_USER=$(id -un)
[[ "$CURRENT_USER" == "$EXPECTED_USER" ]] \
    || die "run as '$EXPECTED_USER' (current account: '$CURRENT_USER'); override OPENCLAW_ENROLL_USER only for a different fleet service account"
[[ -n ${HOME:-} ]] || die 'HOME is not set for the OpenClaw service account'

OPENCLAW_CONFIG_PATH=${OPENCLAW_CONFIG_PATH:-/etc/openclaw/openclaw.json}
OPENCLAW_STATE_DIR=${OPENCLAW_STATE_DIR:-"$HOME/.openclaw"}
OPENCLAW_ENV_FILE=${OPENCLAW_ENV_FILE:-/run/agenix/openclaw-gateway-env}
OPENCLAW_BIN=${OPENCLAW_BIN:-openclaw}
[[ "$OPENCLAW_CONFIG_PATH" == /* ]] || die 'OPENCLAW_CONFIG_PATH must be an absolute path'
[[ "$OPENCLAW_STATE_DIR" == /* ]] || die 'OPENCLAW_STATE_DIR must be an absolute path'
[[ "$OPENCLAW_ENV_FILE" == /* ]] || die 'OPENCLAW_ENV_FILE must be an absolute path'
[[ -f "$OPENCLAW_CONFIG_PATH" && -r "$OPENCLAW_CONFIG_PATH" ]] \
    || die "OpenClaw config is not readable: $OPENCLAW_CONFIG_PATH"
[[ -d "$OPENCLAW_STATE_DIR" && -w "$OPENCLAW_STATE_DIR" ]] \
    || die "OpenClaw state directory must exist and be writable: $OPENCLAW_STATE_DIR"
[[ -f "$OPENCLAW_ENV_FILE" && -r "$OPENCLAW_ENV_FILE" ]] \
    || die "gateway environment file is not readable: $OPENCLAW_ENV_FILE"

if [[ "$OPENCLAW_BIN" == */* ]]; then
    [[ -x "$OPENCLAW_BIN" ]] || die "OpenClaw CLI is not executable: $OPENCLAW_BIN"
else
    command -v "$OPENCLAW_BIN" >/dev/null 2>&1 \
        || die "OpenClaw CLI is not available: $OPENCLAW_BIN"
fi

# The file is an agenix-managed systemd EnvironmentFile. Import it silently so
# the CLI can resolve the gateway's environment SecretRef without printing it.
export OPENCLAW_CONFIG_PATH OPENCLAW_STATE_DIR
export OPENCLAW_NIX_MODE=1
set -a
# shellcheck disable=SC1090,SC1091
. "$OPENCLAW_ENV_FILE"
set +a
# Keep the declared config and state paths authoritative if the env file has
# additional entries; Nix mode prevents CLI-side config mutation.
export OPENCLAW_CONFIG_PATH OPENCLAW_STATE_DIR
export OPENCLAW_NIX_MODE=1
[[ -n ${OPENCLAW_GATEWAY_TOKEN:-} ]] \
    || die 'gateway environment file does not define OPENCLAW_GATEWAY_TOKEN'
trap 'unset OPENCLAW_GATEWAY_TOKEN' EXIT

[[ -z "$PROFILE_ID" || ( "$PROFILE_ID" != *$'\n'* && "$PROFILE_ID" != *$'\r'* ) ]] \
    || die '--profile-id must not contain a newline'

login_args=(models auth login --provider openai)
[[ -z "$PROFILE_ID" ]] || login_args+=(--profile-id "$PROFILE_ID")
((USE_DEVICE_CODE == 0)) || login_args+=(--device-code)

printf 'Starting OpenAI ChatGPT/Codex subscription sign-in for %s.\n' "$CURRENT_USER"
"$OPENCLAW_BIN" "${login_args[@]}"

printf '\nOpenAI auth profiles:\n'
"$OPENCLAW_BIN" models auth list --provider openai
printf '\nModels available to this account:\n'
"$OPENCLAW_BIN" models list --provider openai
printf '\nSign-in complete. The model selection remains managed by Nix.\n'

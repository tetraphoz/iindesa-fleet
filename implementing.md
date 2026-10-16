# Implementation status

Last reviewed: 2026-10-17

This file tracks active workstation-fleet work. The fleet-specific backup,
notification, and management plan is in
[`docs/INFRASTRUCTURE-ROADMAP.md`](docs/INFRASTRUCTURE-ROADMAP.md). Public VPS
resources and hosted applications are managed separately in the `iindesa-infra`
project, not in this flake. Never record passwords, private keys, cloud
credentials, age identities, or other plaintext secrets here.

## Fleet scope

- Registered NixOS hosts: `p50` and `x1-9thgen`.
- `fleetHosts` in `flake.nix` is the single host registry; setting `diskDevice`
  generates a matching destructive `<host>-install` output.
- The T440s has left the fleet. Its former host module and resume offset are
  preserved in `archive/t440s/`; its migration inventory remains under
  `inventories/`. The archive is not included in the flake.
- `modules/common.nix` is the shared workstation configuration; storage is
  separated into runtime (`modules/storage.nix`) and installer
  (`modules/disko-layout.nix`) modules.
- The primary fleet account is `iindesa`.
- P50 runs NixOS 26.05. Its normal output is for routine rebuilds;
  `p50-install` is a destructive full-disk reinstall, not an in-place upgrade.

## Working-tree caution

Preserve unrelated local edits and review `git status` and `git diff` before
staging. The X1 Restic/OpenClaw setup and enrollment script are committed and
pushed in `55f39a5`. Live checks on 2026-10-17 confirmed that OpenClaw is
deployed, authenticated, and active on X1; no Nix-managed configuration or
service deployment was changed during those checks.

Git-backed flakes exclude untracked files. Stage any new files referenced by
the flake before evaluating it, including files embedded with `builtins.readFile`.
This is an index-only step; avoid staging unrelated work.

## Decisions and operational boundaries

- Continue manual NixOS updates and firmware updates; no unattended upgrades
  or firmware flashing.
- Secure Boot signing remains out of scope.
- Verify suspend, hibernate, and resume on actual hardware before changing
  power-management settings.
- X1 Restic/B2 uses the `x1-9thgen` bucket and a dedicated age identity. The
  user reports the first backup completed; a restore test was explicitly
  waived, so recovery remains unverified. P50 remains disabled.
- Keep SSH on the private Tailscale interface. No public SSH or remote desktop.
- Provisioning uses Disko and is destructive. Verify the target and backup,
  read the displayed disk details, and type the exact confirmation only when
  replacement is intentional.

## Current work

The P50 normal configuration and `p50-install` output target the fleet's
Disko layout; the latter erases the selected disk and is not a routine update
path. Keep each host's machine-specific `resume_offset` with its swapfile and
recalculate it after reformatting.

X1 is now configured with the tagged `nix-openclaw` v2026.10.4 release
(commit `08732c0d9fbfc34e7c285cdbac8130bacaaad9db`), packaging OpenClaw
2026.10.4. The X1 system toplevel built locally, and the generated config
passed `openclaw config validate`. The Nix-managed primary is
`openai/gpt-6-astra`; no explicit subagent model is configured.

After activation on 2026-10-16, OpenClaw 2026.10.4 refused to start because
`/home/iindesa/.openclaw/agents/main/agent/openclaw-agent.sqlite` had schema 21
and required a session-identity migration. Nix mode blocked `doctor --fix`;
no repair was applied. Since session history is disposable, the gateway was
stopped and the four `openclaw-agent.sqlite*` files were moved to the private
backup `/home/iindesa/.openclaw/backups/agent-db-fresh-start-20261016-144310/`.
Only those database files were moved; no config, environment file, or other
OpenClaw files were moved. After the manual start at 14:47 on 2026-10-16, the
fresh database was created (692224 bytes), and a follow-up check showed the
service active with `NRestarts=0`. WebSocket requests and Codex account-usage
checks succeeded. Old session IDs now return unavailable, as expected; one
Control UI connection also reported a token mismatch, while another connected
successfully. See the reset and UI follow-up notes in
[`docs/SECRETS.md`](docs/SECRETS.md).

Review compatible systemd sandboxing while retaining the gateway's required
provider network access.

## Backups

The Restic module is optional and disabled by default; X1 opts in to the
`x1-9thgen` B2 bucket with encrypted per-host credentials. Its application key
is bucket-restricted but has no object-prefix restriction. The configured
policy keeps four recent, six daily, eight weekly, and twelve monthly
snapshots, with a monthly 5% repository check. The user reports the first X1
backup completed and waived a restore test; it is not recovery-verified. Future
hosts still need a successful first backup and restore test before their backups
are treated as recovery-ready.

Snapper snapshots remain local recovery points, not a substitute for an
off-machine backup. See [`docs/SECRETS.md`](docs/SECRETS.md).

## Validation completed

- `nix flake check --no-write-lock-file` passed, including Bash syntax and
  ShellCheck for the fleet scripts.
- Built the X1 system toplevel without activating it; the generated OpenClaw
  configuration passed `openclaw config validate`.
- The enrollment script passed `bash -n`, ShellCheck, and a mock OAuth CLI-flow
  test; that mock did not perform a real sign-in. A later live check confirmed
  the OpenAI auth profile is available on X1.
- The Btrfs hibernation helper passed an isolated mock test for offset update
  and rejected an ordinary directory as an unmounted target.
- The enrollment work itself did not provision or deploy OpenClaw; X1 was
  switched to the validated v2026.10.4 system afterward. After archiving the
  incompatible agent database, the fresh gateway remained active in a follow-up
  check. Restic was already active. Commit `55f39a5` was pushed to `origin/main`.

## Next steps

- [ ] Refresh the Control UI after the database reset; if `token_mismatch`
      persists, update its saved token using the current gateway token without
      sharing the token in logs or chat.
- [ ] Review X1's B2 privacy, region, and expected-cost settings.
- [ ] Consider a later X1 Restic restore test; do not call the backup
      recovery-verified until it succeeds. Require a restore test before treating
      backups on additional hosts as recovery-ready.
- [ ] Review compatible OpenClaw systemd sandboxing and the pinned package's
      prompt-injection risk exception before a future upgrade.
- [ ] Keep the planned `/Shared` migration gated on Syncthing readiness and a
      separately verified backup/restore.

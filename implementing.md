# Implementation status

Last reviewed: 2026-10-06

This file tracks active repository work. The longer-term cloud and
infrastructure plan is in [`docs/INFRASTRUCTURE-ROADMAP.md`](docs/INFRASTRUCTURE-ROADMAP.md).
Never record passwords, private keys, cloud credentials, age identities, or
other secrets here.

## Fleet scope

- Registered NixOS hosts: `p50` and `x1-9thgen`; P50 still runs Arch Linux
  and awaits the documented migration.
- `fleetHosts` in `flake.nix` is the single host registry; setting `diskDevice`
  generates a matching destructive `<host>-install` output.
- The T440s has left the fleet. Its former host module and resume offset are
  preserved in `archive/t440s/`; its migration inventory remains under
  `inventories/`. The archive is not included in the flake.
- `modules/common.nix` is the shared workstation configuration; storage is
  separated into runtime (`modules/storage.nix`) and installer
  (`modules/disko-layout.nix`) modules.
- The primary fleet account is `iindesa`.
- The P50 still runs Arch Linux. Its normal NixOS output uses the fleet Disko
  labels; `p50-install` is a full-disk reinstall, not an in-place upgrade.

## Working-tree caution

The checkout contains pre-existing user changes and untracked work in addition
to this refactor. Preserve all unrelated edits. Nothing has been committed,
pushed, provisioned, or deployed as part of this work. Review `git status`
and `git diff` before staging or committing.

Nix's Git-backed flake source excludes untracked files. Stage new Nix files
imported by the flake before running flake evaluation; this is an index-only
step and does not require a commit. Avoid staging unrelated work.

## Decisions and operational boundaries

- Continue manual NixOS updates and firmware updates; no unattended upgrades
  or firmware flashing.
- Secure Boot signing remains out of scope.
- Verify suspend, hibernate, and resume on actual hardware before changing
  power-management settings.
- Restic/B2 remains disabled until a private bucket, per-host encrypted
  credentials, and independently recoverable age identities are ready.
- Keep SSH on the private Tailscale interface. No public SSH or remote desktop.
- Provisioning uses Disko and is destructive. Verify the target and backup,
  read the displayed disk details, and type the exact confirmation only when
  replacement is intentional.

## Current work

The storage/installer refactor and T440s retirement are represented in the
uncommitted working tree. The X1's `resume_offset` is tied to its actual
swapfile and must be retained for that disk; reformatting requires a new
offset. The P50 normal configuration and `p50-install` output both target the
fleet's Disko layout. The install output erases the selected disk; do not use
it until an external backup exists and its restore has been tested.

## Backups

The Restic module is optional and disabled by default. The proposal is a
per-host Backblaze B2 repository, encrypted Restic password, restricted
per-host application key, 14 daily / 8 weekly / 12 monthly retention, and a
monthly 5% repository check. These are not operational backups until the
bucket and secrets exist and both backup and restore have been verified.

Snapper snapshots remain local recovery points, not a substitute for an
off-machine backup. See [`docs/SECRETS.md`](docs/SECRETS.md).

## Validation completed

- `nix flake check --no-write-lock-file` passed from a temporary copy containing
  the full working tree. This avoids staging the existing untracked files just
  to make Git-backed flake evaluation see them.
- Evaluated the four outputs (`p50`, `p50-install`, `x1-9thgen`, and
  `x1-9thgen-install`) and confirmed the active and installer configurations
  evaluate against the shared fleet storage modules.
- `bash -n`, ShellCheck, and `git diff --check` passed for the fleet scripts
  and working tree.
- The Btrfs hibernation helper passed an isolated mock test for offset update
  and rejected an ordinary directory as an unmounted target.
- No system toplevel build, provisioning, install, switch, commit, or push was
  performed.

## Next steps

- [ ] Review the final full diff before staging or committing.
- [ ] Build the relevant host toplevel before a deployment when a full build
      check is wanted; no system activation is required for that validation.
- [ ] Review backup requirements and restore procedure before provisioning
      cloud resources or enabling Restic.
- [ ] Commit, push, install, or deploy only when separately authorized.

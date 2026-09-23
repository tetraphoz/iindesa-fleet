# Implementation status

Last updated: 2026-09-22

This file tracks active work and decisions for the `iindesa-fleet` repository.
The longer-term cloud and infrastructure work sequence is in
[`docs/INFRASTRUCTURE-ROADMAP.md`](docs/INFRASTRUCTURE-ROADMAP.md).
Do not put passwords, private keys, cloud credentials, age identities, or other
secrets here.

## Repository state

- The fleet has three NixOS configurations: `p50`, `t440s`, and `x1-9thgen`.
- `modules/common.nix` is the shared workstation configuration.
- The primary account is `iindesa` on every host.
- The repository is hosted at `github.com/tetraphoz/iindesa-fleet`.
- Commit `34e35b0` (`Make shared directory writable by primary user`) was
  pushed to `origin/main`.
- Current local changes are staged but not yet committed or pushed:
  - `scripts/update-x1.sh`
  - `flake.nix`
  - `docs/SECRETS.md`

## Completed

### Shared directory permissions

- Added a systemd oneshot service in `modules/common.nix`.
- After local filesystems are mounted, it sets:
  - `/home/iindesa/Shared` owner to `iindesa:users`.
  - Directory mode to `0750`.
- The service runs before `syncthing.service` and applies to all hosts.
- The change was deployed to GitHub in commit `34e35b0`, but the X1 activation
  was not completed at that time.

### X1 deployment helper

- Added `scripts/update-x1.sh`.
- It validates the flake, builds on `x1-9thgen`, and activates there over SSH.
- It uses the X1 as both `--build-host` and `--target-host` to avoid copying
  unsigned locally-built store paths to a target requiring Nix signatures.
- It requires an interactive terminal and asks for the remote sudo password.
- The flake shell-script check includes this script.

Run it from an interactive administration-host terminal:

```sh
./scripts/update-x1.sh
```

The X1 currently requires an interactive sudo password. A non-interactive
attempt built the new system remotely but could not activate it.

### Firmware updates

- `services.fwupd.enable = true` is already enabled in `modules/common.nix`.
- `fwupd` is installed in the common package set.
- On `x1-9thgen`, `fwupd.service` is enabled and active.
- Firmware updates are intentionally manual; do not add unattended firmware
  flashing.
- Secure Boot remains disabled by policy. Do not implement Secure Boot signing
  or automatic Secure Boot database updates.

### Validation

The following currently passes:

```sh
nix flake check --no-write-lock-file
git diff --check
```

## Decisions

- Fleet updates remain manual while Clan and Colmena are being evaluated.
- Syncthing's default firewall exposure is acceptable.
- Secure Boot is out of scope; keep it disabled.
- Power-management and hibernate behavior need to be checked on the hardware
  before changing the configuration.
- Syncthing device and folder configuration stays mutable and local. This is
  preferred for flexibility despite the less reproducible setup.
- Firmware updates remain manual.
- Restic backups should eventually use cloud or S3-compatible storage.
- Local notifications are sufficient initially; Zulip integration is optional
  and not yet specified.

## Open work

### Commit and deploy the current staged work

- [ ] Review the staged changes.
- [ ] Commit `scripts/update-x1.sh`, `flake.nix`, and `docs/SECRETS.md`.
- [ ] Push the commit to `origin/main`.
- [ ] Run `./scripts/update-x1.sh` from an interactive terminal.
- [ ] Verify on the X1:

  ```sh
  systemctl status shared-directory-permissions.service
  stat -c '%U:%G %a %n' /home/iindesa/Shared
  systemctl --failed --no-legend
  ```

Expected directory state:

```text
iindesa:users 750 /home/iindesa/Shared
```

### Cloud Restic backups

Restic is installed, but no backup service is enabled. The skeleton is in
`docs/SECRETS.md`; do not enable it until these choices are made:

- [ ] Select a provider: Backblaze B2, Wasabi, AWS S3, Cloudflare R2, or another
      S3-compatible service.
- [ ] Select the bucket/endpoint and region.
- [ ] Decide whether all of `/home/iindesa`, including `Shared`, is backed up.
- [ ] Define daily/weekly/monthly retention limits.
- [ ] Define bandwidth and scheduling requirements.
- [ ] Create agenix-managed restic password and provider credential secrets.
- [ ] Enable `services.restic.backups` in the appropriate common or host module.
- [ ] Test a backup, prune operation, and full restore before relying on it.
- [ ] Decide whether failures should produce local desktop notifications and/or
      Zulip messages.

The backup repository must remain off-machine. Snapper snapshots are local
recovery only and are not a substitute for Restic.

### Fleet management

- [ ] Evaluate Clan and Colmena against the current flake and deployment flow.
- [ ] Decide whether either tool becomes the supported fleet deployment path.
- [ ] Keep the existing manual `nixos-rebuild` and X1 update script working
      until a replacement is tested.

### Power management

- [ ] Check suspend, hibernate, resume, lid-close behavior, and battery use on
      each host.
- [ ] Confirm the configured Btrfs swapfile resume offsets work.
- [ ] Only then decide whether to change TLP, suspend, or hibernate settings.

### Notifications

- [ ] Define which events need notifications: failed services, SMART warnings,
      failed backups, firmware availability, or other events.
- [ ] Start with local notifications unless a Zulip server, stream, bot token,
      and secret-management approach are specified.
- [ ] Never commit Zulip tokens or webhook URLs.

## Out of scope for now

- Automatic NixOS upgrades.
- Automatic firmware installation.
- Secure Boot enablement or signing infrastructure.
- Declarative Syncthing pairing and folder configuration.
- Public SSH or remote-desktop exposure.
- Committing passwords, private keys, cloud credentials, or generated service
  state.

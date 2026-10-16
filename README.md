# IINDESA workstation fleet

NixOS configurations and migration targets for the KDE workstation fleet:

| Host | Hardware | Notes |
|---|---|---|
| `p50` | ThinkPad P50, Quadro M1000M | Running NixOS 26.05 with hybrid graphics and PRIME offload installed; the fwupd BIOS 1.75 update remains pending. |
| `x1-9thgen` | ThinkPad X1 Carbon 9th Gen | NixOS 26.05; shared encrypted Btrfs layout; OpenClaw 2026.10.4 active on loopback. |

The T440s is retired. Its old host module and resume offset are preserved in
[`archive/t440s/`](archive/t440s/); its inventory remains under
`inventories/`. Archived files are not active flake outputs.

## Bitwarden clients

The shared workstation configuration includes the official Bitwarden Desktop
app and managed Firefox and Chromium extensions. Flake checks and host builds
passed. The self-hosted endpoint is live and verified over tailnet HTTPS. After
the configuration is active on a host, select this URL in each client before
signing in (do not use Bitwarden Cloud):
`https://iindesa-apps-01.porpoise-degree.ts.net`. Deploy each host from an
interactive terminal with
`./scripts/deploy-host.sh --host p50` or
`./scripts/deploy-host.sh --host x1-9thgen`.

## Adding a host

`fleetHosts` in `flake.nix` is the single host registry. Add one entry with a
`primaryUser` and host module to create a normal NixOS output; its
`networking.hostName` must match the registry key. Add `diskDevice` only if
that machine should also get a destructive `<host>-install` output.
Create `hosts/<host>/configuration.nix` and `resume-offset.nix`, review any
hardware and storage overrides, then evaluate and build the outputs. See
[`docs/OPERATIONS.md`](docs/OPERATIONS.md) for the short checklist.

## Layout

- `flake.nix`, `flake.lock` — host registry, configurations, and pinned inputs.
- `hosts/` — per-machine configuration and hardware data.
- `modules/common.nix` — shared KDE workstation, users, and services.
- `modules/storage.nix` — runtime encrypted Btrfs mounts.
- `modules/disko-layout.nix` — shared destructive install layout.
- `packages.disko` — pinned Disko CLI for local USB installation.
- `modules/restic-backup.nix` — optional Restic/B2 module; X1 opts in, P50
  remains disabled.
- Pinned `nix-openclaw` input — OpenClaw package and upstream NixOS gateway
  module used by X1.
- `scripts/install-host.sh` — guarded SSH-based installer; USB steps are in `docs/INSTALL.md`.
- `scripts/deploy-host.sh` — guarded remote deployment helper.
- `scripts/enroll-openclaw-openai.sh` — interactive ChatGPT/Codex OAuth
  enrollment; X1 installs it as `enroll-openclaw-openai`.
- `nixos-inventory.sh` — read-only migration inventory collector.
- `docs/` — installation, operations, secrets, and fleet backup/infrastructure
  notes. Public VPS infrastructure is managed separately in the `iindesa-infra`
  project.

The NixOS target layout uses Btrfs subvolumes `@`, `@home`, `@log`, `@sync`,
and `@swap`.
The shared `@sync` subvolume is currently mounted at `/home/iindesa/Shared`;
the persistent swapfile lives in `@swap`. A move to `/Shared` is planned only
after Syncthing completes and a Restic backup/restore is verified; see
[`docs/OPERATIONS.md`](docs/OPERATIONS.md). The normal P50 output uses the same
fleet labels as its `p50-install` output and is the path for routine system
rebuilds. `p50-install` erases and recreates the selected disk; do not use it
for maintenance or deployment.

## Validate

```sh
nix flake check --no-write-lock-file
git diff --check
```

The flake check runs Bash syntax and ShellCheck on repository scripts. Build a
host to evaluate its NixOS system without activating it. `nixos-rebuild switch`
changes the running system.

Git-backed flakes omit untracked files. Stage any new files referenced by the
flake before evaluating (including files embedded with `builtins.readFile`);
review `git status` first. Staging does not require a commit.

## Inventory and operations

Run the read-only inventory collector as root for the most complete result:

```sh
sudo ./nixos-inventory.sh --host HOST --output inventories
```

Review its hardware, network, user, and configuration data before sharing or
committing it; inventory data may be sensitive. For installation, deployment,
Tailscale, and host-registration guidance, see
[`docs/INSTALL.md`](docs/INSTALL.md) and
[`docs/OPERATIONS.md`](docs/OPERATIONS.md).

Plaintext passwords, private keys, Wi-Fi profiles, age identities, Syncthing
state, and cloud credentials do not belong in Git. The separate `iindesa-infra`
project may track only SOPS-encrypted secret ciphertext under its own policy.
Snapper snapshots are local recovery only. X1's first Restic backup is reported
complete, but no restore has been tested; recovery remains unverified. See
[`docs/SECRETS.md`](docs/SECRETS.md). Require a suitable verified backup before
destructive provisioning or storage migration.

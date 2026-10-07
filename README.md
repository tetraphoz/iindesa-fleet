# IINDESA workstation fleet

NixOS configurations and migration targets for the KDE workstation fleet:

| Host | Hardware | Notes |
|---|---|---|
| `p50` | ThinkPad P50, Quadro M1000M | Currently Arch Linux; migrate with the destructive `p50-install` output after verifying an external backup. |
| `x1-9thgen` | ThinkPad X1 Carbon 9th Gen | Uses the shared encrypted Btrfs layout and a storage-free hardware template. |

The T440s is retired. Its old host module and resume offset are preserved in
[`archive/t440s/`](archive/t440s/); its inventory remains under
`inventories/`. Archived files are not active flake outputs.

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
- `modules/restic-backup.nix` — optional Restic/B2 backup module, disabled by default.
- `scripts/install-host.sh` — guarded SSH-based installer; USB steps are in `docs/INSTALL.md`.
- `scripts/deploy-host.sh` — guarded remote deployment helper.
- `nixos-inventory.sh` — read-only migration inventory collector.
- `docs/` — installation, operations, secrets, and infrastructure notes.

The NixOS target layout uses Btrfs subvolumes `@`, `@home`, `@log`, `@sync`,
and `@swap`.
The shared `@sync` subvolume is currently mounted at `/home/iindesa/Shared`;
the persistent swapfile lives in `@swap`. A move to `/Shared` is planned only
after Syncthing completes and a Restic backup/restore is verified; see
[`docs/OPERATIONS.md`](docs/OPERATIONS.md). The normal P50 output uses the same
fleet labels as its `p50-install` output. Do not apply it to the existing Arch
installation; `p50-install` erases and recreates the selected disk.

## Validate

```sh
nix flake check --no-write-lock-file
git diff --check
```

The flake check runs Bash syntax and ShellCheck on repository scripts. Build a
host to evaluate its NixOS system without activating it. `nixos-rebuild switch`
changes the running system.

Nix omits untracked files from Git-backed flakes. Stage newly created Nix files
that the flake imports before evaluating; review `git status` first. Staging
does not require a commit.

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

Passwords, private keys, Wi-Fi profiles, age identities, Syncthing state, and
cloud credentials do not belong in Git. Snapper snapshots are local recovery
only; do not rely on Restic/B2 until a backup and restore have been verified.
See [`docs/SECRETS.md`](docs/SECRETS.md). Provisioning and switching systems
require a verified target and current backup.

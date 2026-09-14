# NixOS work-machine fleet

This repository contains a shared KDE Plasma workstation configuration and
hardware-specific host modules for:

- `p50`: Lenovo ThinkPad P50, encrypted Btrfs root, Quadro M1000M
- `t440s`: Lenovo ThinkPad T440s, encrypted Btrfs root, Intel graphics
- `x1-9thgen`: new ThinkPad X1 Carbon 9th Gen, awaiting its hardware scan

All three hosts use Btrfs with `@`, `@home`, and `@log` subvolumes. The P50
already has that layout. The T440s inventory still describes its old
LUKS/LVM/ext4 installation, so it must be backed up and reprovisioned before
switching to this configuration.

The existing inventories were used as migration input. Package lists were not
copied wholesale: the common module contains the workstation tools and KDE
applications that are useful across the fleet, while old XFCE, Snap, and
machine-specific migration leftovers were intentionally left out. KDE Plasma
is the desktop for every host.

## Build or deploy

```sh
# Evaluate/build without switching the running machine
nix flake check
sudo nixos-rebuild build --flake .#p50
sudo nixos-rebuild build --flake .#t440s
sudo nixos-rebuild build --flake .#x1-9thgen

# On the target machine
sudo nixos-rebuild switch --flake /path/to/iindesa-fleet#p50
```

Set the host name in the command to match the target. The first login account
is `iindesa` on `p50` and `x1-9thgen`, and `rocio` on `t440s`. No password or
SSH key is stored here; set the password locally with `passwd` and add SSH
keys separately.

## Btrfs provisioning

The T440s must be migrated from its current LUKS/LVM/ext4 layout before using
`.#t440s`. The existing `/boot` and EFI partitions can be retained, but the
current root partition must be recreated as LUKS containing Btrfs. Create the
Btrfs subvolumes `@`, `@home`, and `@log`, and label the encrypted container
`NIXOS-LUKS` and the Btrfs filesystem `NIXOS`. Verify the device names first;
this is intentionally not automated because formatting the wrong partition
will destroy data. Restore the user data only after validating the new boot.

The X1 template uses the same Btrfs labels and subvolume layout. Replace its
placeholder hardware file with the generated hardware configuration after
partitioning it.

## New X1 bootstrap

`hosts/x1-9thgen/hardware-configuration.nix` is deliberately a safe template,
not an invented hardware scan. Boot an installer, partition and mount the
machine, then generate the real file:

```sh
sudo nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix hosts/x1-9thgen/
```

Review the generated file, especially the root filesystem, EFI mount, swap,
and any LUKS UUID. Do not run destructive partitioning commands from this
repository without checking the device names first.

For Wi-Fi, no credentials are committed. Enable NetworkManager (already done
by the common module), then connect interactively with KDE's network applet or
`nmcli`.

## Secrets and machine-specific data

Passwords, Wi-Fi profiles, private keys, and syncthing device configuration
must remain outside Git. If reproducible secret management is needed later,
add sops-nix or agenix rather than embedding secrets in a Nix module.

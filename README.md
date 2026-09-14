# NixOS work-machine fleet

This repository contains a shared KDE Plasma workstation configuration and
hardware-specific host modules for:

- `p50`: Lenovo ThinkPad P50, encrypted Btrfs root, Quadro M1000M
- `t440s`: Lenovo ThinkPad T440s, encrypted LUKS/LVM root, Intel graphics
- `x1-9thgen`: new ThinkPad X1 Carbon 9th Gen, awaiting its hardware scan

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

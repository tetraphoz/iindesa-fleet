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

## Installation from a NixOS installer

These steps assume a UEFI x86_64 NixOS installer and a backup of all data on
the target machine. **Partitioning and formatting are destructive. Verify the
disk with `lsblk` before running any storage command.**

### 1. Boot and prepare the installer

Boot the installer in UEFI mode, open a terminal, become root, enable time
synchronization, and connect to the network:

```sh
sudo -i
timedatectl set-ntp true
nmcli device status
# For Wi-Fi, use the KDE network menu or:
nmcli device wifi list
nmcli device wifi connect '<SSID>' --ask
```

Clone this repository in the installer environment, outside `/mnt`. HTTPS
is used here so an SSH key is not required in the installer:

```sh
git clone https://github.com/tetraphoz/iindesa-fleet.git /etc/nixos/fleet
cd /etc/nixos/fleet
```

For a fresh X1 Carbon installation, the guarded automated procedure is
available in [X1-INSTALL.md](X1-INSTALL.md):

```sh
./scripts/install-x1.sh --disk /dev/nvme0n1
```

Replace the disk with the whole internal device identified by `lsblk`. The
script is destructive, displays the selected disk, and requires an explicit
confirmation before partitioning it.

### 2. Choose the storage procedure

- **P50:** the inventory already describes the encrypted Btrfs layout used by
  `hosts/p50/configuration.nix`. Back up the data, unlock the existing LUKS
  container, and mount its existing subvolumes. Do not format it unless a
  clean reinstall is intended.
- **T440s:** the inventory describes the old LUKS/LVM/ext4 installation. To
  use `.#t440s`, back up the machine and recreate its root partition as
  encrypted Btrfs. The existing EFI and `/boot` partitions may be retained.
- **X1 Carbon 9th Gen:** partition the new disk with an EFI system partition
  and an encrypted Linux root partition. The root filesystem must be Btrfs.
  Do not assume the disk is `/dev/nvme0n1`; confirm it with `lsblk`.

For a new encrypted Btrfs root, after creating the partitions, the essential
formatting and subvolume steps are:

```sh
# Replace /dev/ROOT_PARTITION only after checking lsblk.
cryptsetup luksFormat --label NIXOS-LUKS /dev/ROOT_PARTITION
cryptsetup open /dev/ROOT_PARTITION cryptroot
mkfs.btrfs -L NIXOS /dev/mapper/cryptroot

mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
umount /mnt

mount -o subvol=@,compress=zstd /dev/mapper/cryptroot /mnt
mkdir -p /mnt/home /mnt/var/log /mnt/boot /mnt/boot/efi
mount -o subvol=@home,compress=zstd /dev/mapper/cryptroot /mnt/home
mount -o subvol=@log,compress=zstd /dev/mapper/cryptroot /mnt/var/log
```

Mount the EFI and `/boot` partitions according to the host layout. For the
existing T440s layout, the inventory recorded these UUIDs:

```sh
mount /dev/disk/by-uuid/690e4316-3896-4aa2-bb73-71293835d21e /mnt/boot
mount /dev/disk/by-uuid/07D4-D0F1 /mnt/boot/efi
```

For the X1, use the actual EFI partition identified with `lsblk` instead. The
P50 uses `/boot` UUID `43BE-1091` and its existing Btrfs subvolumes, so mount
those rather than running the formatting commands above:

```sh
cryptsetup open /dev/disk/by-uuid/eb8d2902-ae92-4fc8-9aef-578656f5431b luksdev
mount -o subvol=@,compress=zstd /dev/mapper/luksdev /mnt
mkdir -p /mnt/home /mnt/var/log /mnt/boot
mount -o subvol=@home,compress=zstd /dev/mapper/luksdev /mnt/home
mount -o subvol=@log,compress=zstd /dev/mapper/luksdev /mnt/var/log
mount /dev/disk/by-uuid/43BE-1091 /mnt/boot
```

### 3. Generate hardware configuration

The X1 has no inventory yet. After its filesystems are mounted, generate and
review its hardware file:

```sh
nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix \
  /etc/nixos/fleet/hosts/x1-9thgen/hardware-configuration.nix
```

The generated file contains the real UUIDs and replaces the label-based X1
placeholder. For P50 and T440s, review the host modules against the mounted
layout; their disk information came from the existing inventories.

### 4. Install the selected host

Run the installer using the host name that matches the machine:

```sh
nixos-install --root /mnt --flake /etc/nixos/fleet#p50
# or:
nixos-install --root /mnt --flake /etc/nixos/fleet#t440s
# or:
nixos-install --root /mnt --flake /etc/nixos/fleet#x1-9thgen
```

Set the requested root password. The normal fleet account is created by the
configuration, but no user password is stored in Git. After the first boot,
log in through the local console and set it:

```sh
passwd iindesa   # P50 or X1
passwd rocio     # T440s
```

Then remove the installer media and reboot:

```sh
reboot
```

### 5. First boot checks

Confirm that KDE, networking, audio, and the encrypted mounts are working:

```sh
systemctl --failed
findmnt -t btrfs,vfat
nmcli device status
```

Connect Wi-Fi interactively if needed. Future configuration updates can be
installed with `nixos-rebuild switch` from a checked-out copy of this repo.

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

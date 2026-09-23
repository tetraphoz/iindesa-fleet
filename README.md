# NixOS work-machine fleet

This repository contains a shared KDE Plasma workstation configuration and
hardware-specific host modules for:

- `p50`: Lenovo ThinkPad P50, encrypted Btrfs root, Quadro M1000M
- `t440s`: Lenovo ThinkPad T440s, encrypted Btrfs root, Intel graphics
- `x1-9thgen`: new ThinkPad X1 Carbon 9th Gen, awaiting its hardware scan

All three host configurations use an encrypted root by default: each defines
an initrd LUKS device before mounting its Btrfs root. The EFI system partition
(and the T440s `/boot` partition) remain unencrypted as required for boot.
All target roots use Btrfs with `@`, `@home`, `@log`, `@sync`, and `@swap`
subvolumes. The shared `@sync` subvolume is mounted at
`/home/<primary-user>/Shared` for Syncthing's Desktop and Documents folders.
The encrypted `@swap` subvolume contains a persistent swapfile for hibernation.
The P50
already has that layout. The T440s inventory still describes its old
LUKS/LVM/ext4 installation, so it must be backed up and reprovisioned before
switching to this configuration.

The existing inventories were used as migration input. Package lists were not
copied wholesale: the common module contains the workstation tools and KDE
applications that are useful across the fleet, while old XFCE, Snap, and
machine-specific migration leftovers were intentionally left out. KDE Plasma
is the desktop for every host.

## Repository layout

- `flake.nix` and `flake.lock` — pinned NixOS inputs and the three host outputs.
- `modules/common.nix` — shared KDE Plasma workstation configuration.
- `hosts/<name>/` — host-specific boot, hardware, graphics, and filesystem settings.
- `nixos-inventory.sh` — read-only migration inventory collector for existing Linux systems.
- `scripts/install-x1.sh` — guarded, destructive X1 Carbon provisioning helper.
- `docs/X1-INSTALL.md` — guarded X1 installation procedure.
- `docs/SECRETS.md` — agenix, Syncthing, snapshot, and off-machine backup guidance.
- `docs/remote.md` — Tailscale, SSH, and remote NixOS deployment instructions.
- `inventories/` — migration inputs and generated archives. Newly generated
  inventory directories are ignored by Git; add an archive explicitly only
  after reviewing it before sharing.

## Package policy

`modules/common.nix` contains the cross-host workstation baseline derived from
both the P50 and T440s inventories. In addition to KDE applications and
compiler tooling, it includes the storage tools needed by this fleet
(`btrfs-progs`, `cryptsetup`, filesystem utilities, and `efibootmgr`), laptop
and hardware diagnostics, network troubleshooting tools, and common transfer
utilities such as `rsync`.

The old package lists are not copied wholesale. Legacy XFCE applications,
Snap packages, stale migration dependencies, and specialized applications
should only be added after confirming that they belong on every host. Hardware-
specific software, such as the P50 NVIDIA driver, stays in that host's module.

## Collecting a migration inventory

The inventory script records hardware, storage, networking, packages, services,
users, and relevant configuration references from the current Linux machine. It
supports Debian/Ubuntu, Arch, Fedora/RHEL, openSUSE, and Alpine systems. It does
not create a NixOS configuration and it intentionally avoids copying common
secret files.

Run it as root for the most complete result, preferably from the repository
checkout:

```sh
# Use the short hostname and write to ./inventories by default.
sudo ./nixos-inventory.sh

# Explicit host and output directory (the positional form is also supported).
sudo ./nixos-inventory.sh x1-9thgen inventories

# Equivalent long-option form.
sudo ./nixos-inventory.sh --host x1-9thgen --output inventories
```

The command creates `inventories/<host>/` and, when `tar` is available,
`inventories/<host>.tar.gz`. Existing inventory directories are protected from
accidental merging; use `--force` to replace one, or `--no-archive` to skip the
archive. Use `--help` for the complete option list. Always inspect
`logs/sensitive-file-review.txt` and the collected network, user, and
configuration data before committing or sharing an inventory.

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
available in [docs/X1-INSTALL.md](docs/X1-INSTALL.md):

```sh
./scripts/install-x1.sh --disk /dev/nvme0n1
```

Replace the disk with the whole internal device identified by `lsblk`. The
script is destructive, displays the selected disk, requires an explicit
confirmation before partitioning it, and pauses after hardware generation so
the generated file can be reviewed before installation.

### 2. Choose the storage procedure

- **P50:** the inventory already describes the encrypted Btrfs layout used by
  `hosts/p50/configuration.nix`. Back up the data, unlock the existing LUKS
  container, and mount its existing subvolumes. Do not format it unless a
  clean reinstall is intended.
- **T440s:** the inventory describes the old LUKS/LVM/ext4 installation. To
  use `.#t440s`, back up the machine and recreate its root partition as
  encrypted Btrfs. The existing EFI and `/boot` partitions may be retained;
  they are the only unencrypted boot filesystems in the target layout.
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
btrfs subvolume create /mnt/@sync
btrfs subvolume create /mnt/@swap
umount /mnt

mount -o subvol=@,compress=zstd /dev/mapper/cryptroot /mnt
mkdir -p /mnt/home /mnt/var/log /mnt/boot /mnt/boot/efi
mount -o subvol=@home,compress=zstd /dev/mapper/cryptroot /mnt/home
mount -o subvol=@log,compress=zstd /dev/mapper/cryptroot /mnt/var/log
mkdir -p /mnt/home/PRIMARY_USER/Shared
mount -o subvol=@sync,compress=zstd /dev/mapper/cryptroot \
  /mnt/home/PRIMARY_USER/Shared
mkdir -p /mnt/swap
mount -o subvol=@swap,compress=zstd /dev/mapper/cryptroot /mnt/swap
btrfs filesystem mkswapfile --size 32768M --uuid clear /mnt/swap/swapfile
btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile
```

Replace `PRIMARY_USER` with `iindesa` before running the mount commands. Save
that command's numeric output; it is the `resume_offset` value required for
hibernation in the host's hardware configuration. Add it there as:

```nix
boot.kernelParams = [ "resume_offset=REPLACE_WITH_OFFSET" ];
```

Mount the EFI and `/boot` partitions according to the host layout. For the
existing T440s layout, the inventory recorded these UUIDs:

```sh
mount /dev/disk/by-uuid/690e4316-3896-4aa2-bb73-71293835d21e /mnt/boot
mount /dev/disk/by-uuid/07D4-D0F1 /mnt/boot/efi
```

For the X1, use the actual EFI partition identified with `lsblk` instead. The
P50 uses `/boot` UUID `43BE-1091` and its existing Btrfs subvolumes, so mount
those rather than running the formatting commands above. If its existing
filesystem does not yet contain `@sync`, create that subvolume first:

```sh
cryptsetup open /dev/disk/by-uuid/eb8d2902-ae92-4fc8-9aef-578656f5431b luksdev
mkdir -p /mnt/btrfs-top
mount -o subvolid=5 /dev/mapper/luksdev /mnt/btrfs-top
btrfs subvolume create /mnt/btrfs-top/@sync
btrfs subvolume create /mnt/btrfs-top/@swap
umount /mnt/btrfs-top
rmdir /mnt/btrfs-top

mount -o subvol=@,compress=zstd /dev/mapper/luksdev /mnt
mkdir -p /mnt/home /mnt/var/log /mnt/boot
mount -o subvol=@home,compress=zstd /dev/mapper/luksdev /mnt/home
mount -o subvol=@log,compress=zstd /dev/mapper/luksdev /mnt/var/log
mkdir -p /mnt/home/iindesa/Shared
mount -o subvol=@sync,compress=zstd /dev/mapper/luksdev \
  /mnt/home/iindesa/Shared
mkdir -p /mnt/swap
mount -o subvol=@swap,compress=zstd /dev/mapper/luksdev /mnt/swap
btrfs filesystem mkswapfile --size 32768M --uuid clear /mnt/swap/swapfile
btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile
mount /dev/disk/by-uuid/43BE-1091 /mnt/boot
```

The helper can record the offset in the host configuration automatically:

```sh
sudo ./scripts/configure-btrfs-hibernation.sh \
  --root /mnt \
  --config hosts/p50/configuration.nix
```

Use the T440s configuration path instead when provisioning that host. The
`/mnt/swap` subvolume must be mounted before running the helper.

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
nixos-install --root /mnt --no-root-password \
  --flake /etc/nixos/fleet#p50
# or:
nixos-install --root /mnt --no-root-password \
  --flake /etc/nixos/fleet#t440s
# or:
nixos-install --root /mnt --no-root-password \
  --flake /etc/nixos/fleet#x1-9thgen
```

The root account remains locked. The normal fleet account is created in the
`wheel` group, and no user password is stored in Git. Set its password before
rebooting:

```sh
nixos-enter --root /mnt -c 'passwd iindesa'
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

## Validate, build, or deploy

Run the checks before committing configuration or script changes. The flake
check evaluates every host and runs Bash syntax and ShellCheck validation for
the repository scripts:

```sh
nix flake check --no-write-lock-file

# Evaluate/build without switching the running machine.
sudo nixos-rebuild build --flake .#p50
sudo nixos-rebuild build --flake .#t440s
sudo nixos-rebuild build --flake .#x1-9thgen

# On the target machine.
sudo nixos-rebuild switch --flake /path/to/iindesa-fleet#p50
```

Use the host name matching the target. A build does not change the running
system; `switch` does. The first login account is `iindesa` on every host.
No password or SSH key is stored here; set
the password locally with `passwd` and add SSH keys separately.

## Btrfs provisioning

The T440s must be migrated from its current LUKS/LVM/ext4 layout before using
`.#t440s`. The existing `/boot` and EFI partitions can be retained, but the
current root partition must be recreated as LUKS containing Btrfs. Create the
Btrfs subvolumes `@`, `@home`, `@log`, and `@sync`, and label the encrypted container
`NIXOS-LUKS` and the Btrfs filesystem `NIXOS`. Verify the device names first;
this is intentionally not automated because formatting the wrong partition
will destroy data. Restore the user data only after validating the new boot.

The X1 template uses the same Btrfs labels and subvolume layout, including
`@sync` for Syncthing data. Replace its
placeholder hardware file with the generated hardware configuration after
partitioning it.

## New X1 bootstrap

`hosts/x1-9thgen/hardware-configuration.nix` is deliberately a label-based
bootstrap template, not an invented hardware scan. The recommended path is the
[X1 installation procedure](docs/X1-INSTALL.md), which partitions and mounts the
selected disk, generates the real hardware file, checks the flake, and installs
the host. Boot an installer, partition and mount the machine manually only if
you are not using that helper, then generate the real file:

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

## Secrets, Syncthing, and backups

Passwords, Wi-Fi profiles, private keys, and Syncthing device configuration
must remain outside Git. Agenix is included for encrypted secrets, Syncthing
is provisioned automatically for the primary user, and Snapper provides local
Btrfs snapshots for `/` and `/home`.

Read [docs/SECRETS.md](docs/SECRETS.md) for the age identity workflow, Syncthing
bootstrap notes, and the planned restic off-machine backup configuration.
Snapshots are not a substitute for backups because they remain on the same
disk.

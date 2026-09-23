# NixOS installation: ThinkPad X1 Carbon 9th Gen

This document installs the `x1-9thgen` configuration from this repository on a ThinkPad X1 Carbon 9th Gen.

The procedure creates a new GPT partition table, an EFI system partition, and an encrypted Btrfs root filesystem. **It is destructive. Back up all data before starting.**

The repository is kept at `/etc/nixos/fleet`. `/mnt` is used only as the temporary mount point for the target system while booted from the NixOS installer.

## 1. Boot the installer

Boot a NixOS installer in **UEFI mode**. If Secure Boot is enabled and you have not configured your own NixOS signing keys, disable Secure Boot temporarily in the firmware settings.

Open a terminal and become root:

```sh
sudo -i
```

Enable time synchronization:

```sh
timedatectl set-ntp true
```

Connect to the network. For Wi-Fi, either use the installer's network tools or run:

```sh
nmcli device status
nmcli device wifi list
nmcli device wifi connect '<SSID>' --ask
```

Confirm that the installer was booted in UEFI mode:

```sh
test -d /sys/firmware/efi && echo UEFI || echo 'ERROR: not booted in UEFI mode'
```

The output must be `UEFI`.

## 2. Obtain the repository

Clone the repository into `/etc/nixos` in the installer environment:

```sh
mkdir -p /etc/nixos
git clone https://github.com/tetraphoz/iindesa-fleet.git /etc/nixos/fleet
cd /etc/nixos/fleet
```

If the repository is already available on another disk or USB drive, copy it instead:

```sh
cp -a /path/to/iindesa-fleet /etc/nixos/fleet
```

Keep the checkout outside `/mnt`: the script mounts `/mnt` over the target
filesystem, and a checkout below `/mnt` would be hidden while the install is
running.

## Automated installation

For a fresh X1 installation, the repository includes a guarded script that
performs the partitioning, formatting, mounts, hardware scan, flake check, and
NixOS installation described below. It prints the disk layout and requires a
typed confirmation before erasing anything:

```sh
cd /etc/nixos/fleet
./scripts/install-x1.sh --disk /dev/nvme0n1
```

Replace `/dev/nvme0n1` with the whole internal disk identified by `lsblk`.
The script asks for the root password during `nixos-install`, then prompts for
the `iindesa` password and copies the checkout into the installed system at
`/etc/nixos/fleet`. It automatically unmounts the target and closes the LUKS
mapping when it finishes. Read the manual steps below before running it; the
operation is destructive. `--yes` skips the confirmation only for deliberate,
non-interactive use.

## 3. Identify the internal disk

List all disks and partitions:

```sh
lsblk -e7 -o NAME,TYPE,SIZE,FSTYPE,LABEL,UUID,MODEL,MOUNTPOINTS
```

Identify the internal X1 disk. Do not assume that it is `/dev/nvme0n1`; make sure it is not the installer USB or an external backup disk.

For the examples below, the internal disk is assumed to be `/dev/nvme0n1`. Change this value after checking `lsblk`:

```sh
export DISK=/dev/nvme0n1
```

The following command sets partition names for common disk types:

```sh
case "$DISK" in
  /dev/nvme*|/dev/mmcblk*)
    export EFI_PART="${DISK}p1"
    export ROOT_PART="${DISK}p2"
    ;;
  *)
    export EFI_PART="${DISK}1"
    export ROOT_PART="${DISK}2"
    ;;
esac

printf 'Disk: %s\nEFI: %s\nRoot: %s\n' "$DISK" "$EFI_PART" "$ROOT_PART"
lsblk "$DISK"
```

Do not continue until the displayed disk and partitions are correct.

## 4. Create the partition table

The following commands erase the selected disk:

```sh
parted --script "$DISK" \
  mklabel gpt \
  mkpart ESP fat32 1MiB 1GiB \
  set 1 esp on \
  mkpart primary 1GiB 100%
```

Ask the kernel to reread the partition table and verify it:

```sh
partprobe "$DISK"
lsblk "$DISK"
```

If the resulting partition names differ from `$EFI_PART` and `$ROOT_PART`, update those variables before continuing.

## 5. Format and unlock the root filesystem

Format the EFI system partition:

```sh
mkfs.fat -F 32 -n EFI "$EFI_PART"
```

Create the encrypted root partition. This destroys the selected root partition and prompts for a LUKS passphrase:

```sh
cryptsetup luksFormat --label NIXOS-LUKS "$ROOT_PART"
```

Open the encrypted container as `cryptroot`:

```sh
cryptsetup open "$ROOT_PART" cryptroot
```

Create the Btrfs filesystem:

```sh
mkfs.btrfs -L NIXOS /dev/mapper/cryptroot
```

## 6. Create the Btrfs subvolumes

Temporarily mount the filesystem:

```sh
mount /dev/mapper/cryptroot /mnt
```

Create the subvolumes expected by the X1 configuration:

```sh
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
```

Unmount the temporary top-level mount:

```sh
umount /mnt
```

Mount the actual target layout:

```sh
mount -o subvol=@,compress=zstd,ssd \
  /dev/mapper/cryptroot /mnt

mkdir -p /mnt/home /mnt/var/log /mnt/boot

mount -o subvol=@home,compress=zstd,ssd \
  /dev/mapper/cryptroot /mnt/home

mount -o subvol=@log,compress=zstd,ssd \
  /dev/mapper/cryptroot /mnt/var/log

mount "$EFI_PART" /mnt/boot
```

The X1 configuration mounts the EFI partition at `/boot`, not `/boot/efi`.

Verify the layout:

```sh
findmnt -R /mnt
btrfs subvolume list /mnt
```

The output should show the `@`, `@home`, and `@log` subvolumes and mounts for `/mnt`, `/mnt/home`, `/mnt/var/log`, and `/mnt/boot`.

## 7. Generate the real X1 hardware configuration

The committed X1 hardware file is only a placeholder. Generate a hardware configuration from the actual mounted machine into a temporary directory under `/etc/nixos`:

```sh
rm -rf /etc/nixos/generated-x1
mkdir -p /etc/nixos/generated-x1

nixos-generate-config \
  --root /mnt \
  --dir /etc/nixos/generated-x1
```

Copy the generated hardware module into the repository:

```sh
cp /etc/nixos/generated-x1/hardware-configuration.nix \
  /etc/nixos/fleet/hosts/x1-9thgen/hardware-configuration.nix
```

Review the generated file:

```sh
less /etc/nixos/fleet/hosts/x1-9thgen/hardware-configuration.nix
```

Check that it describes the actual installation, especially:

- The LUKS device or UUID.
- The Btrfs root filesystem.
- The `@`, `@home`, and `@log` subvolumes.
- The EFI partition mounted at `/boot`.
- Any generated swap configuration.
- The required initrd modules.

Compare the file with the real devices if necessary:

```sh
blkid
lsblk -f
```

Do not install while the file still contains the placeholder labels from the original template.

## 8. Validate the flake

Run the checks from the repository:

```sh
cd /etc/nixos/fleet
nix flake check --no-write-lock-file
```

Optionally build the X1 system without installing it:

```sh
nix build \
  .#nixosConfigurations.x1-9thgen.config.system.build.toplevel \
  --no-link
```

Fix any errors before continuing.

## 9. Install NixOS

Install the X1 configuration using the repository at `/etc/nixos/fleet`:

```sh
nixos-install \
  --root /mnt \
  --flake /etc/nixos/fleet#x1-9thgen
```

Set the root password when prompted.

The configuration creates the normal user `iindesa`, but no user password is stored in Git. Set it before rebooting:

```sh
nixos-enter --root /mnt -c 'passwd iindesa'
```

## 10. Reboot into NixOS

Flush pending writes, unmount the target, close the encrypted container, and reboot:

```sh
sync
umount -R /mnt
cryptsetup close cryptroot
reboot
```

Remove the installer USB when the machine restarts.

At the first boot:

1. Enter the LUKS passphrase.
2. Select the NixOS system if the boot menu appears.
3. Log in to KDE Plasma as `iindesa`.

## 11. First-boot checks

Open a terminal and check for failed services and expected mounts:

```sh
systemctl --failed
findmnt -t btrfs,vfat
nmcli device status
```

The expected filesystem layout is:

```text
@      -> /
@home  -> /home
@log   -> /var/log
EFI    -> /boot
```

Connect Wi-Fi if needed:

```sh
nmcli device wifi list
nmcli device wifi connect '<SSID>' --ask
```

Also verify KDE, audio, Bluetooth, printing, and Syncthing.

## 12. Future configuration updates

After booting into the installed system, keep the repository at `/etc/nixos/fleet` and apply future changes with:

```sh
cd /etc/nixos/fleet
sudo nixos-rebuild switch --flake /etc/nixos/fleet#x1-9thgen
```

Before committing changes, run:

```sh
cd /etc/nixos/fleet
nix flake check
```

## Important safety notes

- Never run the partitioning or formatting commands until `lsblk` confirms the correct disk.
- Keep backups until the new system has booted and the user data has been restored and verified.
- Do not commit passwords, Wi-Fi credentials, private keys, or Syncthing configuration to the repository.
- The generated hardware file is machine-specific and should be reviewed before every fresh installation.

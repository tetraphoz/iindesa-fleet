# Install a fleet host

`<host>-install` uses Disko to repartition and erase the configured whole disk.
For the P50, use a NixOS USB installer; `scripts/install-host.sh` is the
alternative for a target that is reachable over SSH. Never proceed without an
external backup and a verified test restore.

## P50 from a USB installer

Keep the fleet checkout on a separate writable USB drive or other storage that
will not be erased. Boot the official x86_64 NixOS installer in UEFI mode,
connect it to the network, and open a terminal in the committed fleet checkout.
The installer needs the repo to evaluate the flake; do not use a checkout with
missing or unstaged Nix files.

Confirm the configured and physical disks before formatting:

```sh
nix --extra-experimental-features 'nix-command flakes' eval --raw \
  '.#nixosConfigurations.p50-install.config.disko.devices.disk.main.device'
lsblk -d -o NAME,SIZE,MODEL
```

The configured device is `/dev/nvme0n1`. A September 2026 inventory recorded
a roughly 477 GiB Samsung NVMe there, but verify the live `lsblk` output; do
not rely on the old inventory. Stop if the configured path and P50 disk do not
match exactly.

With the backup and target confirmed, run Disko from the pinned fleet input.
This destroys the selected disk's partition table and data:

```sh
sudo nix --extra-experimental-features 'nix-command flakes' run .#disko -- \
  --mode destroy,format,mount \
  --flake "$PWD#p50-install"
```

Enter a new LUKS passphrase when prompted. If the output or confirmation does
not identify the intended P50 disk, cancel. After Disko completes, verify that
`/mnt`, `/mnt/boot`, `/mnt/home`, and `/mnt/swap` are mounted as expected:

```sh
findmnt -R /mnt
```

Generate the swapfile's machine-specific hibernation offset, stage that one
file so Nix sees it in the Git-backed flake, and install the normal P50
configuration without formatting again:

```sh
sudo ./scripts/configure-btrfs-hibernation.sh \
  --root /mnt --config hosts/p50/resume-offset.nix
git add hosts/p50/resume-offset.nix
sudo nixos-install --flake "$PWD#p50" --no-root-password
```

Before rebooting, set a password for `iindesa` and each other normal account
you intend to use. Do not share passwords in chat:

```sh
sudo nixos-enter --root /mnt -c 'passwd iindesa'
```

Then sync, reboot, and remove the installer USB. Keep the checkout and generated
`hosts/p50/resume-offset.nix`; copy the new offset back to the main fleet repo
and commit/push it before future rebuilds. Reformatting this disk requires a
new offset.

At first boot, verify the system before restoring personal data:

```sh
systemctl --failed
findmnt -t btrfs,vfat
nmcli device status
```

Restore user data from the verified external backup; do not blindly copy the
old Arch `/etc` over NixOS. Enable Restic only after the restored data is in
place and the B2 credentials and recovery keys are ready.

## SSH-based installation

For a Linux target that is reachable over SSH with root or passwordless
`sudo`, `scripts/install-host.sh` runs NixOS Anywhere, checks the target disk,
requires an exact erase confirmation, records the resume offset, sets account
passwords, and reboots. See `scripts/install-host.sh --help` for syntax.

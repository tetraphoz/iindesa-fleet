# Temporary, label-based hardware configuration for the new X1.
#
# Before the first real installation, generate the definitive version from
# the installer environment instead of relying on these placeholders:
#
#   nixos-generate-config --root /mnt
#
# Then copy /mnt/etc/nixos/hardware-configuration.nix here and review it.
# This file assumes a LUKS container labelled NIXOS-LUKS, a Btrfs root
# labelled NIXOS, and an EFI partition labelled EFI so that the flake can be
# evaluated before the machine is scanned.

{ ... }:

{
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-label/NIXOS-LUKS";
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" "ssd" ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd" "ssd" ];
  };

  fileSystems."/var/log" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [ "subvol=@log" "compress=zstd" "ssd" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/EFI";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  # The common module configures the encrypted Btrfs @swap subvolume and
  # persistent swapfile used for hibernation. The installer creates it and
  # adds the machine-specific resume offset after scanning the filesystem.
}

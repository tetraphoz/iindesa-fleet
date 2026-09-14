# Temporary, label-based hardware configuration for the new X1.
#
# Before the first real installation, generate the definitive version from
# the installer environment instead of relying on these placeholders:
#
#   nixos-generate-config --root /mnt
#
# Then copy /mnt/etc/nixos/hardware-configuration.nix here and review it.
# This file assumes an EFI partition labelled EFI and a Btrfs root labelled
# NIXOS only so that the flake can be evaluated before the machine is scanned.

{ ... }:

{
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/EFI";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  # The installer can replace this with the actual encrypted-device entry if
  # the new machine is provisioned with LUKS.
  swapDevices = [ ];
}

{ primaryUser, ... }:

{
  # These labels match new Disko-created filesystems. Existing hosts with
  # stable hardware UUIDs can override individual device identifiers locally.
  boot.initrd.luks.devices.cryptroot.device = "/dev/disk/by-label/NIXOS-LUKS";

  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" "ssd" ];
  };
  fileSystems."/home" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd" "ssd" ];
  };
  fileSystems."/var/log" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@log" "compress=zstd" "ssd" ];
  };
  fileSystems."/home/${primaryUser}/Shared" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@sync" "compress=zstd" "ssd" ];
  };
  fileSystems."/swap" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@swap" "compress=zstd" "ssd" ];
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/EFI";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  swapDevices = [ { device = "/swap/swapfile"; } ];
}

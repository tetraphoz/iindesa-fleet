{ diskDevice, primaryUser, ... }:

{
  disko.devices.disk.main = {
    type = "disk";
    device = diskDevice;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            extraArgs = [ "-n" "EFI" ];
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            extraFormatArgs = [ "--label" "NIXOS-LUKS" ];
            content = {
              type = "btrfs";
              extraArgs = [ "-L" "NIXOS" ];
              subvolumes = {
                "/@" = {
                  mountpoint = "/";
                  mountOptions = [ "compress=zstd" "ssd" ];
                };
                "/@home" = {
                  mountpoint = "/home";
                  mountOptions = [ "compress=zstd" "ssd" ];
                };
                "/@log" = {
                  mountpoint = "/var/log";
                  mountOptions = [ "compress=zstd" "ssd" ];
                };
                "/@sync" = {
                  mountpoint = "/home/${primaryUser}/Shared";
                  mountOptions = [ "compress=zstd" "ssd" ];
                };
                "/@swap" = {
                  mountpoint = "/swap";
                  mountOptions = [ "compress=zstd" "ssd" ];
                  swap.swapfile.size = "32768M";
                };
              };
            };
          };
        };
      };
    };
  };
}

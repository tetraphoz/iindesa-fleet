{ ... }:

{
  networking.hostName = "t440s";

  # Keep the existing EFI and /boot partitions, but replace the old
  # LUKS/LVM/ext4 root with an encrypted Btrfs filesystem.  The labels below
  # are intentional placeholders for the new layout; see README.md before
  # provisioning this host.
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "ehci_pci"
    "sd_mod"
    "sdhci_pci"
  ];
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
    device = "/dev/disk/by-uuid/690e4316-3896-4aa2-bb73-71293835d21e";
    fsType = "ext4";
  };
  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/07D4-D0F1";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  # The inventory reports Intel Haswell integrated graphics.  The kernel's
  # modesetting driver is preferred over the obsolete xf86-video-intel driver.
  services.xserver.videoDrivers = [ "modesetting" ];
}

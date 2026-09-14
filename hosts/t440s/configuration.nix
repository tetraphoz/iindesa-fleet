{ ... }:

{
  networking.hostName = "t440s";

  # The T440s currently has a separate EFI system partition and /boot
  # partition, so retain GRUB rather than changing the existing layout.
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
  boot.initrd.kernelModules = [ "dm_mod" "dm_crypt" "dm_snapshot" ];
  boot.initrd.luks.devices."sda3_crypt" = {
    device = "/dev/disk/by-uuid/ff519df2-33cb-4b7f-ba2f-0b05340682d1";
  };

  fileSystems."/" = {
    device = "/dev/mapper/xubuntu--vg-root";
    fsType = "ext4";
    options = [ "errors=remount-ro" ];
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
  swapDevices = [
    { device = "/dev/mapper/xubuntu--vg-swap_1"; }
  ];

  # The inventory reports Intel Haswell integrated graphics.  The kernel's
  # modesetting driver is preferred over the obsolete xf86-video-intel driver.
  services.xserver.videoDrivers = [ "modesetting" ];
}

{ ... }:

{
  imports = [ ./resume-offset.nix ];

  networking.hostName = "t440s";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "ehci_pci"
    "sd_mod"
    "sdhci_pci"
  ];
  # The inventory reports Intel Haswell integrated graphics.  The kernel's
  # modesetting driver is preferred over the obsolete xf86-video-intel driver.
  services.xserver.videoDrivers = [ "modesetting" ];
}

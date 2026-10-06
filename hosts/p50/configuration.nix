{ ... }:

{
  imports = [ ./resume-offset.nix ];

  networking.hostName = "p50";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "sd_mod"
  ];
  hardware.nvidia = {
    # The inventory identifies a Quadro M1000M (Maxwell).  Keep the
    # proprietary driver: this GPU is not supported by the open kernel module.
    modesetting.enable = true;
    open = false;
    powerManagement.enable = true;
  };
  services.xserver.videoDrivers = [ "nvidia" ];
}

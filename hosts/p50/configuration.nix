{ lib, ... }:

{
  imports = [ ./resume-offset.nix ];

  networking.hostName = "p50";

  # The P50 admin key has been installed; disable password-based SSH auth.
  services.openssh.settings = {
    PasswordAuthentication = lib.mkForce false;
    KbdInteractiveAuthentication = lib.mkForce false;
  };

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

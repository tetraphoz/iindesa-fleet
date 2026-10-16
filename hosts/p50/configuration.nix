{ config, lib, ... }:

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
    # The Quadro M1000M (Maxwell) needs the proprietary legacy 580 branch;
    # newer NVIDIA branches no longer support this GPU.
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    modesetting.enable = true;
    open = false;
    powerManagement.enable = true;
  };
  # BIOS hybrid mode exposes the Intel iGPU for the internal panel. Keep
  # NVIDIA offloaded for applications that explicitly need the discrete GPU.
  hardware.nvidia.prime = {
    intelBusId = "PCI:0@0:2:0";
    nvidiaBusId = "PCI:1@0:0:0";
    offload = {
      enable = true;
      enableOffloadCmd = true;
    };
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.printers.ensurePrinters = [
    {
      name = "HP-LaserJet-Pro-MFP-M127fn";
      description = "HP LaserJet Pro MFP M127fn";
      deviceUri = "ipp://192.168.1.75:631/ipp/print";
      model = "everywhere";
    }
  ];
  hardware.printers.ensureDefaultPrinter = "HP-LaserJet-Pro-MFP-M127fn";
}

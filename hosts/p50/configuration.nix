{ ... }:

{
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
  boot.initrd.luks.devices."luksdev" = {
    device = "/dev/disk/by-uuid/eb8d2902-ae92-4fc8-9aef-578656f5431b";
  };

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/e34fd222-5f3c-4b21-bcbc-5a2e276cb923";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" "ssd" ];
  };
  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/e34fd222-5f3c-4b21-bcbc-5a2e276cb923";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd" "ssd" ];
  };
  fileSystems."/var/log" = {
    device = "/dev/disk/by-uuid/e34fd222-5f3c-4b21-bcbc-5a2e276cb923";
    fsType = "btrfs";
    options = [ "subvol=@log" "compress=zstd" "ssd" ];
  };
  fileSystems."/home/iindesa/Shared" = {
    device = "/dev/disk/by-uuid/e34fd222-5f3c-4b21-bcbc-5a2e276cb923";
    fsType = "btrfs";
    options = [ "subvol=@sync" "compress=zstd" "ssd" ];
  };
  fileSystems."/swap" = {
    device = "/dev/disk/by-uuid/e34fd222-5f3c-4b21-bcbc-5a2e276cb923";
    fsType = "btrfs";
    options = [ "subvol=@swap" "compress=zstd" "ssd" ];
  };
  boot.resumeDevice = "/dev/disk/by-uuid/e34fd222-5f3c-4b21-bcbc-5a2e276cb923";
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/43BE-1091";
    fsType = "vfat";
  };

  hardware.nvidia = {
    # The inventory identifies a Quadro M1000M (Maxwell).  Keep the
    # proprietary driver: this GPU is not supported by the open kernel module.
    modesetting.enable = true;
    open = false;
    powerManagement.enable = true;
  };
  services.xserver.videoDrivers = [ "nvidia" ];
}

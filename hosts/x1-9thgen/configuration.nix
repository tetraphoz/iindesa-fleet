{ ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "x1-9thgen";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # A ThinkPad X1 Carbon 9th Gen uses Intel graphics, NVMe storage and the
  # Intel wireless stack.  The disk UUIDs are intentionally not guessed: this
  # host has no migration inventory yet.  Replace the label-based mounts in
  # hardware-configuration.nix with the output of nixos-generate-config after
  # partitioning the new machine.
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];
  services.xserver.videoDrivers = [ "modesetting" ];
}

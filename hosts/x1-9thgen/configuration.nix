{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./resume-offset.nix
  ];

  networking.hostName = "x1-9thgen";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Storage is declared in modules/storage.nix and mirrored for installation
  # by modules/disko-layout.nix.
  services.xserver.videoDrivers = [ "modesetting" ];
}

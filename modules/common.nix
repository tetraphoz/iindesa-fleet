{ config, lib, pkgs, primaryUser, ... }:

{
  # The inventories show KDE Plasma on both existing work machines.  Keep the
  # desktop and the useful workstation services in one place so all hosts stay
  # alike even though their hardware and disks differ.
  assertions = [
    {
      assertion = builtins.match "^[a-z_][a-z0-9_-]*$" primaryUser != null;
      message = "primaryUser must be a valid Unix account name";
    }
  ];

  system.stateVersion = "25.05";

  time.timeZone = "America/Monterrey";
  i18n.defaultLocale = "es_MX.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "es_MX.UTF-8";
    LC_IDENTIFICATION = "es_MX.UTF-8";
    LC_MEASUREMENT = "es_MX.UTF-8";
    LC_MONETARY = "es_MX.UTF-8";
    LC_NAME = "es_MX.UTF-8";
    LC_NUMERIC = "es_MX.UTF-8";
    LC_PAPER = "es_MX.UTF-8";
    LC_TELEPHONE = "es_MX.UTF-8";
    LC_TIME = "es_MX.UTF-8";
  };
  console.keyMap = "us";

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages;
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ ];
  networking.firewall.allowedUDPPorts = [ ];

  # KDE Plasma, using SDDM.  No XFCE packages or services are pulled in.
  services.xserver.enable = true;
  services.xserver.xkb.layout = "us";
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.displayManager.defaultSession = "plasma";

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;

  hardware.bluetooth.enable = true;
  hardware.graphics.enable = true;
  services.printing = {
    enable = true;
    drivers = [ pkgs.hplip ];
  };
  services.fwupd.enable = true;
  services.udisks2.enable = true;

  # Both inventories show a laptop workload and benefit from zram.  TLP is
  # used instead of power-profiles-daemon to avoid running two power managers.
  zramSwap.enable = true;
  services.tlp.enable = true;
  services.power-profiles-daemon.enable = false;

  services.syncthing = {
    enable = true;
    user = primaryUser;
    group = "users";
    dataDir = "/home/${primaryUser}";
    configDir = "/home/${primaryUser}/.config/syncthing";
  };

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
  users.mutableUsers = true;
  users.users.${primaryUser} = {
    isNormalUser = true;
    description = "${primaryUser} work account";
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "render" "lp" ];
  };

  environment.systemPackages = with pkgs; [
    # Core workstation and diagnostics
    curl
    wget
    git
    neovim
    vim
    zsh
    tmux
    htop
    btop
    jq
    ripgrep
    fd
    fzf
    tree
    file
    pciutils
    usbutils
    lshw
    lm_sensors
    smartmontools
    fwupd
    unzip
    zip
    p7zip
    restic
    openssh

    # Development tools observed on the fleet
    gcc
    clang
    gnumake
    cmake
    ninja
    meson
    pkg-config
    python3
    python3Packages.pip
    nodejs
    jdk
    perl

    # KDE Plasma workstation applications
    kdePackages.dolphin
    kdePackages.konsole
    kdePackages.kate
    kdePackages.ark
    kdePackages.okular
    kdePackages.gwenview
    kdePackages.spectacle
    kdePackages.kcalc
    kdePackages.kdeconnect-kde
    kdePackages.plasma-browser-integration
    kdePackages.kde-gtk-config
    kdePackages.kdenlive
    firefox
    chromium
    thunderbird
    libreoffice
    keepassxc
    mpv
    gimp
    pdfarranger
    ranger
    pavucontrol
    blueman
    hplip
    simple-scan
    networkmanagerapplet
    wayland-utils
  ];

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  # Do not enable an SSH server by default: neither inventory reported one as
  # an active service.  openssh above provides the client for fleet work.
  services.openssh.enable = false;
}

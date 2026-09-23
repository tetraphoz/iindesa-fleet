{ agenix, lib, pkgs, primaryUser, ... }:

{
  # New fleet roots use encrypted Btrfs with @, @home, and @log subvolumes.
  # Filesystem devices and LUKS mappings stay host-specific because they are
  # discovered from each machine during installation.
  #
  # The inventories show KDE Plasma on both existing work machines.  Keep the
  # desktop and the useful workstation services in one place so all hosts stay
  # alike even though their hardware and disks differ.
  assertions = [
    {
      assertion = builtins.match "^[a-z_][a-z0-9_-]*$" primaryUser != null;
      message = "primaryUser must be a valid Unix account name";
    }
  ];

  # Keep the synchronized payload separate from the regular home subvolume.
  # The device label is shared by the fleet; each host still has its own
  # hardware-specific root and LUKS mappings.
  fileSystems."/home/${primaryUser}/Shared" = lib.mkDefault {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [ "subvol=@sync" "compress=zstd" "ssd" ];
  };
  fileSystems."/swap" = lib.mkDefault {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "btrfs";
    options = [ "subvol=@swap" "compress=zstd" "ssd" ];
  };

  # The persistent swapfile is inside the encrypted Btrfs filesystem. Each
  # host's hardware module may override this with its filesystem UUID.
  boot.resumeDevice = lib.mkDefault "/dev/disk/by-label/NIXOS";
  swapDevices = [ { device = "/swap/swapfile"; } ];

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
  services.smartd.enable = true;
  services.udisks2.enable = true;

  # Both inventories show a laptop workload and benefit from zram.  TLP is
  # used instead of power-profiles-daemon to avoid running two power managers.
  zramSwap.enable = true;
  services.tlp.enable = true;
  services.power-profiles-daemon.enable = false;
  services.thermald.enable = true;
  services.fstrim.enable = true;
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
  };

  services.syncthing = {
    enable = true;
    user = primaryUser;
    group = "users";
    dataDir = "/home/${primaryUser}/Shared";
    configDir = "/home/${primaryUser}/.config/syncthing";
    openDefaultPorts = true;
  };

  # Snapper provides local, point-in-time recovery for the Btrfs root and home
  # subvolumes. It is not an off-machine backup; use restic for that later.
  services.snapper = {
    snapshotRootOnBoot = true;
    persistentTimer = true;
    snapshotInterval = "hourly";
    cleanupInterval = "1d";
    configs = {
      root = {
        SUBVOLUME = "/";
        FSTYPE = "btrfs";
        ALLOW_USERS = [ primaryUser ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = 6;
        TIMELINE_LIMIT_DAILY = 7;
        TIMELINE_LIMIT_WEEKLY = 4;
        TIMELINE_LIMIT_MONTHLY = 6;
        TIMELINE_LIMIT_YEARLY = 1;
      };
      home = {
        SUBVOLUME = "/home";
        FSTYPE = "btrfs";
        ALLOW_USERS = [ primaryUser ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = 6;
        TIMELINE_LIMIT_DAILY = 7;
        TIMELINE_LIMIT_WEEKLY = 4;
        TIMELINE_LIMIT_MONTHLY = 6;
        TIMELINE_LIMIT_YEARLY = 1;
      };
      shared = {
        SUBVOLUME = "/home/${primaryUser}/Shared";
        FSTYPE = "btrfs";
        ALLOW_USERS = [ primaryUser ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = 6;
        TIMELINE_LIMIT_DAILY = 7;
        TIMELINE_LIMIT_WEEKLY = 4;
        TIMELINE_LIMIT_MONTHLY = 6;
        TIMELINE_LIMIT_YEARLY = 1;
      };
    };
  };

  # Snapper expects a .snapshots subvolume inside each configured subvolume.
  # Create it declaratively on first boot rather than requiring manual setup.
  systemd.services.snapper-init = {
    description = "Initialize Snapper Btrfs subvolumes";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    before = [
      "snapper-boot.service"
      "snapper-timeline.service"
      "snapper-cleanup.service"
    ];
    path = [ pkgs.btrfs-progs ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for subvolume in / /home /home/${primaryUser}/Shared; do
        snapshot_dir="$subvolume/.snapshots"
        if btrfs subvolume show "$snapshot_dir" >/dev/null 2>&1; then
          continue
        fi
        if [ -e "$snapshot_dir" ]; then
          echo "$snapshot_dir exists but is not a Btrfs subvolume" >&2
          exit 1
        fi
        btrfs subvolume create "$snapshot_dir"
      done
    '';
  };

  systemd.tmpfiles.rules = [
    "d /home/${primaryUser}/Shared/Desktop 0750 ${primaryUser} users -"
    "d /home/${primaryUser}/Shared/Documents 0750 ${primaryUser} users -"
  ];

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
    acpi
    powertop
    iotop
    inxi
    lsof
    ncdu
    unzip
    zip
    p7zip
    btrfs-progs
    cryptsetup
    dosfstools
    e2fsprogs
    efibootmgr
    rsync
    restic
    openssh
    age
    agenix.packages.${pkgs.system}.default

    # Network and transfer utilities observed on the fleet
    aria2
    dnsutils
    traceroute
    wireguard-tools

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
    gdb
    strace

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

  # Generate a unique host identity on first boot without exposing an SSH
  # server by default. The public host key can later be used for host
  # verification or as an agenix recipient.
  services.openssh = {
    enable = false;
    generateHostKeys = true;
    hostKeys = [
      {
        type = "ed25519";
        path = "/etc/ssh/ssh_host_ed25519_key";
      }
    ];
  };
}

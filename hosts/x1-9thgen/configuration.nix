{ config, pkgs, nix-openclaw, ... }:

let
  openclawPackages = nix-openclaw.packages.${pkgs.stdenv.hostPlatform.system};
  openclawPackage = openclawPackages.default;
  openclawCodexPlugin = openclawPackages.openclaw-runtime-plugin-codex;
  openclawEnrollmentScript = pkgs.writeShellApplication {
    name = "enroll-openclaw-openai";
    runtimeInputs = [ openclawPackage ];
    text = builtins.readFile ../../scripts/enroll-openclaw-openai.sh;
  };
in
{
  imports = [
    nix-openclaw.nixosModules.openclaw-gateway
    ./hardware-configuration.nix
    ./resume-offset.nix
  ];

  networking.hostName = "x1-9thgen";

  # Agenix uses this dedicated root-only identity rather than the SSH host key.
  age.identityPaths = [ "/var/lib/agenix/x1-host.txt" ];

  # Use the X1-dedicated B2 bucket; its application key is bucket-scoped.
  # Restic keeps the module's default iindesa-fleet/x1-9thgen object prefix.
  fleet.backups.restic = {
    enable = true;
    bucket = "x1-9thgen";
  };

  # Explicitly permit this pinned OpenClaw release despite Nixpkgs' warning
  # about prompt-injection risk. Review this exception when updating OpenClaw.
  nixpkgs.config.permittedInsecurePackages = [ "openclaw-2026.10.4" ];

  environment.systemPackages = [ openclawPackage openclawEnrollmentScript ];

  age.secrets.openclaw-gateway-env = {
    file = ../../secrets/openclaw/x1-gateway.env.age;
    owner = "iindesa";
    group = "users";
    mode = "0400";
  };

  # Use nix-openclaw's NixOS module instead of a locally defined unit.
  services.openclaw-gateway = {
    enable = true;
    package = openclawPackage;
    user = "iindesa";
    group = "users";
    createUser = false;
    stateDir = "/home/iindesa/.openclaw";
    workingDirectory = "/home/iindesa";
    environmentFiles = [ config.age.secrets.openclaw-gateway-env.path ];
    environment.OPENCLAW_NIX_MODE = "1";
    restart = "on-failure";
    restartSec = 5;
    config = {
      agents.defaults.model.primary = "openai/gpt-6-astra";
      gateway = {
        mode = "local";
        bind = "loopback";
        auth = {
          mode = "token";
          token = {
            source = "env";
            provider = "default";
            id = "OPENCLAW_GATEWAY_TOKEN";
          };
        };
      };
      plugins = {
        entries.codex.enabled = true;
        load.paths = [ "${openclawCodexPlugin}" ];
      };
    };
  };

  # Preserve the service's existing local-only hardening with the upstream unit.
  systemd.services.openclaw-gateway.serviceConfig = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "full";
    TimeoutStopSec = "30s";
    UMask = "0077";
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Storage is declared in modules/storage.nix and mirrored for installation
  # by modules/disko-layout.nix.
  services.xserver.videoDrivers = [ "modesetting" ];
}

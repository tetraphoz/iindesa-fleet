{
  config,
  lib,
  pkgs,
  primaryUser,
  ...
}:

let
  cfg = config.fleet.backups.restic;
  host = config.networking.hostName;
  home = "/home/${primaryUser}";
  secretPrefix = "restic-${host}";
  passwordSecret = "${secretPrefix}-password";
  credentialsSecret = "${secretPrefix}-b2-credentials";
  repository = "b2:${cfg.bucket}:${cfg.prefix}/${host}";
in
{
  options.fleet.backups.restic = {
    enable = lib.mkEnableOption "encrypted off-machine home backups with Restic and Backblaze B2";

    bucket = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The dedicated Backblaze B2 bucket for fleet Restic repositories.";
    };

    prefix = lib.mkOption {
      type = lib.types.str;
      default = "iindesa-fleet";
      description = "Object-name prefix under which per-host Restic repositories are stored.";
    };

    keepDaily = lib.mkOption {
      type = lib.types.ints.positive;
      default = 14;
      description = "Number of daily Restic snapshots to retain per host.";
    };

    keepWeekly = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "Number of weekly Restic snapshots to retain per host.";
    };

    keepMonthly = lib.mkOption {
      type = lib.types.ints.positive;
      default = 12;
      description = "Number of monthly Restic snapshots to retain per host.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.bucket != "";
        message = "fleet.backups.restic.enable requires fleet.backups.restic.bucket";
      }
      {
        assertion =
          builtins.match "^[A-Za-z0-9._/-]+$" cfg.prefix != null
          && !(lib.hasPrefix "/" cfg.prefix)
          && !(lib.hasSuffix "/" cfg.prefix);
        message = "fleet.backups.restic.prefix must be a relative B2 object prefix";
      }
    ];

    age.secrets.${passwordSecret} = {
      file = ../secrets/restic/${host}-password.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    age.secrets.${credentialsSecret} = {
      file = ../secrets/restic/${host}-b2.env.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    services.restic.backups.home = {
      inherit repository;
      passwordFile = config.age.secrets.${passwordSecret}.path;
      environmentFile = config.age.secrets.${credentialsSecret}.path;
      paths = [ home ];
      exclude = [
        "${home}/.cache"
        "${home}/.local/share/Trash"
        "${home}/.snapshots"
        "${home}/.config/syncthing"
        "${home}/Shared/.snapshots"
      ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "2h";
      };
      pruneOpts = [
        "--keep-daily ${toString cfg.keepDaily}"
        "--keep-weekly ${toString cfg.keepWeekly}"
        "--keep-monthly ${toString cfg.keepMonthly}"
      ];
      initialize = true;
      runCheck = false;
    };

    systemd.services.restic-backups-home.onFailure = [ "restic-backup-alert.service" ];

    systemd.services.restic-home-check = {
      description = "Check a sample of the fleet Restic repository";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.restic ];
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = config.age.secrets.${credentialsSecret}.path;
      };
      environment = {
        RESTIC_REPOSITORY = repository;
        RESTIC_PASSWORD_FILE = config.age.secrets.${passwordSecret}.path;
      };
      script = ''
        restic check --read-data-subset=5%
      '';
      onFailure = [ "restic-backup-alert.service" ];
    };

    systemd.services.restic-backup-alert = {
      description = "Notify logged-in users about Restic failures";
      path = [ pkgs.util-linux ];
      serviceConfig.Type = "oneshot";
      script = ''
        message="Restic backup or repository check failed on ${host}. See the system journal."
        printf '%s\n' "$message"
        printf '%s\n' "$message" | wall || true
      '';
    };

    systemd.timers.restic-home-check = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "monthly";
        Persistent = true;
        RandomizedDelaySec = "2h";
      };
    };
  };
}

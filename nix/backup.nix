# NixOS module for Baker backup to Wasabi
# Usage: import this as a module factory — takes `self` to reference the flake's package
{ self }:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.baker-backup;
in {
  options.services.baker-backup = {
    enable = lib.mkEnableOption "Baker backup to Wasabi";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/baker";
      description = "Directory for baker data to backup";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "sinh";
      description = "User to run backup as";
    };

    scriptPath = lib.mkOption {
      type = lib.types.path;
      default = /home/sinh/Documents/bakery-shop/scripts/wasabi-backup.sh;
      description = "Path to the backup script";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.baker-backup = {
      description = "Baker Backup to Wasabi";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${cfg.scriptPath}";
        Environment = "DATA_DIR=${cfg.dataDir}";
        User = cfg.user;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    systemd.timers.baker-backup = {
      description = "Baker Backup Timer - Every 6 hours";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = "*-*-* 00/6:00:00";
        RandomizedDelaySec = "30m";
        Persistent = true;
      };
    };
  };
}

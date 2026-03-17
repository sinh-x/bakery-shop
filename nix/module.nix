# NixOS module for Baker bakery operations API server
# Usage: import this as a module factory — takes `self` to reference the flake's package
{ self }:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.baker;

  configFile = pkgs.writeText "baker.yaml" ''
    data_dir: ${cfg.dataDir}
    db_path: ${cfg.dataDir}/baker.db
    host: ${cfg.host}
    port: ${toString cfg.port}
  '';
in {
  options.services.baker = {
    enable = lib.mkEnableOption "Baker bakery operations API server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 2108;
      description = "Port for baker serve";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Bind address for baker serve";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/baker";
      description = "Directory for baker data (database and photos)";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "sinh";
      description = "User to run baker service as";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.system}.baker;
      defaultText = lib.literalExpression "self.packages.\${pkgs.system}.baker";
      description = "Baker package to use";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.baker = {
      description = "Baker Bakery API Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${cfg.dataDir}";
        ExecStart = "${cfg.package}/bin/baker --config ${configFile} serve";
        User = cfg.user;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}

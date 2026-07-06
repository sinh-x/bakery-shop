# NixOS module for CUPS print server with Y41BT thermal printer
# Usage: import this as a module factory — takes `self` to reference the flake
{ self }:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.baker-cups;
in {
  options.services.baker-cups = {
    enable = lib.mkEnableOption "CUPS print server with Y41BT thermal printer";
  };

  config = lib.mkIf cfg.enable {
    services.printing.enable = true;

    services.printing.ensurePrinters = [
      {
        name = "Y41BT";
        location = "Lily";
        description = "Y41BT Thermal Receipt Printer";
        deviceUri = "parallel:/dev/usb/lp0";
        model = "raw";
        ensureDefaultPrinter = true;
      }
    ];

    services.udev.extraRules = ''
      KERNEL=="lp*", GROUP="lp", MODE="0660"
    '';

    networking.firewall.extraInputRules = ''
      tcp dport 631 ip saddr 100.64.0.0/10 accept
      tcp dport 631 drop
    '';
  };
}

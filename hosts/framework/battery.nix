# The laptop spends most of its time docked on AC (see dock-awake.nix), and a
# lithium cell held at 100% ages fastest: the charger stops charging there, but
# the cell sits at full voltage. Cap charging at 80% and lift the cap on demand
# before leaving with `charge-full`; it drops back to 80% at the next unplug.
#
# The limit lives in the EC (framework_tool --charge-limit). It is reapplied at
# boot because the BIOS can set its own value on startup.
{
  pkgs,
  lib,
  ...
}:
let
  limit = 80;
  ft = lib.getExe pkgs.framework-tool;

  chargeFull = pkgs.writeShellScriptBin "charge-full" ''
    set -eu
    sudo ${ft} --charge-limit 100 > /dev/null
    echo "Charging to 100% until the charger is unplugged; then back to ${toString limit}%."
  '';
in
{
  environment.systemPackages = [
    pkgs.framework-tool
    chargeFull
  ];

  systemd.services.charge-limit = {
    description = "Cap battery charging at ${toString limit}%";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${ft} --charge-limit ${toString limit}";
    };
  };

  # Unplugging ends a `charge-full`.
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", KERNEL=="ACAD", ACTION=="change", ATTR{online}=="0", RUN+="${pkgs.systemd}/bin/systemctl start --no-block charge-limit.service"
  '';
}

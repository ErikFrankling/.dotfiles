# Systemd service: https://github.com/nix-community/NixOS-WSL/issues/262
# wsl-vpnkit: https://github.com/sakai135/wsl-vpnkit

{
  pkgs,
  config,
  lib,
  ...
}:

{
  options.wsl-vpnkit =
    let
      inherit (lib) mkOption types;
    in
    {
      autoVPN = mkOption {
        type = types.bool;
        example = false;
        default = true;
        description = "If the systemd service should be enabled";
      };
      checkURL = mkOption {
        type = types.str;
        example = "192.168.0.1";
        description = "The ip adress in the corp network to ping to test connectivity";
      };
    };

  config = {
    environment.systemPackages = with pkgs; [
      wsl-vpnkit
      iputils
    ];
    systemd.services =
      let
        cfg = config.wsl-vpnkit;
      in
      {
        wsl-vpnkit-auto = {
          enable = cfg.autoVPN;
          description = "wsl-vpnkit";

          path = [ pkgs.iputils ];
          script = ''
            has_internet () {
              ping -q -w 1 -c 1 8.8.8.8 >/dev/null
            }

            has_company_network () {
              ping -q -w 1 -c 1 ${cfg.checkURL} > /dev/null
            }

            is_active_wsl-vpnkit () {
              systemctl is-active -q wsl-vpnkit.service
            }

            main () {
              if is_active_wsl-vpnkit; then
                if has_internet && ! has_company_network; then
                  echo "Stopping wsl-vpnkit..."
                  systemctl stop wsl-vpnkit.service
                fi
              else
                if ! has_internet; then
                  echo "Starting wsl-vpnkit..."
                  systemctl start wsl-vpnkit.service
                fi
              fi
            }

            while :
            do
              main
              sleep 30
            done
          '';

          wantedBy = [ "multi-user.target" ];
        };

        wsl-vpnkit = {
          enable = true;
          description = "wsl-vpnkit";

          serviceConfig = {
            ExecStart = "${pkgs.wsl-vpnkit}/bin/wsl-vpnkit";
            Type = "idle";
            Restart = "always";
            KillMode = "mixed";
          };
        };
      };
  };
}

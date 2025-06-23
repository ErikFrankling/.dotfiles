{ config, pkgs, lib, ... }:

{

  environment.systemPackages = [ pkgs.wpa_supplicant_gui ];
  # networking.wireless.dbusControlled = true;
  networking.networkmanager.enable = lib.mkForce false;
  networking.wireless.enable = true;
  networking.wireless.userControlled.enable = true;
  users.extraUsers.erikf.extraGroups = [ "wheel" ];
  #
  # sops.secrets."wireless.env" = { };
  # networking.wireless.secretsFile = config.sops.secrets."wireless.env".path;
  #
  # networking.wireless.networks = {
  #   "Galaxy S22 Erik" = {
  #     pskRaw = "ext:s22_psk";
  #   };
  #   eduroam = {
  #     # pskRaw = "ext:eduroam_psk";
  #     auth = ''
  #       key_mgmt=WPA-EAP
  #       eap=PWD
  #       identity="ext:eduroam_identity"
  #       password="ext:eduroam_psk"
  #     '';
  #   };
  # };
}

# { config, pkgs, lib, ... }:
#
# with lib;
#
# let
#   cfg = config.networking.networkmanager;
#
#   getFileName = stringAsChars (x: if x == " " then "-" else x);
#
#   createWifi = ssid: opt: {
#     name = ''
#       NetworkManager/system-connections/${getFileName ssid}.nmconnection
#     '';
#     value = {
#       mode = "0400";
#       source = pkgs.writeText "${ssid}.nmconnection" ''
#         [connection]
#         id=${ssid}
#         type=wifi
#
#         [wifi]
#         ssid=${ssid}
#
#         [wifi-security]
#         ${optionalString (opt.psk != null) ''
#         key-mgmt=wpa-psk
#         psk=${opt.psk}''}
#       '';
#     };
#   };
#
#   keyFiles = mapAttrs' createWifi config.networking.wireless.networks;
# in
# {
#   config = mkIf cfg.enable {
#     environment.systemPackages = [
#     ];
#
#     networking.networkmanager.wifi.powersave = true;
#
#     networking.wireless.enable = false;
#     environment.etc = keyFiles;
#
#     systemd.services.NetworkManager-predefined-connections = {
#       restartTriggers = mapAttrsToList (name: value: value.source) keyFiles;
#       serviceConfig = {
#         Type = "oneshot";
#         RemainAfterExit = true;
#         ExecStart = "${pkgs.coreutils}/bin/true";
#         ExecReload = "${pkgs.networkmanager}/bin/nmcli connection reload";
#       };
#       reloadIfChanged = true;
#       wantedBy = [ "multi-user.target" ];
#     };
#   };
# }


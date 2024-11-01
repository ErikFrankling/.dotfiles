{ config, pkgs, lib, ... }: {

  environment.systemPackages = [
    pkgs.wpa_supplicant_gui
  ];

  powerManagement.enable = true;
  powerManagement.powertop.enable = true;

  services.auto-cpufreq.enable = true;
  services.auto-cpufreq.settings = {
    battery = {
      governor = "powersave";
      turbo = "never";
    };
    charger = {
      governor = "performance";
      turbo = "auto";
    };
  };

  # networking.networkmanager.wifi.powersave = true;
  # networking.networkmanager.wifi.backend = "iwd";

  # networking.wireless.dbusControlled = true;
  networking.networkmanager.enable = lib.mkForce true;
  # networking.networkmanager.enable = lib.mkForce false;
  # networking.wireless.enable = true;
  # networking.wireless.userControlled.enable = true;
  # users.extraUsers.erikf.extraGroups = [ "wheel" ];
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

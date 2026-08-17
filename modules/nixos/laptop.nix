{
  config,
  pkgs,
  lib,
  username,
  ...
}:
{

  environment.systemPackages = with pkgs; [
    # pkgs.wpa_supplicant_gui
    powertop
  ];

  powerManagement.enable = true;
  # powerManagement.powertop.enable = true;

  # services.tlp = {
  #   enable = true;
  #   settings = {
  #     CPU_SCALING_GOVERNOR_ON_AC = "performance";
  #     CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
  #
  #     CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
  #     CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
  #
  #     USB_AUTOSUSPEND = 0;
  #
  #    #  CPU_MIN_PERF_ON_AC = 0;
  #    #  CPU_MAX_PERF_ON_AC = 100;
  #    #  CPU_MIN_PERF_ON_BAT = 0;
  #    #  CPU_MAX_PERF_ON_BAT = 20;
  #    #
  #    # #Optional helps save long term battery health
  #    # START_CHARGE_THRESH_BAT0 = 40; # 40 and below it starts to charge
  #    # STOP_CHARGE_THRESH_BAT0 = 80; # 80 and above it stops charging
  #
  #   };
  # };

  # services.auto-cpufreq.enable = true;
  # services.auto-cpufreq.settings = {
  #   battery = {
  #     governor = "powersave";
  #     turbo = "never";
  #   };
  #   charger = {
  #     governor = "performance";
  #     turbo = "auto";
  #   };
  # };

  # services.udev.extraRules = ''
  #   # The example is enabling autosuspend for all USB devices except for keyboards and mice:
  #   ACTION=="add", SUBSYSTEM=="usb", ATTR{product}!="*Mouse", ATTR{product}!="*Keyboard", TEST=="power/control", ATTR{power/control}="auto"
  # '';

  # Default WiFi regulatory domain to SE. The MT7922 relies on the kernel
  # regdb (no firmware-managed regdomain), and cfg80211 falls back to WORLD
  # after every disconnect, where all of 6 GHz is no-IR — so every roam
  # attempt to a 6 GHz BSSID failed with "Authentication request to the
  # driver failed" and stalled traffic for seconds. A module-param regdom is
  # a persistent *user hint*, which survives those resets; AP country IEs
  # still refine it when abroad. Read at module load => needs a reboot.
  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=SE
  '';

  # networking.networkmanager.wifi.powersave = true;
  # networking.networkmanager.wifi.backend = "iwd";

  # networking.wireless.dbusControlled = true;
  # networking.networkmanager.enable = lib.mkForce true;
  # networking.networkmanager.enable = lib.mkForce false;
  # networking.wireless.enable = true;
  # networking.wireless.userControlled.enable = true;
  # users.extraUsers."${username}".extraGroups = [ "wheel" ];
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

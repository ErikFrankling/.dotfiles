{ ... }: {
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

  # networking.wireless.networks.eduroam = {
  #   auth = ''
  #     key_mgmt=WPA-EAP
  #     eap=PWD
  #     identity="erikfran@kth.se"
  #   '';
  # };
}

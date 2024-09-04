{ pkgs, ... }:

{
  imports = [
    ../../modules/home-manager
    ../../modules/home-manager/desktop.nix
    ../../modules/home-manager/print
  ];

  home.packages = with pkgs; [
    prismlauncher
  ];

  hyprland = {
    monitors = [
      {
        name = "DP-1";
        width = 3840;
        height = 2160;
        x = 0;
        scale = "2";
      }
      {
        name = "HDMI-A-1";
        width = 1920;
        height = 1080;
        x = -1920;
        scale = "1";
      }
    ];
    mouse = {
      sensitivity = "0.2";
      scroll_factor = "0.5";
    };
  };
}

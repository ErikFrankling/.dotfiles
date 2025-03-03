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
    initWindows = [
      {
        exec = "kitty tmux";
        monitor = "DP-1";
        workspace = 1;
      }
      {
        exec = "kitty tmux";
        monitor = "DP-1";
        workspace = 2;
      }
      {
        exec = "firefox";
        monitor = "DP-1";
        workspace = 3;
      }
      {
        exec = "webcord";
        monitor = "HDMI-A-1";
        workspace = 10;
      }
      {
        exec = "spotify";
        monitor = "HDMI-A-1";
        workspace = 10;
      }
    ];

    workspaces = [
      {
        ID = 1;
        monitor = "DP-1";
        default = true;
      }
      {
        ID = 2;
        monitor = "DP-1";
      }
      {
        ID = 3;
        monitor = "DP-1";
      }
      {
        ID = 10;
        monitor = "HDMI-A-1";
      }
    ];
  };
}

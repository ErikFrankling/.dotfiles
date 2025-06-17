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

  wayland.windowManager.hyprland.settings = {
    mouse = {
      sensitivity = "0.2";
      scroll_factor = "0.5";
    };

    device = [
      {
        name = "tshort-dactyl-manuform-(5x6)";
        kb_layout = "us";
      }
      {
        name = "logitech-g512-carbon-tactile";
        kb_layout = "se";
      }
    ];
  };

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
        exec = "obsidian";
        monitor = "HDMI-A-1";
        workspace = 9;
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
        ID = 9;
        monitor = "HDMI-A-1";
      }
      {
        ID = 10;
        monitor = "HDMI-A-1";
      }
    ];
  };
}

{ pkgs, ... }:

{
  imports = [
    ../../modules/home-manager
    ../../modules/home-manager/desktop.nix
    ../../modules/home-manager/print
  ];

  home.packages = with pkgs; [ prismlauncher ];

  home.sessionVariables = {
    # LIBSEAT_BACKEND = "logind";
    AQ_DRM_DEVICES = "/dev/dri/card1";
    # HYPRLAND_TRACE = "1";
    # AQ_TRACE = "1";
    # MESA_LOADER_DRIVER_OVERRIDE="radeonsi";
    # EGL_PLATFORM="GBM";
    # WLR_NO_HARDWARE_CURSORS="1";
  };

  wayland.windowManager.hyprland.settings = {
    # mouse = {
    #   sensitivity = "0.2";
    #   scroll_factor = "0.5";
    # };

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

  hyprland =
    let
      monitor_1 = "DP-3";
      monitor_2 = "HDMI-A-1";
    in
    {
      monitors = [
        {
          name = monitor_1;
          width = 3840;
          height = 2160;
          # width = 2560;
          # height = 1440;
          refreshRate = 60;
          x = 1920;
          # x = 2560;
          scale = "2";
        }
        {
          name = monitor_2;
          width = 3840;
          height = 2160;
          # width = 2560;
          # height = 1440;
          refreshRate = 60;
          x = 0;
          scale = "2";
        }
      ];
      initWindows = [
        {
          exec = "kitty";
          monitor = monitor_1;
          workspace = 1;
        }
        {
          exec = "kitty";
          monitor = monitor_1;
          workspace = 2;
        }
        {
          exec = "firefox";
          monitor = monitor_1;
          workspace = 3;
        }
        {
          exec = "obsidian";
          monitor = monitor_2;
          workspace = 9;
        }
        {
          exec = "webcord";
          monitor = monitor_2;
          workspace = 10;
        }
        {
          exec = "spotify";
          monitor = monitor_2;
          workspace = 10;
        }
      ];

      workspaces = [
        {
          ID = 1;
          monitor = monitor_1;
          default = true;
        }
        {
          ID = 2;
          monitor = monitor_1;
        }
        {
          ID = 3;
          monitor = monitor_1;
        }
        {
          ID = 9;
          monitor = monitor_2;
        }
        {
          ID = 10;
          monitor = monitor_2;
          # default = true;
        }
      ];
    };
}

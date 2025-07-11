{
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ../../modules/home-manager
    ../../modules/home-manager/desktop.nix
    # ../../modules/home-manager/print
  ];

  nixpkgs.overlays = [
    # (
    #   final: prev: {
    #     # Your own overlays...
    #   }
    # )
    inputs.ericsson-tools.overlays.default
  ];

  home.packages = with pkgs; [
    alacritty
    foot
    ericsson-rcli
    cloudflared
  ];

  # home.sessionVariables = {
  #   # LIBSEAT_BACKEND = "logind";
  #   AQ_DRM_DEVICES = "/dev/dri/card1";
  #   # HYPRLAND_TRACE = "1";
  #   # AQ_TRACE = "1";
  #   # MESA_LOADER_DRIVER_OVERRIDE="radeonsi";
  #   # EGL_PLATFORM="GBM";
  #   # WLR_NO_HARDWARE_CURSORS="1";
  # };

  # wayland.windowManager.hyprland.settings = {
  #   # mouse = {
  #   #   sensitivity = "0.2";
  #   #   scroll_factor = "0.5";
  #   # };
  #
  #   device = [
  #     # {
  #     #   name = "tshort-dactyl-manuform-(5x6)";
  #     #   kb_layout = "us";
  #     # }
  #     {
  #       name = "at-translated-set-2-keyboard";
  #       kb_layout = "se";
  #     }
  #   ];
  # };

  # hyprland = {
  #   monitors = [
  #     {
  #       name = "Virtual-1";
  #       width = 1920;
  #       height = 1080;
  #       x = 0;
  #       scale = "1";
  #     }
  #     # {
  #     #   name = "DP-2";
  #     #   width = 3840;
  #     #   height = 2160;
  #     #   refreshRate = 60;
  #     #   x = 0;
  #     #   scale = "2";
  #     # }
  #   ];
  #   # initWindows = [
  #   #   {
  #   #     exec = "kitty";
  #   #     monitor = "DP-1";
  #   #     workspace = 1;
  #   #   }
  #   #   {
  #   #     exec = "kitty";
  #   #     monitor = "DP-1";
  #   #     workspace = 2;
  #   #   }
  #   #   {
  #   #     exec = "firefox";
  #   #     monitor = "DP-1";
  #   #     workspace = 3;
  #   #   }
  #   #   {
  #   #     exec = "obsidian";
  #   #     monitor = "DP-2";
  #   #     workspace = 9;
  #   #   }
  #   #   {
  #   #     exec = "webcord";
  #   #     monitor = "DP-2";
  #   #     workspace = 10;
  #   #   }
  #   #   {
  #   #     exec = "spotify";
  #   #     monitor = "DP-2";
  #   #     workspace = 10;
  #   #   }
  #   # ];
  #   #
  #   # workspaces = [
  #   #   {
  #   #     ID = 1;
  #   #     monitor = "DP-1";
  #   #     default = true;
  #   #   }
  #   #   {
  #   #     ID = 2;
  #   #     monitor = "DP-1";
  #   #   }
  #   #   {
  #   #     ID = 3;
  #   #     monitor = "DP-1";
  #   #   }
  #   #   {
  #   #     ID = 9;
  #   #     monitor = "DP-2";
  #   #   }
  #   #   {
  #   #     ID = 10;
  #   #     monitor = "DP-2";
  #   #     # default = true;
  #   #   }
  #   # ];
  # };
}

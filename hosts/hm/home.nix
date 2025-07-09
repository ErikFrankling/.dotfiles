{ pkgs, inputs, ... }:

{
  imports = [
    ../../modules/home-manager
    #../../modules/home-manager/desktop.nix
    #../../modules/home-manager/print
  ];

  targets.genericLinux.enable = true;

  nixpkgs.overlays = [
    # (
    #   final: prev: {
    #     # Your own overlays...
    #   }
    # )
    inputs.ericsson-tools.overlays.default
  ];

  home.packages = with pkgs; [
    ericsson-rcli
    cloudflared
  ];
  #wayland.windowManager.hyprland.settings = {
  #  device = [{
  #    name = "pixa3854:00-093a:0274-touchpad";
  #    sensitivity = "0.2";
  #  }];
  #};

  #hyprland = {
  #  monitors = [
  #    {
  #      name = "eDP-1";
  #      width = 2880;
  #      height = 1920;
  #      scale = "2";
  #      refreshRate = 120;
  #    }
  #    {
  #      name = "DP-4";
  #      width = 3840;
  #      height = 2160;
  #      scale = "2";
  #      refreshRate = 60;
  #      x = 1440;
  #      y = 0;
  #      # enabled = true;
  #    }
  #  ];

  #  initWindows = [
  #    {
  #      exec = "kitty";
  #      monitor = "eDP-1";
  #      workspace = 1;
  #    }
  #    {
  #      exec = "kitty";
  #      monitor = "eDP-1";
  #      workspace = 2;
  #    }
  #    {
  #      exec = "firefox";
  #      monitor = "eDP-1";
  #      workspace = 3;
  #    }
  #    {
  #      exec = "obsidian";
  #      monitor = "eDP-1";
  #      workspace = 4;
  #    }
  #    {
  #      exec = "webcord";
  #      monitor = "eDP-1";
  #      workspace = 10;
  #    }
  #    {
  #      exec = "spotify";
  #      monitor = "eDP-1";
  #      workspace = 10;
  #    }
  #  ];

  #  # workspaces = [
  #  #   {
  #  #     ID = 1;
  #  #     monitor = "eDP-1";
  #  #     default = true;
  #  #   }
  #  #   {
  #  #     ID = 2;
  #  #     monitor = "eDP-1";
  #  #   }
  #  #   {
  #  #     ID = 3;
  #  #     monitor = "eDP-1";
  #  #   }
  #  #   {
  #  #     ID = 4;
  #  #     monitor = "eDP-1";
  #  #   }
  #  #   {
  #  #     ID = 10;
  #  #     monitor = "eDP-1";
  #  #   }
  #  # ];
  #};
}

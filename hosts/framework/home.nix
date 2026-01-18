{ ... }:

{
  imports = [
    ../../modules/home-manager
    ../../modules/home-manager/desktop.nix
    ../../modules/home-manager/print
  ];

  wayland.windowManager.hyprland.settings = {
    device = [
      {
        name = "pixa3854:00-093a:0274-touchpad";
        sensitivity = "0.2";
      }
    ];
  };

  services.kanshi = {
    enable = true;
    systemdTarget = "hyprland-session.target";

    settings = [
      {
        profile.name = "undocked";
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "enable";
          }
        ];
      }
      {
        profile.name = "docked";
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "disable";
          }
          {
            criteria = "DP-9"; # Change to your monitor name
            status = "enable";
          }
          {
            criteria = "DP-10"; # Change to your second monitor name
            status = "enable";
          }
        ];
      }
    ];
  };

  hyprland = {
    keyboards = [
      {
        name = "erik-frankling-dactyl_manuform_5x6_64";
        kb_layout = "us, se";
        multilang = true;
      }
      {
        name = "at-translated-set-2-keyboard";
        kb_layout = "us, se";
        multilang = true;
      }
    ];
    monitors = [
      {
        name = "eDP-1";
        width = 2880;
        height = 1920;
        scale = "2";
        refreshRate = 120;
      }
      {
        name = "DP-9";
        width = 3840;
        height = 2160;
        scale = "2";
        refreshRate = 60;
        x = 1440;
        y = 0;
        # enabled = true;
      }
      {
        name = "DP-10";
        width = 3840;
        height = 2160;
        scale = "2";
        refreshRate = 60;
        x = 1440;
        y = 0;
        # enabled = true;
      }
    ];

    initWindows = [
      {
        exec = "kitty";
        monitor = "eDP-1";
        workspace = 1;
      }
      {
        exec = "kitty";
        monitor = "eDP-1";
        workspace = 2;
      }
      {
        exec = "firefox";
        monitor = "eDP-1";
        workspace = 3;
      }
      {
        exec = "obsidian";
        monitor = "eDP-1";
        workspace = 4;
      }
      {
        exec = "webcord";
        monitor = "eDP-1";
        workspace = 10;
      }
      {
        exec = "spotify";
        monitor = "eDP-1";
        workspace = 10;
      }
    ];

    # workspaces = [
    #   {
    #     ID = 1;
    #     monitor = "eDP-1";
    #     default = true;
    #   }
    #   {
    #     ID = 2;
    #     monitor = "eDP-1";
    #   }
    #   {
    #     ID = 3;
    #     monitor = "eDP-1";
    #   }
    #   {
    #     ID = 4;
    #     monitor = "eDP-1";
    #   }
    #   {
    #     ID = 10;
    #     monitor = "eDP-1";
    #   }
    # ];
  };
}

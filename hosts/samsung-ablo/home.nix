{
  inputs,
  ...
}:

{
  imports = [
    ../../modules/home-manager
    ../../modules/home-manager/desktop.nix
    ../../modules/home-manager/print
    ../../modules/home-manager/auto-update
    ../../modules/home-manager/machines
    ../../modules/home-manager/notify # phone notifications skill
    ../../modules/home-manager/bro
    ../../modules/home-manager/speak # `speak` tool: refuses here (PC speakers only)
    inputs.time.homeManagerModules.agent-v2
    ./t3code.nix # work agents run here, not on the pc
  ];

  # Time v2: screen, input, lid, lock, battery and Wi-Fi each minute, to the
  # local Alloy (queued on disk while away from home).
  services.time-agent-v2 = {
    enable = true;
    device = "samsung-ablo";
  };

  # Nothing on the iGPU worth watching (same as the framework).
  programs.erikshell.metrics.gpu = false;

  # At the desk the KVM gives the laptop the pc's two screens; the built-in
  # one turns off, as on the framework. Matched by model, not connector: the
  # KVM's DP-n names change each time it switches.
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
            criteria = "Samsung Electric Company U28E590 *";
            status = "enable";
          }
          {
            criteria = "Samsung Electric Company U28D590 *";
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
        height = 1800;
        scale = "2";
        refreshRate = 120;
        x = 0;
        y = 0;
      }
      # The KVM cannot carry both screens at 4K/60. These are the modes
      # verified together on the laptop; the U28D590 has no 4K/30 mode.
      {
        name = "desc:Samsung Electric Company U28E590";
        width = 3840;
        height = 2160;
        refreshRate = 30;
        scale = "2";
        x = 0;
        y = 0;
      }
      {
        name = "desc:Samsung Electric Company U28D590";
        width = 2560;
        height = 1440;
        refreshRate = 60;
        scale = "1.333333";
        x = 1920;
        y = 0;
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
    ];
  };
}

{ inputs, pkgs, ... }: {
  # add the home manager module
  imports = [ inputs.ags.homeManagerModules.default ];

  home.packages = with pkgs; [
    inputs.ags.packages.${pkgs.system}.io
    inputs.ags.packages.${pkgs.system}.notifd
    libnotify
  ];

  programs.ags = {
    enable = true;

    # symlink to ~/.config/ags
    configDir = ../ags;

    # additional packages to add to gjs's runtime
    extraPackages = with pkgs;
      [ fzf ] ++ (with inputs.ags.packages.${pkgs.system}; [
        hyprland
        battery
        mpris
        network
        tray
        wireplumber
        notifd
      ]);
  };
}

# deps:
# Battery library.
# Hyprland library.
# Mpris library.
# Network library.
# Tray library.
# WirePlumber library.

# ags flake package outputs:
# │   └───x86_64-linux
# │       ├───ags: package 'ags-2.3.0'
# │       ├───agsFull: package 'ags-2.3.0'
# │       ├───apps: package 'astal-apps-0.1.0'
# │       ├───astal3: package 'astal3-3.0.0'
# │       ├───astal4: package 'astal4-4.0.0'
# │       ├───auth: package 'astal-auth-0.1.0'
# │       ├───battery: package 'astal-battery-0.1.0'
# │       ├───bluetooth: package 'astal-bluetooth-0.1.0'
# │       ├───cava: package 'astal-cava-0.1.0'
# │       ├───default: package 'ags-2.3.0'
# │       ├───docs: package 'docs'
# │       ├───gjs: package 'astal-gjs'
# │       ├───greet: package 'astal-greet-0.1.0'
# │       ├───hyprland: package 'astal-hyprland-0.1.0'
# │       ├───io: package 'astal-0.1.0'
# │       ├───mpris: package 'astal-mpris-0.1.0'
# │       ├───network: package 'astal-network-0.1.0'
# │       ├───notifd: package 'astal-notifd-0.1.0'
# │       ├───powerprofiles: package 'astal-powerprofiles-0.1.0'
# │       ├───river: package 'astal-river-0.1.0'
# │       ├───tray: package 'astal-tray-0.1.0'
# │       └───wireplumber: package 'astal-wireplumber-0.1.0'

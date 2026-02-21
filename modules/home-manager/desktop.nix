{
  pkgs,
  otherPkgs,
  inputs,
  # system,
  ...
}:

{
  imports = [
    # ./firefox.nix
    ./waybar
    ./hyprland
    # ./eww
    # ./ags
    # ./thunderbird.nix
    ./zen.nix
    ./kitty.nix
    ./ai.nix
  ];

  home.packages = with pkgs; [
    webcord
    # otherPkgs.pkgsStable.webcord
    # otherPkgs.pkgsMaster.spotifywm
    spotifywm
    # spotify-qt
    pavucontrol
    otherPkgs.pkgsStable.google-chrome
    # gparted
    # virtualbox
    syncthingtray-minimal
    obsidian
    # otherPkgs.pkgsStable.obsidian
    # otherPkgs.pkgsMaster.obsidian
    # (inputs.ags-shell.packages.${system}.my-shell)
    inputs.ags-shell.packages."x86_64-linux".default
    mattermost-desktop
  ];

  nixpkgs.config.permittedInsecurePackages = [
    "electron-36.9.5"
  ];

  services.syncthing.tray.enable = true;
}

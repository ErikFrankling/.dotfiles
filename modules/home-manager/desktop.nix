{ pkgs, pkgsMaster, ... }:

{
  imports = [
    # ./firefox.nix
    ./waybar
    ./hyprland
    # ./eww
    ./ags
    # ./thunderbird.nix
  ];

  home.packages = with pkgs; [
    webcord
    pkgsMaster.spotifywm
    # spotify-qt
    pavucontrol
    google-chrome
    # gparted
    # virtualbox
    syncthingtray-minimal
    obsidian
  ];

  services.syncthing.tray.enable = true;
  programs.kitty.enable = true;
}

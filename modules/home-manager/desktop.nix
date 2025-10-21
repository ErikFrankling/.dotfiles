{ pkgs, otherPkgs, ... }:

{
  imports = [
    # ./firefox.nix
    ./waybar
    ./hyprland
    # ./eww
    ./ags
    # ./thunderbird.nix
    ./zen.nix
  ];

  home.packages = with pkgs; [
    webcord
    otherPkgs.pkgsMaster.spotifywm
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

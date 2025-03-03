{ pkgs, ... }:

{
  imports = [
    ./firefox.nix
    ./waybar
    ./hyprland.nix
    # ./eww
    # ./thunderbird.nix
  ];

  home.packages = with pkgs; [
    webcord
    spotifywm
    # spotify-qt
    pavucontrol
    google-chrome
    gparted
    # virtualbox
  ];

  programs.kitty.enable = true;
}

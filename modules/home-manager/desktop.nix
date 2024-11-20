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
    obs-studio
    google-chrome
    gparted
  ];

  programs.kitty.enable = true;
}

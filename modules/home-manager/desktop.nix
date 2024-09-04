{ pkgs, ... }:

{
  imports = [
    ./firefox.nix
    ./waybar
    ./hyprland.nix
    # ./eww
  ];

  home.packages = with pkgs; [
    thunderbird
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

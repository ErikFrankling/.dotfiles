{ pkgs, ... }:

{
  imports = [
    ./firefox.nix
    ./waybar
    ./hyprland
    # ./eww
    ./ags
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

{ pkgs, ... }:

{
  imports = [
    ./firefox.nix
    ./waybar
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
  ];

  programs.kitty.enable = true;
}

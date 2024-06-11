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
    # spotify
    pavucontrol
    obs-studio
  ];

  programs.kitty.enable = true;
}

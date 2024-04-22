{ pkgs, ... }:

{
    imports = [
        ./firefox.nix
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

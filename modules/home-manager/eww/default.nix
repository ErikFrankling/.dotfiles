{ pkgs, ... }:

{
  home.packages = with pkgs; [ bash gawk socat jq python3 ];

  programs.eww = {
    enable = true;
    # package = pkgs.eww-wayland;
    configDir = ../eww;
  };
}

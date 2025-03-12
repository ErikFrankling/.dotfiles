{ pkgs, ... }:

{
  home.packages = with pkgs; [
    jq
  ];

  home.file = {
    ".config/waybar/cofig.jsonc".source = ./config.jsonc;
  };

  programs.waybar = {
    enable = true;
    # systemd.enable = true;

    style = ./style.css;
    # settings = builtins.readFile ./config.jsonc;
  };
}

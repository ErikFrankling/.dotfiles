{ pkgs, ... }:

{
  home.packages = with pkgs; [ jq ];

  home.file = {
    ".config/waybar/config.jsonc".source = ./config.jsonc;
    ".local/bin/gpu-util.sh" = {
      source = ./scripts/gpu-util.sh;
      executable = true;
    };
    ".local/bin/gpu-vram.sh" = {
      source = ./scripts/gpu-vram.sh;
      executable = true;
    };
  };

  programs.waybar = {
    enable = true;
    systemd.enable = true;

    style = ./style.css;
    # settings = builtins.readFile ./config.jsonc;
  };
}

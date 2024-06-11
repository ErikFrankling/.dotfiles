{ ... }:

{
  home.file = {
    ".config/waybar/cofig.jsonc".source = ./config.jsonc;
  };

  programs.waybar = {
    enable = true;
    # systemd.enable = true;

    # settings = builtins.readFile ./config.json;
    style = ./style.css;
  };
}

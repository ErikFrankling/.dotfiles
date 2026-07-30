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
    ".local/bin/network-status.sh" = {
      source = ./scripts/network-status.sh;
      executable = true;
    };
    ".local/bin/swap-usage.sh" = {
      source = ./scripts/swap-usage.sh;
      executable = true;
    };
  };

  programs.waybar = {
    enable = true;
    systemd.enable = true;

    style = ./style.css;
    # settings = builtins.readFile ./config.jsonc;
  };

  # style.css @imports the palette the shell publishes, but nothing tells GTK to
  # look at it again. SIGUSR2 makes waybar re-read its style.
  systemd.user.paths.waybar-theme = {
    Unit.Description = "Reload waybar when the published palette changes";
    Path.PathChanged = "%h/.cache/wal/colors-waybar.css";
    Install.WantedBy = [ "paths.target" ];
  };

  systemd.user.services.waybar-theme = {
    Unit.Description = "Reload waybar's style";
    Service = {
      Type = "oneshot";
      # waybar's own unit already maps reload onto SIGUSR2. Leading "-" so a
      # theme change with waybar not running is not a failure.
      ExecStart = "-${pkgs.systemd}/bin/systemctl --user reload waybar.service";
    };
  };
}

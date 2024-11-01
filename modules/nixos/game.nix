{ pkgs, ... }:

{

  environment.systemPackages = with pkgs; [
    heroic
    # grapejuice
    mangohud
  ];

  programs.steam = {
    enable = true;
  };

  hardware.opengl.driSupport32Bit = true;
  programs.steam.gamescopeSession.enable = true;
}

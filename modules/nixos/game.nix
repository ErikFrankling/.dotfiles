{ pkgs, ... }:

{

  environment.systemPackages = with pkgs; [
    heroic
    # grapejuice
    mangohud
    gamemode
  ];

  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
  };

  hardware.graphics.enable32Bit = true;
}

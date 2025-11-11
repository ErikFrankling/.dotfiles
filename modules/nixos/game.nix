{ pkgs, otherPkgs, ... }:

{

  environment.systemPackages = with pkgs; [
    # FIX: role this back. was causing electron rebuild.
    otherPkgs.pkgsStable.heroic
    # heroic
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

{ pkgs, ... }:

{

  environment.systemPackages = with pkgs; [
    heroic
  ];

  programs.steam = {
    enable = true;
  };

  programs.steam.gamescopeSession.enable = true;
}

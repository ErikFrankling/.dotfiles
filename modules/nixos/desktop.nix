{ pkgs, ... }:

{
  imports = [
    ./bluetooth.nix
    ./sound.nix
    ./hyprland.nix
  ];

  environment.systemPackages = with pkgs; [
    xdg-utils
    wlvncc
    xorg.xlsclients
    # tightvnc
    # tigervnc
    networkmanagerapplet
  ];
  nixpkgs.config.permittedInsecurePackages = [
    "tightvnc-1.3.10"
  ];

  programs.nm-applet.enable = true;
  security.polkit.enable = true;
}

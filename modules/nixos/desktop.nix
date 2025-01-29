{ pkgs, ... }:

{
  imports = [
    ./bluetooth.nix
    ./sound.nix
    ./hyprland.nix
    ./projects/matlab.nix
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

  virtualisation.vmware.host.enable = true;
  programs.nm-applet.enable = true;
  security.polkit.enable = true;
}

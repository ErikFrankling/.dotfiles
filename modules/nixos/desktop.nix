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
  ];
  nixpkgs.config.permittedInsecurePackages = [
    "tightvnc-1.3.10"
  ];

  security.polkit.enable = true;
}

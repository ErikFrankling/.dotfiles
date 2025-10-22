{
  pkgs,
  otherPkgs,
  inputs,
  # system,
  ...
}:

{
  imports = [
    # ./firefox.nix
    ./waybar
    ./hyprland
    # ./eww
    # ./ags
    # ./thunderbird.nix
    ./zen.nix
  ];

  home.packages = with pkgs; [
    webcord
    otherPkgs.pkgsMaster.spotifywm
    # spotify-qt
    pavucontrol
    google-chrome
    # gparted
    # virtualbox
    syncthingtray-minimal
    obsidian
    # (inputs.ags-shell.packages.${system}.my-shell)
    inputs.ags-shell.packages."x86_64-linux".default
  ];

  services.syncthing.tray.enable = true;
  programs.kitty.enable = true;
}

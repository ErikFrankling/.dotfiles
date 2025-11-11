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
    ./kitty.nix
    ./ai.nix
  ];

  home.packages = with pkgs; [
    webcord
    # otherPkgs.pkgsMaster.spotifywm
    spotifywm
    # spotify-qt
    pavucontrol
    google-chrome
    # gparted
    # virtualbox
    syncthingtray-minimal
    # FIX: role this back. was causing electron rebuild.
    otherPkgs.pkgsStable.obsidian
    # obsidian
    # (inputs.ags-shell.packages.${system}.my-shell)
    inputs.ags-shell.packages."x86_64-linux".default
  ];

  nixpkgs.config.permittedInsecurePackages = [
    "electron-36.9.5"
  ];

  services.syncthing.tray.enable = true;
}

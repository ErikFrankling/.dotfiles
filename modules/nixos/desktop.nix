{
  pkgs,
  username,
  inputs,
  ...
}:

{
  imports = [
    ./bluetooth.nix
    ./sound.nix
    ./hyprland.nix
    # ./projects/matlab.nix
    ./obs.nix
    ./firefox.nix
  ];

  nixpkgs.overlays = [ inputs.claude-desktop.overlays.default ];

  environment.systemPackages = with pkgs; [
    xdg-utils
    wlvncc
    xlsclients
    # tightvnc
    # tigervnc
    networkmanagerapplet
    gparted
    gthumb
    vlc
    xrdb
    inputs.helium.packages.${pkgs.stdenv.hostPlatform.system}.default
    # inputs.claude-desktop.packages.${system}.claude-desktop-fhs
    # pkgs.claude-desktop-fhs
  ];
  # nixpkgs.config.permittedInsecurePackages = [ "tightvnc-1.3.10" ];

  nixpkgs.config.permittedInsecurePackages = [
    "electron-36.9.5"
  ];

  programs.kdeconnect.enable = true;
  # programs.ladybird.enable = true;
  # virtualisation.vmware.host.enable = true;
  programs.nm-applet.enable = true;
  security.polkit.enable = true;

  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
    dumpcap.enable = true;
    usbmon.enable = true;
  };

  users.extraUsers.${username}.extraGroups = [ "wireshark" ];
  users.users.${username}.extraGroups = [ "wireshark" ];

}

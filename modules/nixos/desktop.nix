{ pkgs, username, ... }:

{
  imports = [
    ./bluetooth.nix
    ./sound.nix
    ./hyprland.nix
    # ./projects/matlab.nix
    ./obs.nix
  ];

  environment.systemPackages = with pkgs; [
    xdg-utils
    wlvncc
    xorg.xlsclients
    # tightvnc
    # tigervnc
    networkmanagerapplet
    gparted
    gthumb
    vlc
  ];
  nixpkgs.config.permittedInsecurePackages = [ "tightvnc-1.3.10" ];

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

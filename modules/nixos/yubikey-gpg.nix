{ config, lib, pkgs, ... }:

{
  programs.ssh.startAgent = false;

  services.pcscd.enable = true;

  environment.systemPackages = with pkgs; [
    gnupg
    yubikey-personalization
    pinentry-curses
    pinentry-gtk2
  ];

  programs.gnupg.agent = {
    enable = true;
    pinentryFlavor = "gtk2";
    enableSSHSupport = true;
  };

  # environment.shellInit = ''
  #   gpg-connect-agent /bye
  #   export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
  # '';

  services.udev.packages = with pkgs; [ yubikey-personalization ];
}

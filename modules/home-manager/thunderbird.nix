{ config, pkgs, lib, ... }:

let
  signature = {
    text = "Mvh Erik Frankling";
    showSignature = "append";
  };
in {
  programs.thunderbird = {
    enable = true;
    # profiles.erikf = {
    #   isDefault = true;
    # };
  };

  accounts.email.accounts.erikf = {
    realName = "Erik Frankling";
    address = "erik.frankling@frankling.se";
    userName = "erik.frankling";
    # primary = true;
    imap = {
      host = "outlook.office365.com";
      port = 993;
    };
    # passwordCommand = "cat ${config.age.secrets.microsoft.path}";
    thunderbird = {
      enable = true;
      # profiles = [ "erikf" ];
    };
    inherit signature;
  };

  imports = [ ];

  home.packages = with pkgs; [ ];

  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # ".config/nvim/" = {
    #   source = ../../nvim;
    #   recursive = true;
    # };

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  home.sessionVariables = {
    # EDITOR = lib.mkForce "/home/erikf/.nix-profile/bin/nvim";
  };
}

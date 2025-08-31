{
  config,
  pkgs,
  lib,
  username,
  inputs,
  ...
}:

{
  imports = [
    # ./nixvim
    ./fish.nix
    ./tmux.nix
    ./scripts
    ./zellij
  ];

  nixpkgs.config.allowUnfree = true;

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "${username}";
  home.homeDirectory = "/home/${username}";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "25.05"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
    age
    dos2unix
    wget
    inputs.nvim.packages.${system}.nvim
    btop
    fzf
    ripgrep
    nix-prefetch-github
    jq
    tree
    powershell
    sshfs
    kubernetes-helm
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
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

  programs = {
    git = {
      enable = true;
      package = pkgs.gitFull;

      userName = "Erik Frankling";
      userEmail = "erik.frankling@frankling.se";

      extraConfig = {
        pull.rebase = false;
        credential.helper = "libsecret";
      };

      includes = [
        {
          condition = "gitdir:~/work/**";
          contents = {
            user.email = "erik.frankling@ericsson.com";
          };
        }
      ];
    };

    direnv = {
      enable = true;
      # enableFishIntegration = true;
      nix-direnv.enable = true;
    };
  };

  nix.package = lib.mkForce pkgs.nix;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  home.sessionVariables = {
    # EDITOR = lib.mkForce "/home/${username}/.nix-profile/bin/nvim";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}

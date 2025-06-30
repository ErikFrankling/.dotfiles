{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [ ];

  home.packages = with pkgs; [ ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    viAlias = true;
    vimdiffAlias = true;

    extraLuaConfig = lib.fileContents ./init.lua;

    plugins = with pkgs.vimPlugins; [
      # yankring
      # vim-nix
      # {
      #   plugin = vim-startify;
      #   config = "let g:startify_change_to_vcs_root = 0";
      # }
    ];
  };

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
    # EDITOR = lib.mkForce "/home/${username}/.nix-profile/bin/nvim";
  };
}

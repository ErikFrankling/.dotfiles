{ inputs, pkgs, ... }:
{
  # add the home manager module
  imports = [ inputs.ags.homeManagerModules.default ];

  home.packages = [
    inputs.ags.packages.${pkgs.system}.io
    inputs.ags.packages.${pkgs.system}.notifd
  ];

  programs.ags = {
    enable = true;

    # symlink to ~/.config/ags
    configDir = ../ags;

    # additional packages to add to gjs's runtime
    extraPackages = with pkgs; [
      inputs.ags.packages.${pkgs.system}.agsFull
      fzf
    ];
  };
}

{
  pkgs,
  inputs,
  otherPkgs,
  ...
}:

# let
#     # pkgs = import (builtins.fetchTarball {
#     #     url = "https://github.com/NixOS/nixpkgs/archive/c792c60b8a97daa7efe41a6e4954497ae410e0c1.tar.gz";
#     #     sha256 = "sha256:1kbdg5ziq6w4jls5wjvp4ddpww39zzm0pr8chz97qdj1l19pa7zn";
#     # }) {};
#
#     pkgs = import (builtins.fetchGit {
#          # Descriptive name to make the store path easier to identify
#          name = "my-old-revision";
#          url = "https://github.com/NixOS/nixpkgs/";
#          ref = "refs/heads/nixpkgs-unstable";
#          rev = "c792c60b8a97daa7efe41a6e4954497ae410e0c1";
#      }) {};
#
#     openscad-2024 = pkgs.openscad-unstable;
# in
{

  home.packages = with pkgs; [
    otherPkgs.pkgsStable.prusa-slicer
    # prusa-slicer
    # openscad
    # openscad-2024
    # TODO: use openscad-unstable when it is no longer broken. it has much faster rendering
    openscad-unstable
  ];
  # home.file = {
  #   ".config/PrusaSlicer/" = {
  #     source = ./PrusaSlicer;
  #     recursive = true;
  #   };
  # };
  # use syncthing instead
}

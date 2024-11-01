{ pkgs, inputs, ... }: {
  home.packages = with pkgs; [
    prusa-slicer
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

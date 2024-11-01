{ pkgs, inputs, ... }: {
  home.packages = with pkgs; [
    prusa-slicer
  ];
  home.file = {
    ".config/PrusaSlicer/" = {
      source = ./PrusaSlicer;
      recursive = true;
    };
  };
}

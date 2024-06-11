{ pkgs, inputs, ... }: {
  home.packages = with pkgs; [
    prusa-slicer
  ];
}

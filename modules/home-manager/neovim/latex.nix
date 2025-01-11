{ pkgs, ... }: {
  config.programs.nixvim.plugins.vimtex = {
    enable = true;
  };
  config.home.packages = with pkgs; [
    texliveMedium
    termpdfpy
  ];
}

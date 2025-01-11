{ pkgs, ... }: {
  config.programs.nixvim.plugins.vimtex = {
    enable = true;
  };
}

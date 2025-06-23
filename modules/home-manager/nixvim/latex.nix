{ pkgs, ... }: {
  config.programs.nixvim.plugins = {
    cmp-vimtex.enable = true;
    cmp-latex-symbols.enable = true;
    vimtex = { enable = true; };
  };
  config.home.packages = with pkgs; [ texliveMedium termpdfpy ];
}

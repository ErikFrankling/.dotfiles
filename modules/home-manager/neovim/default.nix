{ pkgs, ... }: {
  # Import all your configuration modules here
  imports = [
    ./lsp.nix
    ./treesitter.nix
    ./keymaps.nix
    ./completions.nix
    ./telescope.nix
  ];

  config = {
    programs.nixvim = {
      enable = true;
      globals.mapleader = " ";
      options = {
        background = "dark";
        number = true;
        relativenumber = true;

        tabstop = 4;
        softtabstop = -1;
        shiftwidth = 4;
        expandtab = true;

        foldmethod = "expr";
        foldlevelstart = 99;
      };

      colorschemes.base16 = {
        enable = true;
        useTruecolor = true;
        colorscheme = "material-darker";
      };

      plugins = {
        barbar = {
          enable = true;
          keymaps = {
            silent = true;
            previous = "<leader>tk";
            next = "<leader>tj";
            movePrevious = "<leader>th";
            moveNext = "<leader>tl";
            goTo1 = "<leader>t1";
            goTo2 = "<leader>t2";
            goTo3 = "<leader>t3";
            goTo4 = "<leader>t4";
            goTo5 = "<leader>t5";
            goTo6 = "<leader>t6";
            goTo7 = "<leader>t7";
            goTo8 = "<leader>t8";
            goTo9 = "<leader>t9";
            last = "<leader>tL";
            close = "<leader>tq";
          };
          sidebarFiletypes = { NvimTree = true; };
        };

        cursorline = {
          enable = true;
          cursorline = {
            enable = true;
            timeout = 0;
            number = true;
          };
          cursorword = {
            enable = true;
            hl = { underline = true; };
          };
        };

        gitgutter.enable = true;

        lualine = {
          enable = true;
          iconsEnabled = true;
          extensions = [ "nvim-tree" ];
        };

        noice = {
          enable = true;
          presets = {
            bottom_search = true;
            command_palette = true;
            lsp_doc_border = true;
          };
        };
        nvim-autopairs.enable = true;
        nvim-tree.enable = true;

        packer = {
          enable = true;
          plugins =
            [ "Mofiqul/dracula.nvim" "fneu/breezy" "hrsh7th/cmp-nvim-lsp" ];
        };

        which-key = {
          enable = true;
          showKeys = true;
        };
      };

      extraPlugins = with pkgs.vimPlugins; [ ];
    };
  };
}



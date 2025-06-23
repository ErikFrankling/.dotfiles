{ pkgs, inputs, ... }: {
  imports = [
    # For home-manager
    inputs.nixvim.homeManagerModules.nixvim
    ./lsp.nix
    ./treesitter.nix
    ./keymaps.nix
    ./completions.nix
    ./telescope.nix
    # ./autoformat.nix
    ./latex.nix
  ];

  config.programs.nixvim = {
    enable = true;
    defaultEditor = true;
    # exstraConfigLua = builtins.readFile ./init.lua;
    autoCmd = [{
      event = "FileType";
      pattern = "nix";
      command = "setlocal tabstop=2 shiftwidth=2";
    }];
    clipboard.register = "unnamedplus";

    globals = {
      mapleader = " ";
      maplocalleader = " ";
    };

    # keymaps = [
    #   {
    #     action = "<cmd>w<CR>";
    #     key = "<C-a>";
    #     options = {
    #       # silent = true;
    #     };
    #   }
    # ];

    opts = {

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

    colorschemes.onedark.enable = true;

    # colorschemes.base16 = {
    #   enable = true;
    #   options.termguicolors = true;
    #   colorscheme = "material-darker";
    # };

    plugins = {
      markdown-preview.enable = true;
      comment.enable = true;
      # barbar = {
      #   enable = true;
      #   keymaps = {
      #     previous = "<leader>tk";
      #     next = "<leader>tj";
      #     movePrevious = "<leader>th";
      #     moveNext = "<leader>tl";
      #     goTo1 = "<leader>t1";
      #     goTo2 = "<leader>t2";
      #     goTo3 = "<leader>t3";
      #     goTo4 = "<leader>t4";
      #     goTo5 = "<leader>t5";
      #     goTo6 = "<leader>t6";
      #     goTo7 = "<leader>t7";
      #     goTo8 = "<leader>t8";
      #     goTo9 = "<leader>t9";
      #     last = "<leader>tL";
      #     # close = "<leader>tq";
      #   };
      #   sidebarFiletypes = { NvimTree = true; };
      # };

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
        plugins = [ "Mofiqul/dracula.nvim" "fneu/breezy" ];
      };

      which-key = {
        enable = true;
        showKeys = true;
      };
    };

    extraPlugins = with pkgs.vimPlugins; [ ];
  };
}

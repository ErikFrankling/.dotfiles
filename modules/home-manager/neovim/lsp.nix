{ pkgs, ... }: {
  home.packages = with pkgs; [
    nixpkgs-fmt
  ];

  programs.nixvim = {
    extraPlugins = [ pkgs.vimPlugins.yuck-vim ];
    # extraConfigLua = "require('yuck-vim').setup()";
    # extraPlugins = [
    #   (pkgs.vimUtils.buildVimPlugin {
    #     name = "my-plugin";
    #     src = pkgs.fetchFromGitHub {
    #       owner = "elkowar";
    #       repo = "yuck.vim";
    #       rev = "<commit hash>";
    #       hash = "<nix NAR hash>";
    #     };
    #   })
    # ];

    plugins = {
      lsp-format = {
        enable = true;
        settings = {
          sql = {
            exclude = [ "sqls" ];
          };
        };
      };

      lsp = {
        enable = true;
        keymaps = {
          silent = true;
          diagnostic = {
            "<leader>k" = "goto_prev";
            "<leader>j" = "goto_next";
          };
          lspBuf = {
            "gd" = "definition";
            "gD" = "declaration";
            "gi" = "implementation";
            "gr" = "references";
            "gt" = "type_definition";
            "K" = "hover";

            "<C-k>" = "signature_help";

            "<leader>ca" = "code_action";
            "<leader>rn" = "rename";
            "<leader>wa" = "add_workspace_folder";
            "<leader>wr" = "remove_workspace_folder";
          };
        };
        onAttach = ''
          vim.api.nvim_buf_set_keymap(bufnr, 'n', '<leader>wl', '<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>', opts)
        '';

        servers = {
          clangd = {
            enable = true;
            filetypes = [ "c" "cpp" ];
          };

          clojure_lsp = {
            enable = true;
            filetypes = [ "clj" ];
          };

          sqls = {
            enable = true;
            filetypes = [ "sql" "psql" ];
          };

          # postgres_lsp = {
          #   enable = true;
          #   filetypes = [ "sql" "psql" ];
          # };

          lua-ls = {
            enable = true;
            settings = {
              workspace.checkThirdParty = true;
              telemetry.enable = false;
            };
          };

          pyright.enable = true;
          nil_ls = {
            enable = true;
            filetypes = [ "nix" ];
            settings = {
              formatting.command = [ "nixpkgs-fmt" ];
            };
          };

          zls = {
            enable = true;
            # filetypes = [ "zls" ];
            settings = { };
          };

          gopls = {
            enable = true;
            # filetypes = [ "zls" ];
            settings = { };
          };

          ts_ls = {
            enable = true;
            # filetypes = [ "zls" ];
            # settings = { };
          };

          matlab_ls = {
            enable = true;
            # filetypes = [ "m" ];
            # settings = { };
          };

          # rust-analyzer = {
          #   enable = true;
          #   settings = { diagnostics.enable = true; };
          # };

        };
      };
    };
  };
}

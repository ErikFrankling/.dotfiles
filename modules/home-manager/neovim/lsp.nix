{ pkgs, ... }: {
  config.programs.nixvim.plugins.lsp = {
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
      lua-ls = {
        enable = true;
        settings = {
          workspace.checkThirdParty = true;
          telemetry.enable = false;
        };
      };

      pyright.enable = true;
      nil_ls.enable = true;

      rust-analyzer = {
        enable = true;
        settings = { diagnostics.enable = true; };
      };

    };
  };
}

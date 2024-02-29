{ pkgs, ... }: {
  config.programs.nixvim.plugins.telescope = {
    enable = true;
    keymapsSilent = true;
    keymaps = {
      "<leader>fb" = "buffers";
      "<leader>ff" = "find_files";
      "<leader>fg" = "live_grep";
      "<leader>fh" = "help_tags";

      # lsp
      "<leader>fci" = "lsp_incoming_calls";
      "<leader>fco" = "lsp_outgoing_calls";
      "<leader>fd" = "lsp_definitions";
      "<leader>fD" = "lsp_diagnostics";
      "<leader>fi" = "lsp_implementations";
      "<leader>fr" = "lsp_references";
      "<leader>fsd" = "lsp_document_symbols";
      "<leader>fsw" = "lsp_workspace_symbols";
      "<leader>ft" = "lsp_type_definitions";
    };
    defaults = {
      border = true;
      layout_strategy = "horizontal";
      layout_config = {
        anchor = "center";
        height = 0.75;
        width = 0.5;
        prompt_position = "bottom";
      };
    };
  };
}

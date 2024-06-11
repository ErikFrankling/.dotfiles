{ pkgs, ... }: {
    config.programs.nixvim.keymaps = [
        # {
        #     mode = [ "n" "v" ];
        #     key = "<Space>";
        #     action = "<Nop>";
        #     options = { silent = true; };
        # }
        {
            mode = [ "n" "v" ];
            key = "ä";
            action = ":";
            options = { desc = "CLI"; };
        }
        {
            mode = [ "v" ];
            key = "p";
            action = "\"_dP";
        }
        {
            mode = [ "i" ];
            key = "ä";
            action = "<C-[>:";
            options = { desc = "CLI"; };
        }
        {
            mode = [ "n" "i" ];
            key = "ö";
            action = "<Cmd>noh<CR><C-[>";
            options = { desc = "Esc"; };
        }
        {
            mode = [ "v" ];
            key = "<Esc>";
            action = "v<Cmd>noh<CR><C-[>";
        }
        {
            mode = [ "n" "v" "i" ];
            key = "<C-s>";
            action = "<Cmd>w<CR>";
            options = { desc = "Save"; };
        }
        # {
        #     mode = [ "i" ];
        #     key = "Å";
        #     action = "require(\"copilot.suggestion\").accept";
        #     lua = true;
        # }
        # {
        #     mode = [ "i" ];
        #     key = "å";
        #     action = "require(\"copilot.suggestion\").accept_word";
        #     lua = true;
        # }
        {
            mode = [ "n" ];
            key = "k";
            action = "v:count == 0 ? 'gk' : 'k'";
            options = { expr = true; silent = true; };
        }
        {
            mode = [ "n" ];
            key = "j";
            action = "v:count == 0 ? 'gj' : 'j'";
            options = { expr = true; silent = true; };
        }
        {
            mode = [ "n" ];
            key = "<leader>e";
            action = "vim.diagnostic.open_float";
            options = { desc = "Open floating diagnostic message"; };
            lua = true;
        }
        {
            mode = [ "n" ];
            key = "<leader>q";
            action = "vim.diagnostic.setloclist";
            options = { desc = "Open diagnostics list"; };
            lua = true;
        }
    ];
#   config.programs.nixvim.maps = {
#     normal = {
#       # nvim-tree
#       "<leader>b".desc = "Nvim Tree";
#       "<leader>bt" = {
#         silent = true;
#         action = ":NvimTreeToggle<CR>";
#         desc = "Toggle";
#       };
#       "<leader>br" = {
#         silent = true;
#         action = ":NvimTreeRefresh<CR>";
#         desc = "Refresh";
#       };
#       "<leader>bf" = {
#         silent = true;
#         action = ":NvimTreeFindFile<CR>";
#         desc = "Find File";
#       };
#
#       # barbar
#       "<leader>t".desc = "Tabs";
#       "<leader>tk".desc = "Previous";
#       "<leader>tj".desc = "Next";
#       "<leader>th".desc = "Move Previous";
#       "<leader>tl".desc = "Move Next";
#       "<leader>t1".desc = "Buffer 1";
#       "<leader>t2".desc = "Buffer 2";
#       "<leader>t3".desc = "Buffer 3";
#       "<leader>t4".desc = "Buffer 4";
#       "<leader>t5".desc = "Buffer 5";
#       "<leader>t6".desc = "Buffer 6";
#       "<leader>t7".desc = "Buffer 7";
#       "<leader>t8".desc = "Buffer 8";
#       "<leader>t9".desc = "Buffer 9";
#       "<leader>tL".desc = "Last Buffer";
#       "<leader>tq".desc = "Close";
#       "<leader>tr" = {
#         silent = true;
#         action = "<Cmd>BufferRestore<CR>";
#         desc = "Restore";
#       };
#
#       # lsp
#       "g".desc = "GoTo";
#       "gd".desc = "Definition";
#       "gD".desc = "Declaration";
#       "gi".desc = "Implementation";
#       "gr".desc = "Referecnes";
#       "gt".desc = "Type Definition";
#       "K".desc = "Hover";
#       "<C-k>".desc = "Signature Help";
#       "<leader>c".desc = "Code";
#       "<leader>ca".desc = "Code Action";
#       "<leader>j".desc = "Next Diagnostic";
#       "<leader>k".desc = "Previous Diagnostic";
#       "<leader>r".desc = "Refactor";
#       "<leader>rn".desc = "Rename";
#       "<leader>w".desc = "Workspace";
#       "<leader>wa".desc = "Add Folder";
#       "<leader>wl".desc = "List Folders";
#       "<leader>wr".desc = "Remove Folder";
#
#       # gitgutter
#       "<leader>h".desc = "Git Hunk";
#       "<leader>hp".desc = "Preview";
#       "<leader>hs".desc = "Stage";
#       "<leader>hu".desc = "Undo";
#
#       # telescope
#       "<leader>f".desc = "Find";
#       "<leader>fb".desc = "Buffer";
#       "<leader>ff".desc = "File";
#       "<leader>fg".desc = "Live Grep";
#       "<leader>fh".desc = "Help Tags";
#       "<leader>fc".desc = "Calls";
#       "<leader>fci".desc = "Incoming";
#       "<leader>fco".desc = "Outgoing";
#       "<leader>fd".desc = "Definition";
#       "<leader>fD".desc = "Diagnostic";
#       "<leader>fi".desc = "Implementation";
#       "<leader>fr".desc = "Referecnes";
#       "<leader>fs".desc = "Symbols";
#       "<leader>fsd".desc = "Document";
#       "<leader>fsw".desc = "Workspace";
#       "<leader>ft".desc = "Type Definition";
#     };
#   };
}

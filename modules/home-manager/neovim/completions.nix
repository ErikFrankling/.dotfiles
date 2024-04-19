{ pkgs, ... }: {
  config.programs.nixvim = { 
      extraConfigLua = builtins.readFile ./completions.lua;

      plugins = {
        luasnip.enable = true;

        # nvim-cmp = {
        #   enable = true;
        #   snippet = { expand = "luasnip"; };
        #   mapping = {
        #     "<CR>" =
        #       "cmp.mapping.confirm({ select = true, behavior = cmp.ConfirmBehavior.Replace, })";
        #     "<Tab>" = {
        #       modes = [ "i" "s" ];
        #       action = ''
        #         function(fallback)
        #           local luasnip = require 'luasnip'
        #           if cmp.visible() then
        #             cmp.select_next_item()
        #           elseif luasnip.expandable() then
        #             luasnip.expand();
        #           elseif luasnip.expand_or_jumpable() then
        #             luasnip.expand_or_jump()
        #           else
        #             fallback()
        #           end
        #         end
        #       '';
        #     };
        #     "<S-Tab>" = {
        #       modes = [ "i" "s" ];
        #       action = ''
        #         function(fallback)
        #           local luasnip = require 'luasnip'
        #           if cmp.visible() then
        #             cmp.select_prev_item()
        #           elseif luasnip.jumpable(-1) then
        #             luasnip.jump(-1);
        #           else
        #             fallback()
        #           end
        #         end
        #       '';
        #     };
        #     "<C-p>" = "cmp.mapping.select_prev_item()";
        #     "<C-n>" = "cmp.mapping.select_next_item()";
        #     "<C-d>" = "cmp.mapping.scroll_docs(-4)";
        #     "<C-f>" = "cmp.mapping.scroll_docs(4)";
        #     "<C-Space>" = "cmp.mapping.complete()";
        #     "<C-e>" = "cmp.mapping.close()";
        #   };
        #   sources = [
        #     { name = "luasnip"; }
        #     { name = "path"; }
        #     { name = "spell"; }
        #     { name = "zsh"; }
        #     { name = "crates"; }
        #     { name = "buffer"; }
        #     { name = "nvim_lsp"; }
        #   ];
        # };
      };
  };
}

{ pkgs, ... }: {
  config.programs.nixvim = {
    # extraConfigLua = builtins.readFile ./completions.lua;

    plugins = {

      copilot-lua = {
        enable = true;
        extraOptions = {
          suggestion = {
            enabled = true;
            auto_trigger = true;
            hide_during_completion = true;
            debounce = 75;
            keymap = {
              accept = "<C-Space>";
              accept_word = "<S-Tab>";
              accept_line = false;
              next = false;
              prev = false;
              dismiss = false;
            };
          };
        };
      };

      luasnip.enable = true;

      cmp-buffer = { enable = true; };

      cmp-emoji = { enable = true; };

      cmp-nvim-lsp = { enable = true; };

      cmp-path = { enable = true; };

      cmp_luasnip = { enable = true; };

      cmp = {
        enable = true;
        autoEnableSources = true;
        settings = {
          completion.autocomplete =
            [ "require('cmp.types').cmp.TriggerEvent.TextChanged" ];
          mapping = {
            __raw = ''
              cmp.mapping.preset.insert({ 
                -- Select the [n]ext item
                ['<C-n>'] = cmp.mapping.select_next_item(),
                -- Select the [p]revious item
                ['<C-p>'] = cmp.mapping.select_prev_item(),

                -- Scroll the documentation window [b]ack / [f]orward
                ['<C-b>'] = cmp.mapping.scroll_docs(-4),
                ['<C-f>'] = cmp.mapping.scroll_docs(4),
                ['<C-S>'] = cmp.mapping.complete(),
                ['<C-y>'] = cmp.mapping.confirm({ select = true }),

                -- Think of <c-l> as moving to the right of your snippet expansion.
                --  So if you have a snippet that's like:
                --  function $name($args)
                --    $body
                --  end
                --
                -- <c-l> will move you to the right of each of the expansion locations.
                -- <c-h> is similar, except moving you backwards.
                ['<C-l>'] = cmp.mapping(function()
                  if luasnip.expand_or_locally_jumpable() then
                    luasnip.expand_or_jump()
                  end
                end, { 'i', 's' }),
                ['<C-h>'] = cmp.mapping(function()
                  if luasnip.locally_jumpable(-1) then
                    luasnip.jump(-1)
                  end
                end, { 'i', 's' }),
              })
            '';
          };
          snippet = {
            expand =
              "function(args) require('luasnip').lsp_expand(args.body) end";
          };
          sources = [
            { name = "luasnip"; }
            { name = "path"; }
            {
              name = "spell";
            }
            # { name = "zsh"; }
            # { name = "crates"; }
            # { name = "buffer"; }
            { name = "nvim_lsp"; }
          ];
        };
        # snippet = { expand = "luasnip"; };
        # mapping = {
        #   "<CR>" =
        #     "cmp.mapping.confirm({ select = true, behavior = cmp.ConfirmBehavior.Replace, })";
        #   "<Tab>" = {
        #     modes = [ "i" "s" ];
        #     action = ''
        #       function(fallback)
        #         local luasnip = require 'luasnip'
        #         if cmp.visible() then
        #           cmp.select_next_item()
        #         elseif luasnip.expandable() then
        #           luasnip.expand();
        #         elseif luasnip.expand_or_jumpable() then
        #           luasnip.expand_or_jump()
        #         else
        #           fallback()
        #         end
        #       end
        #     '';
        #   };
        # "<S-Tab>" = {
        #   modes = [ "i" "s" ];
        #   action = ''
        #     function(fallback)
        #       local luasnip = require 'luasnip'
        #       if cmp.visible() then
        #         cmp.select_prev_item()
        #       elseif luasnip.jumpable(-1) then
        #         luasnip.jump(-1);
        #       else
        #         fallback()
        #       end
        #     end
        #   '';
        # };
        #       "<C-p>" = "cmp.mapping.select_prev_item()";
        #       "<C-n>" = "cmp.mapping.select_next_item()";
        #       "<C-d>" = "cmp.mapping.scroll_docs(-4)";
        #       "<C-f>" = "cmp.mapping.scroll_docs(4)";
        #       "<C-Space>" = "cmp.mapping.complete()";
        #       "<C-e>" = "cmp.mapping.close()";
        #     };
      };
    };
  };
}

-- Write every keymap this Neovim ends up with to $NVIM_KEYMAP_OUT, as JSON,
-- and quit. Driven by nvim-keymaps.nix; run by hand with `nvim-keymap-dump`.
--
-- Two startup facts decide whether the answer is right, and both were measured
-- rather than guessed:
--
--   * `nvim --headless -c '…' -c 'qa!'` never reaches VimEnter. `-c` runs
--     before it and `qa!` exits first, so a dump taken there misses every
--     plugin that has not loaded yet — 106 normal-mode maps against the 132 a
--     real session has. Hence the VimEnter autocmd below rather than a `-c`.
--   * lazy.nvim fires its `VeryLazy` event from `UIEnter` when Vim has not
--     entered yet (lazy/core/util.lua, M.very_lazy), and headless has no UI, so
--     `UIEnter` never comes on its own and nvim-surround's 25 maps never
--     appear. One synthetic `nvim_exec_autocmds('UIEnter', {})` is lazy's own
--     code path, not a way around it.
--
-- With both, a headless run reproduces a real TUI session exactly: identical
-- per-mode counts against an instance driven in a pty, in 1.3 seconds.
local out = assert(vim.env.NVIM_KEYMAP_OUT, 'set NVIM_KEYMAP_OUT')

local function collect()
  local leader = vim.g.mapleader == ' ' and ' ' or vim.g.mapleader
  local function pretty(lhs)
    if leader and #leader > 0 and lhs:sub(1, #leader) == leader then
      return '<leader>' .. lhs:sub(#leader + 1)
    end
    return lhs
  end
  local rows, seen = {}, {}
  -- which-key knows two things `nvim_get_keymap` cannot: the descriptions it
  -- ships for Vim's own motions and operators (`w`, `%`, `H` — not mappings at
  -- all, so no keymap table has them), and the group headings the leader tree
  -- is organised by. Its tree is walkable as of 3.x.
  local wk = package.loaded['which-key.buf']
  local wkdesc, wkgroup, wkicon = {}, {}, {}
  if wk then
    for _, mode in ipairs({ 'n', 'i', 'v', 'x', 's', 'o', 't', 'c' }) do
      local m = wk.get({ mode = mode })
      if m then
        m.tree:walk(function(node)
          local mp = node.mapping
          if mp then
            local id = mode .. '\t' .. node.keys
            if mp.desc then wkdesc[id] = mp.desc end
            if mp.group then wkgroup[id] = true end
            local ic = mp.icon
            if ic then wkicon[id] = type(ic) == 'table' and ic.icon or ic end
          end
        end)
      end
    end
  end
  for _, mode in ipairs({ 'n', 'i', 'v', 'x', 's', 'o', 't', 'c' }) do
    for _, k in ipairs(vim.api.nvim_get_keymap(mode)) do
      local id = mode .. '\t' .. k.lhs
      if not seen[id] and k.lhs:sub(1, 6) ~= '<Plug>' and k.lhs:sub(1, 5) ~= '<SNR>' then
        seen[id] = true
        local src
        if k.callback then
          local ok, info = pcall(debug.getinfo, k.callback, 'S')
          if ok and info then src = (info.source or ''):gsub('^@', '') end
        end
        -- Field by field, never the whole entry: `callback` is a function and
        -- `vim.json.encode` refuses to serialise one.
        rows[#rows + 1] = {
          mode = mode,
          lhs = pretty(k.lhs),
          desc = (k.desc ~= '' and k.desc) or wkdesc[id] or nil,
          rhs = type(k.rhs) == 'string' and k.rhs ~= '' and k.rhs or nil,
          icon = wkicon[id],
          source = src,
        }
      end
    end
  end
  local annot = 0
  for _, mode in ipairs({ 'n', 'v', 'o' }) do
    local m = wk and wk.get({ mode = mode })
    if m then
      m.tree:walk(function(node)
        if node.mapping and not node.keymap then
          local id = mode .. '\t' .. node.keys
          if not seen[id] then
            seen[id] = true
            annot = annot + 1
            rows[#rows + 1] = {
              mode = mode, lhs = pretty(node.keys), desc = node.mapping.desc,
              group = wkgroup[id] or nil, builtin = true,
            }
          end
        end
      end)
    end
  end
  return rows, annot
end

vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function()
  vim.api.nvim_exec_autocmds('UIEnter', {})
  vim.defer_fn(function()
    vim.wait(5000, function() return vim.g.did_very_lazy == true end)
    vim.wait(200, function() return false end)
    local rows, annot = collect()
    local f = assert(io.open(out, 'w'))
    f:write(vim.json.encode({
      generated = os.date('!%Y-%m-%dT%H:%M:%SZ'),
      config = vim.fn.stdpath('config'),
      count = #rows,
      maps = rows,
    }))
    f:close()
    io.stderr:write(('wrote %d entries (%d of them which-key annotations) to %s\n')
      :format(#rows, annot, out))
    vim.cmd('qa!')
  end, 0)
end })

# The Neovim keymap dump the keys overlay reads.
#
# The shell's third keys page (~/projects/personal/quickshell/keys/Nvim.qml)
# renders `$XDG_CACHE_HOME/erikshell/nvim-keymaps.json` and says so plainly when
# the file is not there. This is what writes it.
#
# It cannot be read live. A keymap only exists inside a Neovim that has finished
# starting, and lazy.nvim does not register a plugin's `desc` until then, so the
# only honest answer comes from actually starting one. That takes 1.3 s — fine
# once per rebuild, far too slow behind a keypress.
#
# An activation script rather than a derivation, deliberately. 47 of the 48
# plugins are store paths, but harpoon is a lazy.nvim git clone living in
# ~/.local/share/nvim/lazy; in a build sandbox lazy tries to clone it, fails
# without network, and the build either breaks ("Too many rounds of missing
# plugins") or silently undercounts. Running the real profile Neovim as the real
# user has none of that problem. If this is ever wanted hermetically, harpoon
# has to be pinned in the nvim flake first.
#
# Refresh is therefore every `nixos-rebuild switch`, which is exactly right: the
# config is a flake input, so its store path moves if and only if the config
# changed, and the dump moves with it. No path unit watches the JSON afterwards
# because nothing needs to — Nvim.qml's FileView already has `watchChanges` on
# it and reloads itself the moment it is replaced. The unit below is for the
# other gap: a cache directory that has been cleared, where the file has to come
# back without waiting for the next rebuild.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;

  # The same package `home.packages` installs, referenced by store path rather
  # than found on PATH: an activation script's PATH is not his shell's, and the
  # whole point is to dump the Neovim he actually runs.
  nvim = inputs.nvim.packages.${system}.nvim;

  out = "${config.xdg.cacheHome}/erikshell/nvim-keymaps.json";

  dump = pkgs.writeShellApplication {
    name = "nvim-keymap-dump";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      out=''${1:-${out}}
      dir=$(dirname "$out")
      mkdir -p "$dir"

      # Written beside the target and renamed onto it, so a reader — the shell
      # watches this file — never sees a half-written dump. Same directory, so
      # the rename is atomic.
      tmp=$(mktemp "$dir/.nvim-keymaps.XXXXXX")
      trap 'rm -f "$tmp"' EXIT

      # `timeout` because a Neovim that fails to reach VimEnter headless would
      # otherwise sit there forever, holding up an activation.
      if NVIM_KEYMAP_OUT=$tmp timeout 120 ${nvim}/bin/nvim --headless \
          --cmd "luafile ${./nvim-keymaps.lua}" && [ -s "$tmp" ]; then
        chmod 644 "$tmp"
        mv "$tmp" "$out"
      else
        echo "nvim-keymap-dump: Neovim wrote no keymaps; leaving $out alone" >&2
        exit 1
      fi
    '';
  };
in
{
  home.packages = [ dump ];

  # A failed dump must not fail the switch: the overlay showing a slightly old
  # list, or saying it has none, is a far smaller problem than a rebuild that
  # will not complete.
  home.activation.nvimKeymaps = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${dump}/bin/nvim-keymap-dump || warnEcho "nvim-keymap-dump failed — the keys overlay keeps the previous dump"
  '';

  systemd.user.services.nvim-keymaps = {
    Unit = {
      Description = "Dump Neovim's keymaps for the shell's keys overlay";
      # Only when the file is gone. Every switch writes it, so on a normal login
      # this unit starts, finds the condition false, and does nothing.
      ConditionPathExists = "!${out}";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${dump}/bin/nvim-keymap-dump";
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };
}

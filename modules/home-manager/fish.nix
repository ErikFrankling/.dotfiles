{
  pkgs,
  config,
  hostName,
  username,
  ...
}:

let
  rebuildScript = pkgs.writeScriptBin "rebuild" ''
    #!${pkgs.fish}/bin/fish
    # Builds the dotfiles checkout it is run from (a clone or worktree of this
    # repo), else ~/.dotfiles.
    set -l dir /home/${username}/.dotfiles
    set -l top (git rev-parse --show-toplevel 2>/dev/null)
    if test -n "$top"; and test -f "$top/flake.nix"; and test -d "$top/modules/nixos/agent-priority"
      set dir $top
    end
    cd $dir
    echo "rebuild: deploying $dir"
    set -l cg (cat /proc/self/cgroup)
    set -l agent 0
    if string match -q '*/app-t3code.slice/*' -- $cg; and not string match -q '*/t3code-terminal-*' -- $cg
      set agent 1
    end

    if [ -f /home/${username}/.ssh/id_ed25519 ]
      if [ ! -f /home/${username}/.config/sops/age/keys.txt ]
        echo "No age key found. Generating one..."
        mkdir -p ~/.config/sops/age
        nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt" 
      end
    else
      echo "No SSH key found. Use 
      'scp ~/.ssh/id_ed25519.pub erikf@$pc:~/.ssh/'"
    end

    # A flake only sees files git knows. Erik's rebuild stages everything; an
    # agent's does not, because ~/.dotfiles holds other sessions' scratch files
    # and half-done work (agents commit their own files first).
    if test $agent = 0
      git add -A
    else
      set -l untracked (git ls-files --others --exclude-standard -- flake.nix hosts modules)
      if test -n "$untracked"
        echo "rebuild: not in the build until committed or git-added: $untracked" >&2
      end
    end

    if [ -z "$argv" ]
      set argv "switch"
    end

    # On the pc the evaluation and build run on the homelab builder and only
    # the activation runs here (modules/nixos/agent-priority). `rebuild --local`
    # is the old local nh path, for when the homelab is down.
    if contains -- --local $argv; and test $agent = 1
      echo "rebuild --local is Erik's fallback; agents build on the homelab (plain rebuild)." >&2
      exit 1
    end
    if command -q nixos-remote-switch; and not contains -- --local $argv
      nixos-remote-switch $argv[1] $dir; or exit 1
    else
      set argv (string match -v -- --local $argv)
      test -n "$argv"; or set argv switch
      # sudo nixos-rebuild $argv --fast --flake /home/${username}/.dotfiles#${hostName}
      nh os $argv /home/${username}/.dotfiles --hostname ${hostName}
    end
    echo $(hyprctl reload)
  '';
in
{
  # home.file = {
  #   ".config/fish/conf.d/config.fish" = {
  #     source = ./config.fish;
  #   };
  #
  #   # ".config/fish/conf.d" = {
  #   #   source = ./conf.d;
  #   #   recursive = true;
  #   # };
  # };

  # xdg.configFile."fish/fish_variables".source = config.lib.file.mkOutOfStoreSymlink ./fish_variables;

  home.packages = [
    rebuildScript
    pkgs.fastfetch
    pkgs.onefetch
  ];

  programs.fish = {
    enable = true;

    functions = {
      push = ''
        git pull
        git add -A
        git commit -am "$argv"
        git push
      '';

      eww_reload = ''
        pkill eww
        eww daemon --config /home/${username}/.dotfiles/modules/home-manager/eww/ 
        eww open bar --config /home/${username}/.dotfiles/modules/home-manager/eww/ 
      '';

      nvim-update = ''
        cd /home/${username}/projects/personal/nvim/
        git pull
        git add -A

        if [ -z "$argv" ]
          set argv "Update"
        end

        git commit -am "$argv"
        git push

        cd /home/${username}/.dotfiles
        git pull
        nix flake update nvim
        rebuild
        git add flake.lock
        git commit -am "Update nvim"
        git push
      '';

      fish_greeting = ''
        fastfetch
      '';

      cd = {
        wraps = "cd";
        body = ''
          builtin cd $argv || return
          check_directory_for_new_repository
        '';
      };

      check_directory_for_new_repository = ''
        set current_repository (git rev-parse --show-toplevel 2> /dev/null)
        if [ "$current_repository" ] && \
          [ "$current_repository" != "$last_repository" ]
          onefetch
        end
        set -gx last_repository $current_repository
      '';
    };

    shellAliases = {
      ls = "ls -oAhp --color=auto";
      grep = "grep --color=auto";
      xclients = "xlsclients";
      n = "nvim";
      g = "git";
    };

    interactiveShellInit = ''
      set -g theme_display_date no

      if isatty stdin
        stty -ixon
      end

      # Replay the palette the shell last published, so a terminal opened now
      # matches the ones that already recoloured from the live OSC broadcast.
      if isatty stdout; and test -r $HOME/.cache/wal/sequences
        cat $HOME/.cache/wal/sequences
      end
    '';

    shellInit = ''

      if test "$TERM_PROGRAM" = "kiro"
          exec /bin/env bash --login
      end
      fish_add_path --path $HOME/.dotfiles/bin $HOME/Downloads/zig 
      set -gx GTK_THEME Adwaita:dark
      set -gx GTK2_RC_FILES /usr/share/themes/Adwaita-dark/gtk-2.0/gtkrc
      set -gx QT_STYLE_OVERRIDE adwaita-dark
      set -gx HISTCONTROL ignoredups
      set -gx MOZ_USE_XINPUT2 1
      set -gx NIXPKGS_ALLOW_UNFREE 1
      set -gx EDITOR nvim
      set -gx NIXPKGS_ALLOW_INSECURE 1
      set -gx LIBVIRT_DEFAULT_URI qemu:///system
    '';

    loginShellInit = ''
      if not set -q SSH_TTY
        if test -z "$DISPLAY" -a "$XDG_VTNR" = 1
          start-hyprland
        end
      end
    '';

    plugins = [
      # Enable a plugin (here grc for colorized command output) from nixpkgs
      {
        name = "bobthefish";
        src = pkgs.fishPlugins.bobthefish.src;
      }
      # Manually packaging and enable a plugin
      {
        name = "z";
        src = pkgs.fetchFromGitHub {
          owner = "jethrokuan";
          repo = "z";
          rev = "e0e1b9dfdba362f8ab1ae8c1afc7ccf62b89f7eb";
          sha256 = "0dbnir6jbwjpjalz14snzd3cgdysgcs3raznsijd6savad3qhijc";
        };
      }
    ];
  };
}

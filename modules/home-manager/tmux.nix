{ pkgs, lib, ... }:
let
  # # TODO: move to official trepo
  # t-smart-manager = pkgs.tmuxPlugins.mkTmuxPlugin
  #   {
  #     pluginName = "t-smart-tmux-session-manager";
  #     version = "unstable-2023-06-05";
  #     rtpFilePath = "t-smart-tmux-session-manager.tmux";
  #     src = pkgs.fetchFromGitHub {
  #       owner = "joshmedeski";
  #       repo = "t-smart-tmux-session-manager";
  #       rev = "0a4c77c5c3858814621597a8d3997948b3cdd35d";
  #       sha256 = "1dr5w02a0y84q2iw4jp1psxvkyj4g6pr87gc22syw1jd4ibkn925";
  #     };
  #   };
  # tmux-nvim = pkgs.tmuxPlugins.mkTmuxPlugin
  #   {
  #     pluginName = "tmux.nvim";
  #     version = "unstable-2023-01-06";
  #     src = pkgs.fetchFromGitHub {
  #       owner = "aserowy";
  #       repo = "tmux.nvim";
  #       rev = "57220071739c723c3a318e9d529d3e5045f503b8";
  #       sha256 = "sha256-zpg7XJky7PRa5sC7sPRsU2ZOjj0wcepITLAelPjEkSI=";
  #     };
  #   };
  # tmux-browser = pkgs.tmuxPlugins.mkTmuxPlugin
  #   {
  #     pluginName = "tmux-browser";
  #     version = "unstable-2022-10-24";
  #     src = pkgs.fetchFromGitHub {
  #       owner = "ofirgall";
  #       repo = "tmux-browser";
  #       rev = "c3e115f9ebc5ec6646d563abccc6cf89a0feadb8";
  #       sha256 = "sha256-ngYZDzXjm4Ne0yO6pI+C2uGO/zFDptdcpkL847P+HCI=";
  #     };
  #   };

  # tmux-super-fingers = pkgs.tmuxPlugins.mkTmuxPlugin
  #   {
  #     pluginName = "tmux-super-fingers";
  #     version = "unstable-2023-05-31";
  #     src = pkgs.fetchFromGitHub {
  #       owner = "artemave";
  #       repo = "tmux_super_fingers";
  #       rev = "2c12044984124e74e21a5a87d00f844083e4bdf7";
  #       sha256 = "sha256-cPZCV8xk9QpU49/7H8iGhQYK6JwWjviL29eWabuqruc=";
  #     };
  #   };

in {
  # TODO: what if this is defined in another file? Merge it!
  # programs.fish = {
  #   shellInit = ''
  #     fish_add_path ${t-smart-manager}/share/tmux-plugins/t-smart-tmux-session-manager/bin/
  #   '';
  # };

  home.packages = with pkgs; [
    sesh
    lsof
    moreutils
    # for tmux super fingers
    # python311
  ];

  programs.tmux = {
    enable = true;
    shell = "${pkgs.fish}/bin/fish";
    terminal = "tmux-256color";
    historyLimit = 100000;
    plugins = with pkgs; [
      # tmux-nvim
      # tmuxPlugins.tmux-thumbs
      # TODO: why do I have to manually set this
      # {
      #   plugin = t-smart-manager;
      #   extraConfig = ''
      #     set -g @t-fzf-prompt '  '
      #     set -g @t-bind "T"
      #   '';
      # }
      # {
      #   plugin = tmux-super-fingers;
      #   extraConfig = "set -g @super-fingers-key f";
      # }
      # {
      #   plugin = tmux-browser;
      #   extraConfig = ''
      #     set -g @browser_close_on_deattach '1'
      #   '';
      # }

      # tmuxPlugins.sensible
      # must be before continuum edits right status bar
      # {
      #   plugin = tmuxPlugins.catppuccin;
      #   extraConfig = '' 
      #     set -g @catppuccin_flavour 'frappe'
      #     set -g @catppuccin_window_tabs_enabled on
      #     set -g @catppuccin_date_time "%H:%M"
      #   '';
      # }
      {
        plugin = tmuxPlugins.resurrect;
        extraConfig = ''
          set -g @resurrect-strategy-vim 'session'
          set -g @resurrect-strategy-nvim 'session'
          set -g @resurrect-capture-pane-contents 'on'

          resurrect_dir="$HOME/.tmux/resurrect"
          set -g @resurrect-dir $resurrect_dir
          set -g @resurrect-hook-post-save-all 'target=$(readlink -f $resurrect_dir/last); sed "s| --cmd .*-vim-pack-dir||g; s|/etc/profiles/per-user/$USER/bin/||g; s|/home/$USER/.nix-profile/bin/||g" $target | sponge $target'
        '';
      }
      {
        plugin = tmuxPlugins.continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-boot 'on'
          set -g @continuum-save-interval '10'
        '';
      }
      # tmuxPlugins.better-mouse-mode
      # tmuxPlugins.yank
    ];
    extraConfig = ''
            # fix for slow escape key in neovim
            set -sg escape-time 10

            set-option -g status-interval 5
            set-option -g automatic-rename on
            set-option -g automatic-rename-format '#{b:pane_current_path}'
            # set -g default-terminal "tmux-256color"
            set -ag terminal-overrides ",xterm-256color:RGB"
            #
            #   set-option -g prefix C-a
            #   unbind-key C-b
            #   bind-key C-a send-prefix
            #
            set -g mouse on
            #
            #   # Change splits to match nvim and easier to remember
            #   # Open new split at cwd of current split
            #   unbind %
            #   unbind '"'
            #   bind | split-window -h -c "#{pane_current_path}"
            #   bind - split-window -v -c "#{pane_current_path}"
            #
              # Use vim keybindings in copy mode
              set-window-option -g mode-keys vi
            #
              # v in copy mode starts making selection
              bind-key -T copy-mode-vi v send-keys -X begin-selection
              bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
              bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
            #
            #   # Escape turns on copy mode
            #   bind Escape copy-mode

              # Easier reload of config
              bind r source-file ~/.config/tmux/tmux.conf

              set-option -g status-position top
            #
            #   # make Prefix p paste the buffer.
            #   unbind p
            #   bind p paste-buffer

      bind-key "T" run-shell "sesh connect \"$(
      	sesh list | fzf-tmux -p 55%,60% \
      		--no-sort --ansi --border-label ' sesh ' --prompt '⚡  ' \
      		--header '  ^a all ^t tmux ^g configs ^x zoxide ^d tmux kill ^f find' \
      		--bind 'tab:down,btab:up' \
      		--bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list)' \
      		--bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t)' \
      		--bind 'ctrl-g:change-prompt(⚙️  )+reload(sesh list -c)' \
      		--bind 'ctrl-x:change-prompt(📁  )+reload(sesh list -z)' \
      		--bind 'ctrl-f:change-prompt(🔎  )+reload(fd -H -d 2 -t d -E .Trash . ~)' \
      		--bind 'ctrl-d:execute(tmux kill-session -t {})+change-prompt(⚡  )+reload(sesh list)'
      )\""
    '';
  };
}

#t-smart-manager = pkgs.tmuxPlugins.mkTmuxPlugin
#  {
#    pluginName = "t-smart-tmux-session-manager";
#    version = "unstable-2023-06-05";
#    rtpFilePath = "t-smart-tmux-session-manager.tmux";
#    src = pkgs.fetchFromGitHub {
#      owner = "joshmedeski";
#      repo = "t-smart-tmux-session-manager";
#      rev = "0a4c77c5c3858814621597a8d3997948b3cdd35d";
#      sha256 = "1dr5w02a0y84q2iw4jp1psxvkyj4g6pr87gc22syw1jd4ibkn925";
#    };
#  };
#tmux-nvim = pkgs.tmuxPlugins.mkTmuxPlugin
#  {
#    pluginName = "tmux.nvim";
#    version = "unstable-2023-01-06";
#    src = pkgs.fetchFromGitHub {
#      owner = "aserowy";
#      repo = "tmux.nvim";
#      rev = "57220071739c723c3a318e9d529d3e5045f503b8";
#      sha256 = "sha256-zpg7XJky7PRa5sC7sPRsU2ZOjj0wcepITLAelPjEkSI=";
#    };
#  };
#tmux-browser = pkgs.tmuxPlugins.mkTmuxPlugin
#  {
#    pluginName = "tmux-browser";
#    version = "unstable-2022-10-24";
#    src = pkgs.fetchFromGitHub {
#      owner = "hmajid2301";
#      repo = "tmux-browser";
#      rev = "0156f7bf2034899dc8bec32a6c930839f55aedd8";
#      sha256 = "sha256-+f0UDmFBX/bShep5IrnIYKgA9Ia2Ok41ohWHAdQFopU";
#    };
#  };

#tmux-super-fingers = pkgs.tmuxPlugins.mkTmuxPlugin
#  {
#    pluginName = "tmux-super-fingers";
#    version = "unstable-2023-05-31";
#    src = pkgs.fetchFromGitHub {
#      owner = "artemave";
#      repo = "tmux_super_fingers";
#      rev = "2c12044984124e74e21a5a87d00f844083e4bdf7";
#      sha256 = "sha256-cPZCV8xk9QpU49/7H8iGhQYK6JwWjviL29eWabuqruc=";
#    };
#  };


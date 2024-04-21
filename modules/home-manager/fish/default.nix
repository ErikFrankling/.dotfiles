{ pkgs, config, ... }:

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

    home.packages = with pkgs; [
        neofetch
        onefetch
    ];

  programs.fish = {
    enable = true;

    interactiveShellInit = ''
        function cd -w='cd'
          builtin cd $argv || return
          check_directory_for_new_repository
        end

        function check_directory_for_new_repository
          set current_repository (git rev-parse --show-toplevel 2> /dev/null)
          if [ "$current_repository" ] && \
            [ "$current_repository" != "$last_repository" ]
            onefetch
          end
          set -gx last_repository $current_repository
        end

        alias ls='ls -oAhp --color=auto'
        alias grep='grep --color=auto'
        alias xclients='xlsclients'

        function sync
            git pull
            git add -A
            git commit -m "Sync"
            git push
        end

        function fish_greeting
            neofetch
        end
    '';

    shellInit = ''
        fish_add_path --path $HOME/.dotfiles/bin
    
        set -gx EDITOR /usr/bin/nvim
        set -gx GTK_THEME Adwaita:dark
        set -gx GTK2_RC_FILES /usr/share/themes/Adwaita-dark/gtk-2.0/gtkrc
        set -gx QT_STYLE_OVERRIDE adwaita-dark
        set -gx HISTCONTROL ignoredups
        set -gx MOZ_ENABLE_WAYLAND 1
    '';

    loginShellInit = ''
        if not set -q SSH_TTY
            dbus-run-session Hyprland
        end
    '';

    plugins = [
      # Enable a plugin (here grc for colorized command output) from nixpkgs
      { name = "bobthefish"; src = pkgs.fishPlugins.bobthefish.src; }
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

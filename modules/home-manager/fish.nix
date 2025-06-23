{ pkgs, config, hostName, ... }:

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

  home.packages = with pkgs; [ fastfetch onefetch ];

  programs.fish = {
    enable = true;

    functions = {
      push = ''
        git pull
        git add -A
        git commit -am "$argv"
        git push
      '';

      rebuild = ''
        cd /home/erikf/.dotfiles

        if [ -f /home/erikf/.ssh/id_ed25519 ]
          if [ ! -f /home/erikf/.config/sops/age/keys.txt ]
            echo "No age key found. Generating one..."
            mkdir -p ~/.config/sops/age
            nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt" 
          end
        else
          echo "No SSH key found. Use 
          'scp ~/.ssh/id_ed25519.pub erikf@$pc:~/.ssh/'"
        end

        git add -A

        if [ -z "$argv" ]
          set argv "switch"
        end

        sudo nixos-rebuild $argv --fast --flake /home/erikf/.dotfiles#${hostName}
        echo $(hyprctl reload)
      '';
      eww_reload = ''
        pkill eww
        eww daemon --config /home/erikf/.dotfiles/modules/home-manager/eww/ 
        eww open bar --config /home/erikf/.dotfiles/modules/home-manager/eww/ 
      '';

      nvim-update = ''
        cd /home/erikf/projects/personal/nvim/
        git pull
        git add -A

        if [ -z "$argv" ]
          set argv "Update"
        end

        git commit -am "$argv"
        git push

        cd /home/erikf/.dotfiles
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

    interactiveShellInit = "";

    shellInit = ''
      fish_add_path --path $HOME/.dotfiles/bin $HOME/Downloads/zig 
      set -gx GTK_THEME Adwaita:dark
      set -gx GTK2_RC_FILES /usr/share/themes/Adwaita-dark/gtk-2.0/gtkrc
      set -gx QT_STYLE_OVERRIDE adwaita-dark
      set -gx HISTCONTROL ignoredups
      set -gx MOZ_ENABLE_WAYLAND 1
      set -gx NIXPKGS_ALLOW_UNFREE 1
      set -gx EDITOR nvim
      set -gx LIBGL_ALWAYS_SOFTWARE 1
      set -gx LIBGL_ALWAYS_INDIRECT 0
    '';

    loginShellInit = ''
      if not set -q SSH_TTY
        if test -z "$DISPLAY" -a "$XDG_VTNR" = 1
          dbus-run-session Hyprland
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

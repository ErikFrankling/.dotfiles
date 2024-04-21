if status is-interactive
    alias ls='ls -oAhp --color=auto'
    alias grep='grep --color=auto'
    alias inst='sudo pacman -S'
    alias xclients='xlsclients'

    function sync
        git pull
        git add -A
        git commit -m "Sync"
        git push
    end

    # set  last_repository (sh "$HOME/.dotfiles/scripts/onefetch-last-repository.sh")
    #
    # function cd
    #     cd $args
    #     sh "$HOME/.dotfiles/scripts/onefetch-last-repository.sh"
    # end
    
    function fish_greeting
        neofetch
    end

    fish_add_path --path $HOME/.dotfiles/bin
    
    set -gx EDITOR /usr/bin/nvim
    set -gx GTK_THEME Adwaita:dark
    set -gx GTK2_RC_FILES /usr/share/themes/Adwaita-dark/gtk-2.0/gtkrc
    set -gx QT_STYLE_OVERRIDE adwaita-dark
    set -gx HISTCONTROL ignoredups
    set -gx MOZ_ENABLE_WAYLAND 1

    sh "$HOME/.cargo/env"
end

if status is-login
    dbus-run-session Hyprland
end

set -q GHCUP_INSTALL_BASE_PREFIX[1]; or set GHCUP_INSTALL_BASE_PREFIX $HOME ; set -gx PATH $HOME/.cabal/bin /home/erikf/.ghcup/bin $PATH # ghcup-env

# opam configuration
source /home/erikf/.opam/opam-init/init.fish > /dev/null 2> /dev/null; or true

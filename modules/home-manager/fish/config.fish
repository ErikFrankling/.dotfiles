if status is-interactive
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

    fish_add_path --path $HOME/.dotfiles/bin
    
    set -gx EDITOR /usr/bin/nvim
    set -gx GTK_THEME Adwaita:dark
    set -gx GTK2_RC_FILES /usr/share/themes/Adwaita-dark/gtk-2.0/gtkrc
    set -gx QT_STYLE_OVERRIDE adwaita-dark
    set -gx HISTCONTROL ignoredups
    set -gx MOZ_ENABLE_WAYLAND 1
end

if status is-login
    if test -z "$DISPLAY" -a "$XDG_VTNR" = 1
        dbus-run-session Hyprland
    end
end

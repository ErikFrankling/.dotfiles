start-process -FilePath "ssh" -ArgumentList ("-vL", "5900:localhost:5900", "erikf@arch-erik-pc", "WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 sway -V")
Start-Sleep -Seconds 3
& "C:\Users\erikf\projects\.dotfiles\other\laptop-vnc-viewer-config.vnc" 
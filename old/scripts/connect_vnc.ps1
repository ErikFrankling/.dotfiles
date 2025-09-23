start-process -FilePath "ssh" -ArgumentList ("-vLfN", "5900:localhost:5900", "erikf@192.168.0.232")#, "WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 sway -V")
start-process -FilePath "ssh" -ArgumentList ("-v", "erikf@192.168.0.232", "WAYLAND_DISPLAY=wayland-1 wayvnc -Ldebug --output DP-1")
Start-Sleep -Seconds 5
& "C:\Users\erikf\projects\.dotfiles\other\laptop-vnc-viewer-config.vnc" 
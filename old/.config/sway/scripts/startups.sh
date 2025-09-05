#!/bin/bash

swaymsg "focus output DP-1"

swaymsg "workspace 1 Neovim"
/home/erikf/.config/sway/scripts/sway-toolwait -v --waitfor Alacritty -- alacritty -e nvim

swaymsg "workspace 2 CLI"
/home/erikf/.config/sway/scripts/sway-toolwait -v --waitfor Alacritty alacritty

swaymsg "workspace number 3 Browser"
/home/erikf/.config/sway/scripts/sway-toolwait -v --waitfor google-chrome google-chrome-stable

swaymsg "workspace 1 Neovim"

swaymsg "focus output HDMI-A-1"

serverAdr="192.168.0.1"

ping -c 1 $serverAdr > /dev/null 2>&1
while [ $? -ne 0 ]; do
  echo -e "\e[1A\e[K $(date): Connecting - ${serverAdr}"
  sleep 1
  ping -c 1 $serverAdr > /dev/null 2>&1
done

swaymsg "workspace 10 Discord"
/home/erikf/.config/sway/scripts/sway-toolwait -v --nocheck spotify-launcher
/home/erikf/.config/sway/scripts/sway-toolwait -v --waitfor discord -- discord --enable-features=UseOzonePlatform --ozone-platform=wayland

swaymsg create_output HEADLESS-1

#swaymsg "focus output DP-1"

wayvnc --output DP-1 -Ldebug

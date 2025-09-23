#!/bin/bash

if [[ -z "${WLR_BACKENDS}" ]]; then
	echo not headless
	swaymsg 'set $DP DP-1'
	swaymsg 'set $HDMI HDMI-A-1'
else
	echo headless
	swaymsg create_output HEADLESS-1 
	swaymsg 'set $DP HEADLESS-1'
	swaymsg 'set $HDMI HEADLESS-1'
	wayvnc --output HEADLESS-1 -Ldebug
fi

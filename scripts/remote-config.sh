#!/bin/bash

if [[ -z "${WLR_BACKENDS}" ]]; then
	echo not headless
else
	echo headless
	swaymsg create_output HEADLESS-1 
	wayvnc --output HEADLESS-1 -Ldebug
fi

#!/bin/bash
# Grey background flicker is prevented by killing old swaybg process after new one.
# See https://github.com/swaywm/swaybg/issues/17#issuecomment-851680720
PID=`pidof swaybg`
swaybg -i "$1" -m fill &
if [ ! -z "$PID" ]; then
	sleep 1
	kill $PID 2>/dev/null
fi

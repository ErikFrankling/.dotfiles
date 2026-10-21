# pc-idle: is Erik away from the pc? Exit 0 when he has had no keyboard or
# mouse input for 10 minutes (erik-idle.service), 1 when he is using it.
# While idle, agents may run heavy jobs on the pc (one emulator at most);
# lag-guard pauses them the moment he is back and resumes them at the next
# idle window. `when-idle <cmd>` waits for idle, then runs cmd.
flag=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/erik-idle
if [ -e "$flag" ]; then
  away=$((($(date +%s) - $(stat -c %Y "$flag")) / 60 + 10))
  echo "idle: Erik has been away for about $away min. Heavy jobs may run on the pc now (one emulator at most); they are paused the moment he is back."
  exit 0
fi
echo "active: Erik is using the pc (input within the last 10 min). Heavy work goes to the homelab (heavy -- <cmd>), or wait with when-idle <cmd>."
exit 1

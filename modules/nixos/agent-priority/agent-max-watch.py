"""agent-max-watch: turn agent max mode off when Erik is back at the pc.

Runs while max mode is on (started by `agent-max on`). Watches the physical
input devices (kernel evdev, not the compositor: the agent seat's input never
reaches /dev/input, and ydotool's uinput device is under /sys/devices/virtual
and skipped). Any key, button or pointer movement after a short grace period,
or the deadline in $XDG_RUNTIME_DIR/agent-max/until, runs `agent-max off`.
"""

import os
import select
import subprocess
import sys
import time

import evdev
from evdev import ecodes

GRACE = 60  # Erik may have typed `agent-max on` himself and walked away.
RESCAN = 10  # Pick up devices plugged in later.
until_file = os.path.join(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"), "agent-max", "until")


def physical_devices():
    found = {}
    for path in evdev.list_devices():
        sysfs = os.path.realpath(f"/sys/class/input/{os.path.basename(path)}")
        if "/virtual/" in sysfs:
            continue
        try:
            dev = evdev.InputDevice(path)
        except OSError:
            continue
        caps = dev.capabilities()
        if ecodes.EV_KEY in caps or ecodes.EV_REL in caps or ecodes.EV_ABS in caps:
            found[dev.fd] = dev
        else:
            dev.close()
    return found


def off(reason):
    print(f"agent-max-watch: {reason}", flush=True)
    subprocess.run(["agent-max", "off", reason], check=False)
    sys.exit(0)


def deadline():
    try:
        with open(until_file) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return 0


start = time.time()
devices = physical_devices()
print(f"agent-max-watch: watching {', '.join(sorted(d.name for d in devices.values()))}", flush=True)
last_scan = start
while True:
    now = time.time()
    if deadline() <= now:
        off("max mode timed out")
    if now - last_scan > RESCAN:
        for dev in devices.values():
            dev.close()
        devices = physical_devices()
        last_scan = now
    ready, _, _ = select.select(list(devices), [], [], 5)
    for fd in ready:
        dev = devices[fd]
        try:
            events = [e for e in dev.read() if e.type in (ecodes.EV_KEY, ecodes.EV_REL, ecodes.EV_ABS)]
        except OSError:  # unplugged
            continue
        if events and time.time() - start > GRACE:
            off(f"Erik is back at the pc ({dev.name})")

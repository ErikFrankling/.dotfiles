"""Small desktop helpers; input itself belongs to the compositor backend."""

import json
import os
from pathlib import Path
import subprocess
import sys

OUTPUT = "AGENT-1"
WORKSPACE = "agent"


def run(*args, timeout=15):
    return subprocess.run(args, check=True, capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, timeout=timeout).stdout.strip()


def session():
    instances = json.loads(run("hyprctl", "-j", "instances"))
    current = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    matches = [i for i in instances if i["instance"] == current]
    if not matches and len(instances) == 1:
        matches = instances
    if len(matches) != 1:
        raise RuntimeError("Select a live Hyprland session; refusing to guess between sessions")
    selected = matches[0]
    os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = selected["instance"]
    os.environ["WAYLAND_DISPLAY"] = selected["wl_socket"]
    # An inherited pre-opened socket takes precedence over WAYLAND_DISPLAY in
    # libwayland. It may belong to a stale/different compositor session.
    os.environ.pop("WAYLAND_SOCKET", None)
    # Desktop launchers sometimes inherit an Electron library environment.
    os.environ.pop("LD_LIBRARY_PATH", None)


def query(kind, timeout=15):
    return json.loads(run("hyprctl", "-j", kind, timeout=timeout))


def monitor():
    found = [m for m in query("monitors") if m["name"] == OUTPUT]
    if len(found) != 1:
        raise RuntimeError("AGENT-1 is unavailable; check agent-desktop.service")
    return found[0]


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    if command in ("--help", "help"):
        print("agent-desktop status | start-browser | screenshot FILE | view")
        return
    session()
    if command == "exec-session" and len(sys.argv) > 2:
        os.execvp(sys.argv[2], sys.argv[2:])
    elif command == "load-plugin" and len(sys.argv) == 3:
        target = sys.argv[2]
        signature = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
        marker = Path(os.environ["XDG_RUNTIME_DIR"]) / "agent-desktop-plugin.json"
        loaded = run("hyprctl", "plugin", "list")
        if "computer-use" in loaded:
            previous = json.loads(marker.read_text()) if marker.exists() else {}
            if previous != {"session": signature, "path": target}:
                raise RuntimeError("A different computer-use plugin is loaded; restart Hyprland to replace it")
            return
        reply = run("hyprctl", "plugin", "load", target)
        if not (Path(os.environ["XDG_RUNTIME_DIR"]) / "computer-use/guard.sock").is_socket():
            raise RuntimeError(f"Compositor plugin did not start: {reply}")
        marker.write_text(json.dumps({"session": signature, "path": target}))
    elif command == "ensure-output":
        # Called by the declarative user unit. Never removes an output or
        # switches the human's workspace, pointer, or focused window.
        if not any(m["name"] == OUTPUT for m in query("monitors")):
            reply = run("hyprctl", "output", "create", "headless", OUTPUT)
            if "ok" not in reply.lower():
                raise RuntimeError(reply)
        monitor()
    elif command == "status":
        monitors = query("monitors")
        windows = [w for w in query("clients") if w["workspace"]["name"] == WORKSPACE]
        units = {}
        for unit in ("agent-desktop", "agent-computer-use", "agent-desktop-permissions", "agent-firefox", "agent-desktop-vnc"):
            units[unit] = run("systemctl", "--user", "show", unit, "--property=ActiveState", "--value")
        print(json.dumps({"output": next((m for m in monitors if m["name"] == OUTPUT), None),
                          "windows": windows, "services": units,
                          "input_policy": "independent-seat only; unsupported clients are refused",
                          "viewer": "127.0.0.1:5903 (view-only)"}, indent=2))
    elif command == "start-browser":
        monitor()
        run("systemctl", "--user", "start", "agent-firefox.service", timeout=30)
        print("Agent Firefox service started on workspace agent")
    elif command == "screenshot" and len(sys.argv) == 3:
        monitor()
        target = Path(sys.argv[2]).expanduser().absolute()
        target.parent.mkdir(parents=True, exist_ok=True)
        run("grim", "-o", OUTPUT, str(target))
        print(target)
    elif command == "view":
        monitor()
        os.execvp("vncviewer", ["vncviewer", "-ViewOnly", "-Shared", "127.0.0.1::5903"])
    else:
        raise RuntimeError("usage: agent-desktop status | start-browser | screenshot FILE | view")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError, ValueError, OSError) as error:
        print(f"agent-desktop: {error}", file=sys.stderr)
        sys.exit(1)

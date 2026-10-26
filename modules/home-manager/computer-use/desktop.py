"""Small desktop helpers; input itself belongs to the compositor backend."""

import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys

OUTPUT = "AGENT-1"
WORKSPACE = "agent"
AGENT_WORKSPACES = ("agent", "agent-park")


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


def return_focus():
    # When every physical display disconnects (monitors powered off), Hyprland
    # warps the pointer and focus to the only remaining output, AGENT-1. On
    # reconnect it leaves both there, and the gap before AGENT-1 clamps the
    # pointer to it, so the desktop looks frozen. Hand both back to the human.
    monitors = query("monitors")
    human = next((m for m in monitors if m["name"] != OUTPUT and not m["disabled"]), None)
    if human and any(m["focused"] and m["name"] == OUTPUT for m in monitors):
        run("hyprctl", "dispatch", "focusmonitor", human["name"])
        print(f"Returned focus from {OUTPUT} to {human['name']}", flush=True)


def agent_process(pid):
    """True for processes that opted in to the agent seat (or their children)."""
    try:
        for _ in range(6):
            process = Path("/proc") / str(int(pid))
            if process.stat().st_uid != os.getuid():
                return False
            # Chromium/Electron overwrite their environment block, so they opt
            # in with a command-line switch instead (same rule as the plugin).
            if (b"HYPRLAND_AGENT_SEAT=1" in (process / "environ").read_bytes().split(b"\0")
                    or b"--hyprland-agent-seat" in (process / "cmdline").read_bytes().split(b"\0")):
                return True
            pid = int((process / "stat").read_text().rsplit(")", 1)[1].split()[1])
            if pid <= 1:
                return False
    except (OSError, ValueError, TypeError, IndexError):
        pass
    return False


HARNESSES = ("claude", "codex", "opencode")


def harness_spawned(pid):
    """True for GUI processes an agent harness started directly (e.g. a
    Playwright browser or `xdg-open` from an agent's shell)."""
    try:
        for _ in range(16):
            process = Path("/proc") / str(int(pid))
            name = (process / "comm").read_text().strip().lstrip(".").removesuffix("-wrapped")
            if name in HARNESSES:
                return True
            pid = int((process / "stat").read_text().rsplit(")", 1)[1].split()[1])
            if pid <= 1:
                return False
    except (OSError, ValueError, IndexError):
        pass
    return False


def hypr_request(command):
    """One request on Hyprland's command socket, without spawning hyprctl."""
    path = Path(os.environ["XDG_RUNTIME_DIR"]) / "hypr" / os.environ["HYPRLAND_INSTANCE_SIGNATURE"] / ".socket.sock"
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(2)
        connection.connect(str(path))
        connection.sendall(command.encode())
        chunks = []
        while chunk := connection.recv(65536):
            chunks.append(chunk)
    return b"".join(chunks).decode(errors="replace")


# Erik's own apps, on his own profiles. Their windows belong on his monitors,
# whoever started the process: an agent that launches one of these reaches his
# profile (single-instance apps hand the request to his running copy), so the
# window is his. Agents use their own classes (agent-chromium, agent-firefox,
# com.t3tools.T3Code.Development). 2026-10-26: Thunderbird on agent-park meant
# Erik could not open his mail.
ERIK_APPS = re.compile(r"^(firefox|zen.*|thunderbird|spotify|webcord|discord|vesktop"
                       r"|md\.obsidian\.Obsidian|obsidian|helium|com\.t3tools\.T3Code"
                       r"|signal|org\.telegram\.desktop|teams-for-linux|Slack)$", re.IGNORECASE)


def erik_app(window):
    return bool(ERIK_APPS.match(window["class"]))


def erik_workspace(monitors=None):
    """The workspace Erik is looking at: the focused human monitor's, else the
    first human monitor's (focus can sit on AGENT-1)."""
    monitors = monitors or json.loads(hypr_request("j/monitors"))
    human = [m for m in monitors if m["name"] != OUTPUT and not m["disabled"]]
    human.sort(key=lambda m: not m["focused"])
    return human[0]["activeWorkspace"]["name"] if human else None


def rescue_window(window, clients):
    # Never keep an app of Erik's on the agent seat, and never let a second
    # Thunderbird main window vanish onto its hidden special:mail shelf while
    # Thunderbird is on his screen.
    workspace = window["workspace"]["name"]
    stray = workspace in AGENT_WORKSPACES or (
        window["class"] == "thunderbird" and workspace == "special:mail"
        and any(w["class"] == "thunderbird" and not w["workspace"]["name"].startswith("special:")
                and w["workspace"]["name"] not in AGENT_WORKSPACES for w in clients))
    if not (erik_app(window) and stray):
        return False
    target = erik_workspace()
    if target:
        hypr_request(f"dispatch movetoworkspacesilent name:{target},address:{window['address']}")
        print(f"Moved Erik's {window['class']} window ({window['address']}) from workspace "
              f"{workspace} to {target}", flush=True)
    return True


def confine_window(address, opened=True):
    # Only an app's first window follows the `[workspace name:agent silent]`
    # launch rule. Later ones (dialogs, compose windows, extra toplevels) open
    # on whatever workspace has focus, i.e. on Erik's monitor. Send every
    # window of an agent-seat process, and anything an agent harness spawned
    # itself, to AGENT-1 the moment it opens. Erik's own apps go the other way.
    clients = json.loads(hypr_request("j/clients"))
    window = next((w for w in clients if w["address"] == address), None)
    if not window or rescue_window(window, clients) or erik_app(window) or not opened:
        return
    if (window["workspace"]["name"] not in AGENT_WORKSPACES
            and (agent_process(window["pid"]) or harness_spawned(window["pid"]))):
        hypr_request(f"dispatch movetoworkspacesilent name:{WORKSPACE},address:{address}")
        print(f"Moved agent window {window['class']} ({address}) from workspace "
              f"{window['workspace']['name']} to {WORKSPACE}", flush=True)


def watch_focus():
    return_focus()
    for window in query("clients"):
        confine_window(window["address"])
    events = Path(os.environ["XDG_RUNTIME_DIR"]) / "hypr" / os.environ["HYPRLAND_INSTANCE_SIGNATURE"] / ".socket2.sock"
    with socket.socket(socket.AF_UNIX) as connection:
        connection.connect(str(events))
        for line in connection.makefile("rb"):
            if line.startswith(b"monitoradded>>"):
                return_focus()
            elif line.startswith((b"openwindow>>", b"movewindowv2>>")):
                # Both start with the window address. A move only rescues
                # Erik's apps (an agent's `movetoworkspace`); it never confines,
                # so a window someone moves to Erik on purpose stays there.
                event, _, payload = line.partition(b">>")
                try:
                    confine_window("0x" + payload.split(b",", 1)[0].decode(),
                                   opened=event == b"openwindow")
                except (OSError, ValueError, KeyError) as error:
                    print(f"confine failed: {error}", flush=True)


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
    elif command == "watch-focus":
        watch_focus()
    elif command == "status":
        monitors = query("monitors")
        windows = [w for w in query("clients") if w["workspace"]["name"] == WORKSPACE]
        units = {}
        for unit in ("agent-desktop", "agent-input-plugin", "agent-computer-use", "agent-desktop-permissions", "agent-chromium", "cua-driver", "agent-desktop-vnc"):
            units[unit] = run("systemctl", "--user", "show", unit, "--property=ActiveState", "--value")
        print(json.dumps({"output": next((m for m in monitors if m["name"] == OUTPUT), None),
                          "windows": windows, "services": units,
                          "input_policy": "independent-seat only; unsupported clients are refused",
                          "viewer": "127.0.0.1:5903 (view-only)"}, indent=2))
    elif command == "start-browser":
        monitor()
        run("systemctl", "--user", "start", "agent-chromium.service", timeout=30)
        print("Agent Chromium running on workspace agent (Playwright: http://127.0.0.1:9222)")
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

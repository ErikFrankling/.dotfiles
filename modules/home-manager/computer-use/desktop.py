"""Small desktop helpers; input itself belongs to the compositor backend."""

import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request

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
            # Chromium/Electron blank their environment block and flatten their
            # command line into one string, so the switch is a substring there.
            if (b"HYPRLAND_AGENT_SEAT=1" in (process / "environ").read_bytes().split(b"\0")
                    or b"--hyprland-agent-seat" in (process / "cmdline").read_bytes()):
                return True
            pid = int((process / "stat").read_text().rsplit(")", 1)[1].split()[1])
            if pid <= 1:
                return False
    except (OSError, ValueError, TypeError, IndexError):
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


# Erik's own apps, on his own profiles. Their windows belong on his monitors.
# 2026-10-26: Thunderbird on agent-park meant Erik could not open his mail. A
# window tagged agent-window (packages/agent-windows) came from an agent session
# and stays on the agent seat whatever its class.
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
    if "agent-window" in window.get("tags", []):
        return False
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


ORIGIN_LOG = Path.home() / ".local/state/window-origin/windows.jsonl"


def rescue(address):
    clients = json.loads(hypr_request("j/clients"))
    window = next((w for w in clients if w["address"] == address), None)
    if window:
        rescue_window(window, clients)


def escape_alert(record, dry_run=False):
    """Tell Erik an agent window reached his monitors, naming the thread."""
    thread = record.get("thread") or "unknown thread"
    what = {"opened-outside": "opened on", "agent-moved-it": "was moved to"}.get(record.get("event"), "reached")
    message = (f"{record.get('class')} {what} workspace {record.get('workspace')} "
               f"({record.get('monitor')}); sent back to AGENT-1. Thread {thread}, "
               f"pid {record.get('pid')}, {(record.get('cgroup') or '').rsplit('/', 1)[-1]}.")
    command = ["notify-erik", "-p", "high", "-t", "Agent window got onto your monitor", "--source", "window-origin"]
    if record.get("thread"):
        command += ["--thread", record["thread"]]
    command.append(message)
    if dry_run:
        print("would send:", " ".join(command))
        return
    subprocess.run(command, check=False, timeout=30, stdin=subprocess.DEVNULL)


def watch_focus():
    return_focus()
    for window in query("clients"):
        rescue(window["address"])
    events = Path(os.environ["XDG_RUNTIME_DIR"]) / "hypr" / os.environ["HYPRLAND_INSTANCE_SIGNATURE"] / ".socket2.sock"
    with socket.socket(socket.AF_UNIX) as connection:
        connection.connect(str(events))
        for line in connection.makefile("rb"):
            try:
                if line.startswith(b"monitoradded>>"):
                    return_focus()
                elif line.startswith((b"openwindow>>", b"movewindowv2>>")):
                    rescue("0x" + line.partition(b">>")[2].split(b",", 1)[0].decode())
                elif line.startswith(b"agentwindowescape>>"):
                    escape_alert(json.loads(line.partition(b">>")[2]))
            except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
                print(f"watch failed: {error}", flush=True)


def origin_records():
    for path in (ORIGIN_LOG.with_name(ORIGIN_LOG.name + ".1"), ORIGIN_LOG):
        if path.exists():
            for line in path.read_text().splitlines():
                try:
                    yield json.loads(line)
                except ValueError:
                    pass


def window_origin(args):
    """Who opened which window. The log never holds titles, so this is safe to paste."""
    if args[:1] == ["alert"]:
        if "--test" not in args[1:]:
            raise RuntimeError("usage: window-origin alert --test [--dry-run]")
        escape_alert({"event": "opened-outside", "class": "test-window", "workspace": "test", "monitor": "TEST-1",
                      "thread": os.environ.get("T3CODE_THREAD_ID", "test-thread"), "pid": os.getpid(),
                      "cgroup": "/test.scope"}, dry_run="--dry-run" in args)
        return
    if args[:1] in (["--help"], ["help"]):
        print("window-origin [ADDRESS] [--class REGEX] [--agents] [--erik] [--escapes] [--last N] [--json]
"
              "window-origin alert --test [--dry-run]")
        return
    last, want, show_json, filters = 20, None, False, []
    while args:
        item = args.pop(0)
        if item == "--last":
            last = int(args.pop(0))
        elif item == "--class":
            pattern = re.compile(args.pop(0), re.IGNORECASE)
            filters.append(lambda r, p=pattern: p.search(r.get("class", "")))
        elif item == "--agents":
            filters.append(lambda r: r.get("agent"))
        elif item == "--erik":
            filters.append(lambda r: r.get("monitor") != OUTPUT)
        elif item == "--escapes":
            filters.append(lambda r: r.get("event") in ("opened-outside", "agent-moved-it"))
        elif item == "--json":
            show_json = True
        elif item.startswith("0x") or re.fullmatch(r"[0-9a-f]{6,}", item):
            want = item if item.startswith("0x") else "0x" + item
        else:
            raise RuntimeError(f"window-origin: unknown argument {item}")
    records = [r for r in origin_records() if (not want or r.get("address") == want)
               and all(f(r) for f in filters)][-last:]
    if not records:
        print("No matching window. Windows mapped before the plugin loaded (2026-10-31) are not recorded.")
    for record in records:
        if show_json:
            print(json.dumps(record))
            continue
        when = time.strftime("%m-%d %H:%M:%S", time.localtime(record.get("ts_ms", 0) / 1000))
        print(f"{when}  {record.get('event'):<14} {record.get('address'):<15} {record.get('monitor'):<9} "
              f"{record.get('workspace'):<10} {record.get('class')}\n"
              f"    {'AGENT thread ' + (record.get('thread') or 'unknown') + ' via ' + (record.get('via') or '?') if record.get('agent') else 'not an agent'}"
              f"  pid {record.get('pid')}{' x11' if record.get('x11') else ''}\n"
              f"    cgroup {record.get('cgroup')}\n"
              f"    chain  {' < '.join(record.get('chain', []))}")


def open_url(target):
    """Open a URL or file in a new tab of the agent's Chromium."""
    if "://" not in target and not target.startswith(("about:", "mailto:")):
        target = Path(target).expanduser().absolute().as_uri()
    monitor()
    run("systemctl", "--user", "start", "agent-chromium.service", timeout=30)
    request = urllib.request.Request("http://127.0.0.1:9222/json/new?" + urllib.parse.quote(target, safe=""), method="PUT")
    for attempt in range(40):
        try:
            with urllib.request.urlopen(request, timeout=5):
                print(f"Opened in the agent's Chromium on AGENT-1: {target}")
                return
        except OSError:
            if attempt == 39:
                raise
            time.sleep(0.25)


def load_window_plugin(target):
    # This plugin owns no seat, so a new build replaces the old one without
    # restarting Hyprland.
    signature = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    marker = Path(os.environ["XDG_RUNTIME_DIR"]) / "agent-windows-plugin.json"
    wanted = {"session": signature, "path": target}
    previous = json.loads(marker.read_text()) if marker.exists() else {}
    if "agent-windows" in run("hyprctl", "plugin", "list"):
        if previous == wanted:
            return
        if previous.get("session") == signature and previous.get("path"):
            run("hyprctl", "plugin", "unload", previous["path"])
    reply = run("hyprctl", "plugin", "load", target)
    if "agent-windows" not in run("hyprctl", "plugin", "list"):
        raise RuntimeError(f"agent-windows plugin did not load: {reply}")
    marker.write_text(json.dumps(wanted))


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    if command in ("--help", "help"):
        print("agent-desktop status | start-browser | open URL | screenshot FILE | view")
        return
    if command == "window-origin":
        window_origin(sys.argv[2:])
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
    elif command == "load-window-plugin" and len(sys.argv) == 3:
        load_window_plugin(sys.argv[2])
    elif command == "open" and len(sys.argv) == 3:
        open_url(sys.argv[2])
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
        raise RuntimeError("usage: agent-desktop status | start-browser | open URL | screenshot FILE | view")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError, ValueError, OSError) as error:
        print(f"agent-desktop: {error}", file=sys.stderr)
        sys.exit(1)

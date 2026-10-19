"""Approve requested agent-window access and keep computer use from pausing.

This is same-user desktop policy, not an OS security boundary. The compositor
also refuses input outside AGENT-1, including between these periodic checks.
"""

import json
import os
from pathlib import Path
import socket
import subprocess
import time

from desktop import agent_process, query, session

def eligible_windows(monitors, windows, opted_in=agent_process):
    outputs = {m["id"] for m in monitors if m["name"] == "AGENT-1"}
    return {w["stableId"] for w in windows
            if w.get("mapped") and w.get("stableId")
            and w.get("monitor") in outputs
            and w.get("workspace", {}).get("name") == "agent"
            and opted_in(w.get("pid"))}


def allowed(request, windows):
    scope = request.get("scope", {})
    return (request.get("capability") in ("observe", "control")
            and scope.get("kind") == "window" and scope.get("id") in windows)


def decisions(state, windows):
    # Remove stale grants before granting newly eligible windows.
    for grant in state.get("grants", []):
        if not allowed(grant, windows):
            yield "revoke", {"id": grant["id"]}
    # Computer use is always on (Erik, 2026-10-19). The broker pauses itself
    # whenever this supervisor disconnects and the tray has a Pause button;
    # both are undone here. Pending requests wait for the next tick.
    if state.get("paused"):
        yield "pause", {"paused": False}
    elif (state.get("mode") == "approve"
            and not state.get("revocation_unconfirmed")):
        for request in state.get("requests", []):
            if request.get("state") == "pending" and allowed(request, windows):
                yield "approve", {"id": request["id"], "seconds": 300}


def main():
    session()
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(4)
        connection.connect(os.path.join(os.environ["XDG_RUNTIME_DIR"], "computer-use/ui.sock"))
        with connection.makefile("rwb") as stream:
            def send(op, **kwargs):
                stream.write(json.dumps({"op": op, **kwargs}).encode() + b"\n")
                stream.flush()
                line = stream.readline()
                if not line:
                    raise RuntimeError("Computer-use broker disconnected")
                return json.loads(line)

            while True:
                state = send("state")
                # The broker's UI connection has a five-second read deadline.
                # Bound both compositor queries below it. A slow compositor
                # (heavy load) used to crash this supervisor, and the broker
                # then paused computer use until someone resumed it. Treat a
                # failed query as "no eligible windows" instead: every grant is
                # revoked and nothing is approved until the compositor answers.
                try:
                    windows = eligible_windows(query("monitors", timeout=1), query("clients", timeout=1))
                except (subprocess.SubprocessError, ValueError) as error:
                    print(f"compositor query failed, revoking: {error}", flush=True)
                    windows = set()
                for op, args in decisions(state, windows):
                    send(op, **args)
                time.sleep(0.5)


if __name__ == "__main__":
    main()

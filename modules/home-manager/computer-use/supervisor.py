"""Approve requested agent-window access, respecting the owner's pause switch.

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

AUDIT = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "computer-use/audit.jsonl"


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


def paused_by_disconnect(events):
    # The broker pauses itself whenever its last UI connection (this
    # supervisor) drops, and never resumes. That pause is ours to lift; one the
    # owner set from the tray ("pause" true, possibly followed by disconnects)
    # is not.
    for event in reversed(events):
        if event.get("event") == "pause":
            return event.get("detail") != "true"
    return any(e.get("event") == "supervisor_disconnected" for e in events)


def audit_tail(path=AUDIT, size=262144):
    try:
        with open(path, "rb") as audit:
            start = max(0, audit.seek(0, os.SEEK_END) - size)
            audit.seek(start)
            # A partial first line is dropped when reading from the middle.
            lines = audit.read().splitlines()[1 if start else 0:]
    except OSError:
        return []
    events = []
    for line in lines:
        try:
            events.append(json.loads(line))
        except ValueError:
            pass
    return events


def decisions(state, windows):
    # Remove stale grants before granting newly eligible windows. Pausing never
    # emits a resume or a new grant, including after the supervisor reconnects.
    for grant in state.get("grants", []):
        if not allowed(grant, windows):
            yield "revoke", {"id": grant["id"]}
    if (state.get("mode") == "approve" and not state.get("paused")
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

            state = send("state")
            if state.get("paused") and paused_by_disconnect(audit_tail()):
                print("Resuming computer use paused by a supervisor disconnect", flush=True)
                send("pause", paused=False)
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

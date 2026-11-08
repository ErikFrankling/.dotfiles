"""Durable retry decisions for health-watch (called under its existing flock).

The monitors and T3 own observation/execution. This stores the missing per-incident
attempt identity: no upstream component correlates their state for this watcher.
"""
import json
import os
import re
from pathlib import Path
import sys
from datetime import datetime


def key(line):
    return line.split(": ", 1)[0].split(" (", 1)[0]


def epoch(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def decide(state, data):
    now = data["now"]
    attempts = state.setdefault("attempts", {})
    # Import the previous controller's confirmed attempts once. A deployment
    # of this fix must not itself resurrect an unchanged incident.
    if not state.get("migrated"):
        for line in data.get("previous", "").splitlines():
            if line:
                attempts[key(line)] = {"revision": "", "quota": 0}
        state["migrated"] = True
    projects = {p["id"] for p in data["shell"]["projects"]
                if p.get("workspaceRoot") == data["root"]}
    owners = [t for t in data["shell"]["threads"] if t["projectId"] in projects]
    resets = [epoch(t["limitRecovery"]["resetAt"]) for t in owners
              if (t.get("limitRecovery") or {}).get("resetAt")]
    state["quotaReset"] = max([state.get("quotaReset", 0)] + resets)
    reset = state["quotaReset"]
    blocked = reset > now
    # Give T3's armed resume time to run. If it never starts, the passed quota
    # reset is one changed blocker; a stale autoResume flag cannot deadlock us.
    owned = any(t.get("activeRunId") or t.get("pendingBackgroundTasks") or
                ((t.get("limitRecovery") or {}).get("autoResume") and
                 epoch(t["limitRecovery"]["resetAt"]) + 1800 > now) for t in owners)

    # Recovery requires ten continuous minutes of successful observations.
    # Missing APIs, missing endpoints and maintenance filtering are NOT recovery.
    health = {}
    health["monitor/gatus"] = data.get("statuses") is not None
    health["monitor/alertmanager"] = data.get("alerts") is not None
    if data.get("statuses") is not None:
        for endpoint in data["statuses"]:
            results = endpoint.get("results", [])
            if results:
                last = results[-1]
                fresh = now - epoch(last["timestamp"]) < 600
                health[f'{endpoint["group"]}/{endpoint["name"]}'] = fresh and last["success"]
    if data.get("alerts") is not None:
        active = set()
        for alert in data["alerts"]:
            labels = alert["labels"]
            identity = "/".join(str(labels[k]) for k in sorted(labels)
                                if k not in ("alertname", "severity", "project", "session"))
            active.add("alert/" + labels["alertname"] + ("/" + identity if identity else ""))
        for incident in attempts:
            if incident.startswith("alert/"):
                health[incident] = incident not in active
    for incident, attempt in list(attempts.items()):
        # A deployment can temporarily empty Alertmanager while rules re-arm.
        maintained = any(w["end"] + 600 > now and re.search(w["pattern"], incident)
                         for w in data.get("maintenance", []))
        if not maintained and health.get(incident) is True:
            since = attempt.setdefault("healthySince", now)
            if now - since >= 600:
                del attempts[incident]
        else:
            attempt.pop("healthySince", None)

    eligible = []
    revisions = state.setdefault("revisions", {})
    for line in data["failing"].splitlines():
        if not line:
            continue
        incident = key(line)
        attempt = attempts.get(incident)
        revision = revisions.get(incident, "")
        quota = reset if reset and now >= reset else 0
        if attempt is None or attempt["revision"] != revision or quota > attempt["quota"]:
            eligible.append(line)
    reason = "quota-blocked" if blocked else "existing-owner" if owned else "unchanged" if not eligible else "changed-evidence"
    return {"eligible": "\n".join(eligible) if not blocked and not owned else "",
            "reason": reason, "quotaReset": reset, "outstanding": len(attempts)}


def main():
    path = Path(sys.argv[1])
    mode = sys.argv[2]
    data = json.load(sys.stdin)
    state = json.loads(path.read_text()) if path.exists() else {}
    if mode == "changed":
        if not data["evidence"].strip():
            raise ValueError("A concrete changed revision or cleared blocker is required")
        state.setdefault("revisions", {})[data["key"]] = data["evidence"]
        result = {"recorded": data["key"]}
    elif mode == "commit":
        for line in data["eligible"].splitlines():
            incident = key(line)
            state.setdefault("attempts", {})[incident] = {
                "revision": state.get("revisions", {}).get(incident, ""),
                "quota": data["quotaReset"] if data["now"] >= data["quotaReset"] else 0,
            }
        result = {"recorded": True}
    else:
        result = decide(state, data)
    if not data.get("dry", False):
        temporary = path.with_suffix(".tmp")
        with temporary.open("w") as output:
            json.dump(state, output, sort_keys=True)
            output.flush()
            os.fsync(output.fileno())
        temporary.replace(path)
    print(json.dumps(result))


if __name__ == "__main__":
    main()

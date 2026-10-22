"""todo-nudge: wake the personal agent while its to-do list has work it can do.

Reads the front matter of every item in the to-do folder (contract:
~/.t3/personal/todo/README.md), works out which items can move now, and when
the personal-agent thread is idle sends it one automated "work the to-do list"
message through the `t3 thread` CLI. Runs every minute from a user timer.

Decision logic is pure (`actionable_items`, `agent_idle`, `decide`) so the
tests can drive it with fixtures; `main` does the I/O.
"""

import argparse
import datetime as dt
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

import yaml

AGENT_THREAD = "personal-agent"
TODO_DIR = Path.home() / ".t3/personal/todo"
STATE_DIR = Path.home() / ".local/state/todo-nudge"

IDLE_SECONDS = 120  # the agent must have been quiet this long
REPEAT_SECONDS = 30 * 60  # same set, nothing changed: nudge again after this
MAX_PER_HOUR = 4
LOG_MAX_BYTES = 1_000_000

PREFIX = "[automated: todo-nudge, not Erik]"

# Run statuses of a thread that is doing nothing (OrchestratorMcpThreadStatus).
SETTLED = {"idle", "completed", "interrupted", "failed", "cancelled", "rolled_back"}


class Malformed(Exception):
    pass


def now_utc():
    return dt.datetime.now(dt.timezone.utc)


def parse_time(value):
    """A YAML date/datetime or ISO string; naive times are local time."""
    if isinstance(value, dt.datetime):
        t = value
    elif isinstance(value, dt.date):
        t = dt.datetime(value.year, value.month, value.day)
    elif isinstance(value, str):
        t = dt.datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    else:
        raise ValueError(f"not a time: {value!r}")
    if t.tzinfo is None:
        t = t.astimezone()
    return t.astimezone(dt.timezone.utc)


def flat_fields(block):
    data = {}
    for line in block.splitlines():
        key, sep, value = line.partition(":")
        if not sep or not key.strip() or key[0].isspace():
            continue
        value = value.split(" #", 1)[0].strip().strip("'\"")
        data[key.strip()] = value or None
    return data


def front_matter(text):
    if not text.startswith("---"):
        raise Malformed("no front matter")
    parts = text.split("\n---", 1)
    if len(parts) != 2:
        raise Malformed("front matter not closed")
    try:
        data = yaml.safe_load(parts[0][3:])
    except yaml.YAMLError as e:
        # Agents write flat `key: value` lines; a title like "Boxers: pick"
        # is not valid YAML but still readable that way.
        data = flat_fields(parts[0][3:])
        if "status" not in data:
            raise Malformed(f"bad YAML: {str(e).splitlines()[0]}")
    if not isinstance(data, dict):
        raise Malformed("front matter is not a mapping")
    return data


def read_items(todo_dir):
    """[(slug, front matter)] and [(slug, error)] for todo/*.md (not done/)."""
    items, errors = [], []
    for path in sorted(Path(todo_dir).glob("*.md")):
        if path.name == "README.md":
            continue
        slug = path.stem
        try:
            items.append((slug, front_matter(path.read_text(encoding="utf-8"))))
        except (Malformed, OSError, UnicodeDecodeError) as e:
            errors.append((slug, str(e)))
    return items, errors


def fingerprint(todo_dir):
    """Changes whenever an item file is added, removed or edited."""
    h = hashlib.sha256()
    for path in sorted(Path(todo_dir).glob("*.md")):
        if path.name == "README.md":
            continue
        h.update(path.name.encode())
        try:
            h.update(path.read_bytes())
        except OSError:
            pass
    return h.hexdigest()[:16]


def owner_running(info):
    """An in_flight owner still moves by itself unless it stopped or waits."""
    if info is None:
        return False  # unreadable or deleted thread: the agent must chase it
    if info.get("pendingRequestCount", 0) > 0:
        return False
    return info.get("status") not in SETTLED | {"waiting"}


def actionable_items(items, now, owner_info):
    """Slugs that can move now, and per-item errors for malformed ones.

    owner_info(thread_id) -> thread dict or None; only called for in_flight.
    """
    actionable, errors = [], []
    for slug, fm in items:
        status = fm.get("status")
        if status == "actionable":
            actionable.append(slug)
        elif status == "blocked":
            until = fm.get("blocked_until")
            if until is None:
                continue
            try:
                if parse_time(until) <= now:
                    actionable.append(slug)
            except (ValueError, TypeError) as e:
                errors.append((slug, f"bad blocked_until: {e}"))
        elif status == "in_flight":
            owner = fm.get("owner")
            if not owner:
                errors.append((slug, "in_flight without owner"))
                actionable.append(slug)
            elif not owner_running(owner_info(str(owner))):
                actionable.append(slug)
        elif status in ("standing", "done"):
            continue
        else:
            errors.append((slug, f"unknown status {status!r}"))
    return actionable, errors


def agent_idle(thread, now):
    """(idle?, reason). Idle = no run, nothing queued or asked, quiet for a while."""
    if thread is None:
        return False, "personal-agent unreadable"
    limit = thread.get("usageLimit")
    if limit:
        reset = limit.get("resetAt")
        if reset is None or parse_time(reset) > now:
            return False, f"usage limit (resets {reset})"
    if thread.get("activeRunId"):
        return False, f"busy ({thread.get('status')})"
    if thread.get("status") not in SETTLED:
        return False, f"busy ({thread.get('status')})"
    if thread.get("pendingRequestCount", 0) > 0:
        return False, "waiting for an answer"
    quiet = (now - parse_time(thread["updatedAt"])).total_seconds()
    if quiet < IDLE_SECONDS:
        return False, f"idle only {int(quiet)}s"
    return True, f"idle {int(quiet)}s"


def decide(actionable, fp, state, now):
    """(nudge?, reason) from the loop protection rules."""
    recent = [t for t in state.get("nudges", []) if (now - parse_time(t)).total_seconds() < 3600]
    if len(recent) >= MAX_PER_HOUR:
        return False, f"cap: {len(recent)} nudges in the last hour"
    last = state.get("last_nudge_at")
    if last is None:
        return True, "first nudge"
    if fp != state.get("last_fingerprint"):
        return True, "todo/ changed since last nudge"
    if sorted(actionable) != sorted(state.get("last_set", [])):
        return True, "actionable set changed"
    since = (now - parse_time(last)).total_seconds()
    if since >= REPEAT_SECONDS:
        return True, f"unchanged for {int(since // 60)} min"
    return False, f"unchanged, last nudge {int(since // 60)} min ago"


def message(actionable):
    return (
        f"{PREFIX} {len(actionable)} actionable items: {', '.join(actionable)}. "
        "Work the to-do list: do what can be done now (start or chase sessions), "
        "and mark everything that can't move as blocked with the reason "
        "(see todo/README.md). Only stop when all items are blocked, standing or in flight."
    )


# --- I/O -------------------------------------------------------------------


def t3_show(thread_id):
    try:
        out = subprocess.run(
            ["t3", "thread", "show", thread_id, "--json", "--messages", "0"],
            capture_output=True, text=True, timeout=60, check=True,
        ).stdout
        return json.loads(out)["thread"]
    except (subprocess.SubprocessError, OSError, ValueError, KeyError):
        return None


def t3_send(thread_id, text):
    out = subprocess.run(
        ["t3", "thread", "send", thread_id, text, "--json"],
        capture_output=True, text=True, timeout=60, check=True,
    ).stdout
    return json.loads(out)


def log(line, dry):
    stamped = f"{now_utc().astimezone().isoformat(timespec='seconds')} {line}"
    print(stamped)
    if dry:
        return
    path = STATE_DIR / "decisions.log"
    if path.exists() and path.stat().st_size > LOG_MAX_BYTES:
        path.replace(path.with_suffix(".log.1"))
    with path.open("a") as f:
        f.write(stamped + "\n")


def load_state():
    try:
        return json.loads((STATE_DIR / "state.json").read_text())
    except (OSError, ValueError):
        return {}


def save_state(state):
    tmp = STATE_DIR / "state.json.tmp"
    tmp.write_text(json.dumps(state, indent=2))
    tmp.replace(STATE_DIR / "state.json")


def main(argv=None):
    p = argparse.ArgumentParser(prog="todo-nudge")
    p.add_argument("--dry-run", action="store_true", help="decide and print, send nothing")
    args = p.parse_args(argv)
    dry = args.dry_run
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    now = now_utc()

    items, errors = read_items(TODO_DIR)
    owners = {}

    def owner_info(tid):
        if tid not in owners:
            owners[tid] = t3_show(tid)
        return owners[tid]

    # Cheap pass first: skip every thread lookup when nothing could count.
    if not any(fm.get("status") in ("actionable", "blocked", "in_flight") for _, fm in items):
        for slug, err in errors:
            log(f"skip-file {slug}: {err}", dry)
        log(f"no-nudge: nothing actionable ({len(items)} items)", dry)
        return 0

    agent = t3_show(AGENT_THREAD)
    idle, why_idle = agent_idle(agent, now)
    actionable, item_errors = actionable_items(items, now, owner_info) if idle or dry else ([], [])
    for slug, err in errors + item_errors:
        log(f"skip-file {slug}: {err}", dry)
    if not idle:
        log(f"no-nudge: {why_idle}" + (f"; actionable={','.join(actionable)}" if dry else ""), dry)
        return 0
    if not actionable:
        log(f"no-nudge: nothing actionable ({len(items)} items, agent {why_idle})", dry)
        return 0

    state = load_state()
    fp = fingerprint(TODO_DIR)
    go, why = decide(actionable, fp, state, now)
    if not go:
        log(f"no-nudge: {why}; actionable={','.join(actionable)}", dry)
        return 0
    if dry:
        log(f"would-nudge ({why}): {','.join(actionable)}", dry)
        return 0
    try:
        sent = t3_send(AGENT_THREAD, message(actionable))
    except (subprocess.SubprocessError, OSError, ValueError) as e:
        log(f"send-failed: {e}", dry)
        return 1
    stamp = now.isoformat()
    state["nudges"] = [
        t for t in state.get("nudges", []) if (now - parse_time(t)).total_seconds() < 3600
    ] + [stamp]
    state.update(last_nudge_at=stamp, last_fingerprint=fp, last_set=sorted(actionable))
    save_state(state)
    log(
        f"NUDGE ({why}, agent {why_idle}) run={sent.get('runId')} "
        f"delivery={sent.get('delivery')}: {','.join(actionable)}",
        dry,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

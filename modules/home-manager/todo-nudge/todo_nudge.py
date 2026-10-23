"""todo-nudge: wake the personal agent while its to-do list has work it can do.

The message carries the entire list (blocked items too, triggers marked *) so
the agent re-checks every blocker; with nothing able to move it still sends a
full review once an hour.

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
import shlex
import subprocess
import sys
import urllib.request
from pathlib import Path

import yaml

AGENT_THREAD = "personal-agent"
TODO_DIR = Path.home() / ".t3/personal/todo"
STATE_DIR = Path.home() / ".local/state/todo-nudge"

IDLE_SECONDS = 120  # the agent must have been quiet this long
REPEAT_SECONDS = 30 * 60  # same set, nothing changed: nudge again after this
MAX_PER_HOUR = 4
REVIEW_SECONDS = 60 * 60  # full review of every item, blocked ones too
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


def agent_idle(thread, now, idle_since=None):
    """(idle?, reason). Idle = no run, nothing queued or asked, quiet for a while.

    idle_since: when this script first saw the thread settled in this state.
    It covers an updatedAt in the future, which a wrong clock leaves behind
    (the RTC runs in local time, so a hard reboot can start two hours off).
    """
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
    if idle_since is not None:
        quiet = max(quiet, (now - parse_time(idle_since)).total_seconds())
    if quiet < IDLE_SECONDS:
        return False, f"idle only {int(quiet)}s"
    return True, f"idle {int(quiet)}s"


def settled_key(thread):
    """Identifies one quiet stretch of the thread; None while it is busy."""
    if thread is None or thread.get("activeRunId") or thread.get("status") not in SETTLED:
        return None
    return f"{thread.get('latestRunId')}|{thread.get('updatedAt')}"


def decide(actionable, fp, state, now):
    """(nudge?, reason, hourly?) from the trigger and loop protection rules.

    Something not blocked can move: nudge (rate limited). Nothing can: still a
    full review once an hour, since blockers clear without the files changing.
    """
    recent = [t for t in state.get("nudges", []) if 0 <= (now - parse_time(t)).total_seconds() < 3600]
    if len(recent) >= MAX_PER_HOUR:
        return False, f"cap: {len(recent)} nudges in the last hour", False
    last = state.get("last_nudge_at")
    if last is None:
        return True, "first nudge", not actionable
    since = (now - parse_time(last)).total_seconds()
    if actionable:
        if fp != state.get("last_fingerprint"):
            return True, "todo/ changed since last nudge", False
        if sorted(actionable) != sorted(state.get("last_set", [])):
            return True, "actionable set changed", False
        if since >= REPEAT_SECONDS:
            return True, f"unchanged for {int(since // 60)} min", False
        return False, f"unchanged, last nudge {int(since // 60)} min ago", False
    if since >= REVIEW_SECONDS:
        return True, "hourly review", True
    return False, f"all blocked, standing or running; review in {int((REVIEW_SECONDS - since) // 60)} min", False


def owner_state(info):
    if info is None:
        return "gone"
    if info.get("pendingRequestCount", 0) > 0:
        return "asking"
    return info.get("status", "?")


def item_line(slug, fm, triggered, owner_info, now):
    status = fm.get("status")
    detail = str(status)
    if status == "in_flight":
        owner = fm.get("owner")
        if owner:
            info = owner_info(str(owner))
            run = "running" if owner_running(info) else f"stopped: {owner_state(info)}"
            detail += f", owner {owner} {run}"
        else:
            detail += ", no owner"
    elif status == "blocked":
        if fm.get("blocked_on"):
            detail += f" on {fm.get('blocked_on')}"
        until = fm.get("blocked_until")
        if until is not None:
            try:
                passed = parse_time(until) <= now
            except (ValueError, TypeError):
                passed = False
            shown = until.isoformat(timespec="minutes") if isinstance(until, dt.datetime) else until
            detail += f" until {shown}" + (" (passed)" if passed else "")
    title = " ".join(str(fm.get("title") or "(no title)").split())
    return f"{'*' if triggered else '-'} {slug} [{detail}] {title}"


# Triggering items first, then what moves, then the rest.
ORDER = {"actionable": 0, "in_flight": 1, "standing": 2, "blocked": 3}


def message(items, actionable, owner_info, now, unreadable=(), hourly=False, time_line=None,
            calendar=None):
    """The entire list (everything but done), one line per item.

    Items that triggered the nudge are marked *. Blocked items are listed too:
    the agent re-checks whether each blocker has cleared.
    """
    trigger = set(actionable)
    open_items = [(slug, fm) for slug, fm in items if fm.get("status") != "done"]
    open_items.sort(key=lambda i: (i[0] not in trigger, ORDER.get(i[1].get("status"), 4)))
    lines = [item_line(slug, fm, slug in trigger, owner_info, now) for slug, fm in open_items]
    counts = {}
    for _, fm in open_items:
        counts[fm.get("status")] = counts.get(fm.get("status"), 0) + 1
    summary = ", ".join(f"{n} {st}" for st, n in sorted(counts.items(), key=lambda c: str(c[0])))
    kind = "hourly review" if hourly else f"{len(trigger)} can move now, marked *"
    head = f"{PREFIX} To-do list ({kind}): {len(lines)} items ({summary})"
    if unreadable:
        head += f", {len(unreadable)} unreadable ({', '.join(unreadable)})"
    body = [head + ":", *lines, ""]
    if time_line:
        body += [f"Time, last hour: {time_line}", ""]
    if calendar:
        body += [calendar, ""]
    body.append(
        "Review every item, blocked ones too: re-check whether each blocker has "
        "cleared, do what can be done now (start or chase sessions), and move "
        "finished items to done/ (see todo/README.md). End with every item done, "
        "blocked with the reason, standing, or in flight with a running owner. "
        "If all are still blocked, just finish."
    )
    return "\n".join(body)


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


def time_summary():
    """One line on what Erik did in the last hour, from the Time server.

    Hook for the hourly review: set TODO_NUDGE_TIME_URL to an HTTP endpoint
    returning text or JSON {"summary": "..."}; unset or failing = no line.
    """
    url = os.environ.get("TODO_NUDGE_TIME_URL")
    if not url:
        return None
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            raw = r.read(4096).decode("utf-8", "replace")
    except (OSError, ValueError):
        return None
    try:
        data = json.loads(raw)
        raw = data.get("summary", "") if isinstance(data, dict) else str(data)
    except ValueError:
        pass
    line = " ".join(str(raw).split())
    return line[:300] or None


def calendar_block():
    """Erik's next 24 hours, from the `calendar-next` command.

    Hook: TODO_NUDGE_CALENDAR_CMD is a command (shell words) that prints a
    compact calendar block on stdout; unset or failing = no block.
    """
    cmd = os.environ.get("TODO_NUDGE_CALENDAR_CMD")
    if not cmd:
        return None
    try:
        out = subprocess.run(
            shlex.split(cmd), capture_output=True, text=True, timeout=30, check=True,
        ).stdout
    except (subprocess.SubprocessError, OSError, ValueError):
        return None
    lines = [line.rstrip() for line in out.strip().splitlines()]
    return "\n".join(lines)[:2000] or None


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

    state = load_state()
    last = state.get("last_nudge_at")
    review_due = last is None or (now - parse_time(last)).total_seconds() >= REVIEW_SECONDS
    unreadable = [s for s, _ in errors]

    # Cheap pass first: skip every thread lookup when nothing could count.
    could_trigger = any(fm.get("status") in ("actionable", "blocked", "in_flight") for _, fm in items)
    if not items or not (could_trigger or review_due):
        for slug, err in errors:
            log(f"skip-file {slug}: {err}", dry)
        log(f"no-nudge: nothing actionable ({len(items)} items)", dry)
        return 0

    agent = t3_show(AGENT_THREAD)
    idle_key = settled_key(agent)
    seen = state.get("idle_seen") or {}
    if idle_key is None:
        state.pop("idle_seen", None)
    elif seen.get("key") != idle_key:
        seen = state["idle_seen"] = {"key": idle_key, "since": now.isoformat()}
    if not dry:
        save_state(state)
    idle, why_idle = agent_idle(agent, now, seen.get("since") if idle_key else None)
    actionable, item_errors = actionable_items(items, now, owner_info) if idle or dry else ([], [])
    for slug, err in errors + item_errors:
        log(f"skip-file {slug}: {err}", dry)
    if not idle:
        log(f"no-nudge: {why_idle}" + (f"; actionable={','.join(actionable)}" if dry else ""), dry)
        if dry:
            print(message(items, actionable, owner_info, now, unreadable))
        return 0

    fp = fingerprint(TODO_DIR)
    go, why, hourly = decide(actionable, fp, state, now)
    if not go:
        log(f"no-nudge: {why}; actionable={','.join(actionable)}", dry)
        return 0
    text = message(
        items, actionable, owner_info, now, unreadable,
        hourly=hourly, time_line=time_summary() if hourly else None,
        calendar=calendar_block(),
    )
    if dry:
        log(f"would-nudge ({why}): {','.join(actionable)}", dry)
        print(text)
        return 0
    try:
        sent = t3_send(AGENT_THREAD, text)
    except (subprocess.SubprocessError, OSError, ValueError) as e:
        log(f"send-failed: {e}", dry)
        return 1
    stamp = now.isoformat()
    state["nudges"] = [
        t for t in state.get("nudges", []) if 0 <= (now - parse_time(t)).total_seconds() < 3600
    ] + [stamp]
    state.update(last_nudge_at=stamp, last_fingerprint=fp, last_set=sorted(actionable))
    save_state(state)
    log(
        f"NUDGE ({why}, agent {why_idle}) run={sent.get('runId')} "
        f"delivery={sent.get('delivery')} items={len(items)}: {','.join(actionable) or '-'}",
        dry,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""calendar-next: Erik's upcoming events as a compact block, and meeting reminders.

Sources (read-only, nothing is ever created, accepted, declined or sent):
- Google Calendar through the Executor app `calendar` (tools.calendar.upcoming),
  called over Executor's MCP endpoint with the API key in /run/secrets.
- KTH Canvas: the calendar feed (ICS) the Canvas API names in the profile of
  the read-only Canvas token (`agent-canvas-token`). Timed items (labs,
  seminars, extra sessions) are events; zero-length items are deadlines and
  go on a "Due" line.

    calendar-next [--hours 24] [--json]     print the block
    calendar-next remind [--speak-cmd CMD]  speak "<title> in ten minutes"
                                            about 10 min before each event

State and logs: ~/.local/state/calendar/ (cache.json, reminded.json,
reminders.log). Tests: test_calendar_next.py (run at build time).
"""

import argparse
import datetime as dt
import json
import math
import os
import re
import shlex
import subprocess
import sys
import urllib.request
from pathlib import Path

EXECUTOR_URL = os.environ.get("CALENDAR_EXECUTOR_URL", "https://executor.erikfrankling.duckdns.org/mcp")
EXECUTOR_KEY_FILE = os.environ.get("CALENDAR_EXECUTOR_KEY_FILE", "/run/secrets/executor-api-key")
CALENDAR_APP = "app_5f3b9389-6c1b-4aab-867f-9c06fc59eb8a"  # Executor app "Calendar"
CANVAS_API = "https://canvas.kth.se/api/v1/users/self/profile"
STATE_DIR = Path(os.environ.get("CALENDAR_STATE_DIR", Path.home() / ".local/state/calendar"))
CACHE_FRESH_SECONDS = 4 * 60
CACHE_STALE_SECONDS = 3 * 3600
REMIND_BEFORE = dt.timedelta(minutes=10)
REMIND_SLACK = dt.timedelta(seconds=45)
LOG_MAX_BYTES = 200_000


def now_utc():
    return dt.datetime.now(dt.timezone.utc)


def local_tz():
    return now_utc().astimezone().tzinfo


# --- events ----------------------------------------------------------------


def parse_when(value):
    """ISO date or date-time -> (aware datetime, all_day)."""
    value = value.strip()
    if len(value) == 10:
        return dt.datetime.fromisoformat(value).replace(tzinfo=local_tz()), True
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    return (parsed if parsed.tzinfo else parsed.replace(tzinfo=local_tz())), False


def make_event(source, title, start, end, all_day=False, where=None, link=None,
               meet=None, attendees=(), uid=None):
    return {
        "source": source, "title": " ".join(str(title).split()) or "(no title)",
        "start": start, "end": end, "all_day": all_day, "where": where or None,
        "link": link or None, "meet": meet or None, "attendees": list(attendees),
        "uid": uid or f"{source}:{title}:{start.isoformat()}",
    }


def google_events(value):
    """Events of tools.calendar.upcoming(...) -> event dicts."""
    out = []
    for e in value.get("events", []):
        start, all_day = parse_when(e["start"])
        end, _ = parse_when(e["end"])
        if e.get("myResponse") == "declined":
            continue
        guests = [a.get("name") or a.get("email") for a in e.get("attendees", [])
                  if a.get("response") != "declined"]
        out.append(make_event(
            "google", e["title"], start, end, all_day, e.get("where"), e.get("link"),
            e.get("meetLink"), guests if len(guests) > 1 else [],
        ))
    return out


def unfold_ics(text):
    lines = []
    for raw in text.replace("\r\n", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        else:
            lines.append(raw)
    return lines


def ics_unescape(value):
    return re.sub(r"\\([nN,;\\])", lambda m: "\n" if m.group(1) in "nN" else m.group(1), value)


def ics_when(params, value):
    if params.get("VALUE") == "DATE" or len(value) == 8:
        return dt.datetime.strptime(value, "%Y%m%d").replace(tzinfo=local_tz()), True
    if value.endswith("Z"):
        return dt.datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=dt.timezone.utc), False
    naive = dt.datetime.strptime(value, "%Y%m%dT%H%M%S")
    tzid = params.get("TZID")
    try:
        from zoneinfo import ZoneInfo
        return naive.replace(tzinfo=ZoneInfo(tzid) if tzid else local_tz()), False
    except Exception:  # unknown zone name: treat as local
        return naive.replace(tzinfo=local_tz()), False


def canvas_events(ics_text):
    """(timed events, deadline events) from a Canvas calendar feed."""
    timed, due = [], []
    props = None
    for line in unfold_ics(ics_text):
        if line == "BEGIN:VEVENT":
            props = {}
        elif line == "END:VEVENT" and props is not None:
            if "DTSTART" in props:
                try:
                    start, all_day = ics_when(*props["DTSTART"])
                    end, _ = ics_when(*props["DTEND"]) if "DTEND" in props else (start, all_day)
                except ValueError:
                    props = None
                    continue
                title = ics_unescape(props.get("SUMMARY", ("", ""))[1])
                where = ics_unescape(props.get("LOCATION", ("", ""))[1])
                url = props.get("URL", ("", ""))[1]
                uid = props.get("UID", ("", ""))[1]
                ev = make_event("canvas", title, start, end, all_day, where, url, None, (), uid or None)
                (timed if end > start and not all_day else due).append(ev)
            props = None
        elif props is not None and ":" in line:
            head, _, value = line.partition(":")
            name, *params = head.split(";")
            props[name.upper()] = (dict(p.split("=", 1) for p in params if "=" in p), value)
    return timed, due


# --- sources ---------------------------------------------------------------


def mcp_execute(code, timeout=30):
    key = Path(EXECUTOR_KEY_FILE).read_text().strip()
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json",
               "Accept": "application/json, text/event-stream"}

    def post(payload, session=None):
        h = dict(headers, **({"Mcp-Session-Id": session} if session else {}))
        req = urllib.request.Request(EXECUTOR_URL, json.dumps(payload).encode(), h)
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.headers.get("Mcp-Session-Id"), r.read().decode()

    sid, _ = post({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-06-18", "capabilities": {},
        "clientInfo": {"name": "calendar-next", "version": "1"}}})
    post({"jsonrpc": "2.0", "method": "notifications/initialized"}, sid)
    _, body = post({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                    "params": {"name": "execute", "arguments": {"code": code}}}, sid)
    data = next((l[6:] for l in body.splitlines() if l.startswith("data: ")), body)
    text = json.loads(data)["result"]["content"][0]["text"]
    return json.loads(text)


def fetch_google(hours):
    days = max(hours / 24, 0.1)
    result = mcp_execute(f"return await tools.calendar.upcoming({{ days: {days:.3f} }});")
    execution = result.get("execution", {})
    if not execution.get("ok"):
        err = execution.get("error") or result.get("error") or result
        raise RuntimeError(str(err.get("message") if isinstance(err, dict) else err)[:200])
    return google_events(execution["value"])


def http_get(url, headers=None, timeout=20):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def fetch_canvas():
    token = subprocess.run(["agent-canvas-token"], capture_output=True, text=True, check=True).stdout.strip()
    profile = json.loads(http_get(CANVAS_API, {"Authorization": f"Bearer {token}"}))
    return canvas_events(http_get(profile["calendar"]["ics"]))


def event_to_json(ev):
    return dict(ev, start=ev["start"].isoformat(), end=ev["end"].isoformat())


def event_from_json(d):
    return dict(d, start=dt.datetime.fromisoformat(d["start"]), end=dt.datetime.fromisoformat(d["end"]))


def load_cache():
    try:
        c = json.loads((STATE_DIR / "cache.json").read_text())
        return {"fetched_at": dt.datetime.fromisoformat(c["fetched_at"]),
                "timed": [event_from_json(e) for e in c["timed"]],
                "due": [event_from_json(e) for e in c["due"]], "errors": c.get("errors", [])}
    except (OSError, ValueError, KeyError):
        return None


def save_cache(now, timed, due, errors):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = STATE_DIR / "cache.json.tmp"
    tmp.write_text(json.dumps({"fetched_at": now.isoformat(), "errors": errors,
                               "timed": [event_to_json(e) for e in timed],
                               "due": [event_to_json(e) for e in due]}))
    tmp.replace(STATE_DIR / "cache.json")


def gather(now, hours, max_cache_age=0, use=("google", "canvas")):
    """(timed, due, notes). Uses the cache when it is younger than max_cache_age
    seconds; falls back to a cache younger than CACHE_STALE_SECONDS when a
    source fails, and says so in notes."""
    cache = load_cache()
    if cache and max_cache_age and (now - cache["fetched_at"]).total_seconds() < max_cache_age:
        return cache["timed"], cache["due"], cache["errors"]
    timed, due, notes = [], [], []
    ok = {}
    if "google" in use:
        try:
            timed += fetch_google(max(hours, 24))
            ok["google"] = True
        except Exception as e:  # network, auth, account not linked
            notes.append(f"google unavailable: {str(e)[:120]}")
    if "canvas" in use:
        try:
            t, d = fetch_canvas()
            timed += t
            due += d
            ok["canvas"] = True
        except Exception as e:
            notes.append(f"canvas unavailable: {str(e)[:120]}")
    if notes and cache and (now - cache["fetched_at"]).total_seconds() < CACHE_STALE_SECONDS:
        age = int((now - cache["fetched_at"]).total_seconds() // 60)
        keep = [e for e in cache["timed"] if e["source"] not in ok]
        timed += keep
        due += [e for e in cache["due"] if e["source"] not in ok]
        if keep:
            notes.append(f"{keep[0]['source']}: showing cached data from {age} min ago")
    if ok:
        save_cache(now, timed, due, notes)
    return timed, due, notes


# --- output ----------------------------------------------------------------

WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def day_label(d):
    return f"{WEEKDAYS[d.weekday()]} {d.day} {MONTHS[d.month - 1]}"


def in_window(ev, now, until):
    return ev["end"] > now and ev["start"] < until


def render(timed, due, notes, now, hours):
    local = now.astimezone()
    until = now + dt.timedelta(hours=hours)
    shown = sorted((e for e in timed if in_window(e, now, until)), key=lambda e: (e["start"], e["title"]))
    head = f"Calendar, next {int(hours) if hours == int(hours) else hours}h (now {day_label(local)} {local:%H:%M}):"
    lines = [head]
    if not shown:
        lines.append("  nothing found (a source failed, see below)" if any("unavailable" in n for n in notes) else "  nothing scheduled")
    day = None
    for ev in shown:
        start, end = ev["start"].astimezone(), ev["end"].astimezone()
        if start.date() != day:
            day = start.date()
            lines.append(day_label(start))
        when = "all day" if ev["all_day"] else f"{start:%H:%M}-{end:%H:%M}"
        bits = [ev["title"]]
        bits += [b for b in (ev["where"], ev["meet"] or ev["link"]) if b]
        if ev["attendees"]:
            bits.append("with " + ", ".join(ev["attendees"][:5]))
        tag = " (now)" if start <= local <= end and not ev["all_day"] else ""
        lines.append(f"  {when}{tag} {' | '.join(bits)}")
    soon = sorted((e for e in due if now <= e["start"] <= until), key=lambda e: e["start"])
    if soon:
        names = [f"{e['start'].astimezone():%H:%M} {spoken_title(e['title'])}" for e in soon[:5]]
        lines.append("Due (Canvas): " + "; ".join(names) + (f"; +{len(soon) - 5} more" if len(soon) > 5 else ""))
    lines += [f"({n})" for n in notes]
    return "\n".join(lines)


# --- reminders -------------------------------------------------------------


def spoken_title(title):
    return re.sub(r" \[[^]]*\]$", "", title).strip() or title


def spoken_text(ev, now):
    minutes = math.ceil((ev["start"] - now).total_seconds() / 60)
    when = "in ten minutes" if minutes >= 9 else (f"in {minutes} minutes" if minutes > 1 else "in a minute")
    return f"{spoken_title(ev['title'])} {when}"


def reminders_due(timed, now, reminded):
    out = []
    for ev in sorted(timed, key=lambda e: e["start"]):
        if ev["all_day"] or ev["uid"] + "|" + ev["start"].isoformat() in reminded:
            continue
        if now < ev["start"] <= now + REMIND_BEFORE + REMIND_SLACK:
            out.append(ev)
    return out


def log_line(line):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    stamped = f"{now_utc().astimezone().isoformat(timespec='seconds')} {line}"
    print(stamped)
    path = STATE_DIR / "reminders.log"
    if path.exists() and path.stat().st_size > LOG_MAX_BYTES:
        path.replace(path.with_suffix(".log.1"))
    with path.open("a") as f:
        f.write(stamped + "\n")


def run_remind(args, now):
    reminded_path = STATE_DIR / "reminded.json"
    try:
        reminded = json.loads(reminded_path.read_text())
    except (OSError, ValueError):
        reminded = {}
    horizon = (now - dt.timedelta(days=1)).isoformat()
    reminded = {k: v for k, v in reminded.items() if v > horizon}
    if args.fixture:
        timed = fixture_events(args.fixture)
        notes = []
    else:
        timed, _, notes = gather(now, 24, max_cache_age=CACHE_FRESH_SECONDS)
    note_path = STATE_DIR / "last-note.txt"
    note = "; ".join(notes)
    try:
        last_note = note_path.read_text()
    except OSError:
        last_note = ""
    if re.sub(r"\d+ min", "N min", note) != re.sub(r"\d+ min", "N min", last_note):  # log a source problem once, not every minute
        log_line(f"source-note: {note or 'all sources ok'}")
        if not args.dry_run:
            note_path.write_text(note)
    sent = 0
    for ev in reminders_due(timed, now, reminded):
        text = spoken_text(ev, now)
        cmd = shlex.split(args.speak_cmd) + [text, "normal"]
        key = ev["uid"] + "|" + ev["start"].isoformat()
        try:
            subprocess.run(cmd, check=True, timeout=120, capture_output=True)
            log_line(f"REMIND [{ev['source']}] {ev['start'].astimezone():%a %H:%M} {ev['title']!r}: said {text!r}"
                     + (" (fixture)" if args.fixture else ""))
            reminded[key] = now.isoformat()
            sent += 1
        except (subprocess.SubprocessError, OSError) as e:
            log_line(f"REMIND-FAILED [{ev['source']}] {ev['title']!r}: {e}")
    if not args.dry_run:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        reminded_path.write_text(json.dumps(reminded))
    return 0


def run_connect():
    """A fresh (30 min) Executor link: Erik signs in to Google and allows read-only calendar access."""
    result = mcp_execute(
        "return await tools.executor.appAccounts.userConnect({ path: { app: '" + CALENDAR_APP + "', "
        "requirement: 'calendar' }, body: {} });")
    execution = result.get("execution", {})
    if not execution.get("ok"):
        print(f"connect failed: {execution.get('error') or result}", file=sys.stderr)
        return 1
    print(execution["value"]["url"])
    return 0


def fixture_events(path):
    out = []
    for e in json.loads(Path(path).read_text()):
        start, all_day = parse_when(e["start"])
        end, _ = parse_when(e["end"])
        out.append(make_event(e.get("source", "fixture"), e["title"], start, end, all_day,
                              e.get("where"), e.get("link"), e.get("meet"), e.get("attendees", [])))
    return out


# --- main ------------------------------------------------------------------


def main(argv=None):
    p = argparse.ArgumentParser(prog="calendar-next")
    p.add_argument("command", nargs="?", choices=["remind", "connect"],
               help="remind: speak upcoming meetings; connect: print a fresh link to (re)connect Google Calendar")
    p.add_argument("--hours", type=float, default=24)
    p.add_argument("--json", action="store_true")
    p.add_argument("--now", help="pretend it is this ISO time (tests)")
    p.add_argument("--fixture", help="JSON list of events instead of the real sources (tests)")
    p.add_argument("--speak-cmd", default="speak say", help="remind: command that gets TEXT and 'normal'")
    p.add_argument("--dry-run", action="store_true", help="remind: do not record what was said")
    args = p.parse_args(argv)
    now = parse_when(args.now)[0] if args.now else now_utc()
    if args.command == "remind":
        return run_remind(args, now)
    if args.command == "connect":
        return run_connect()
    if args.fixture:
        timed, due, notes = fixture_events(args.fixture), [], []
    else:
        timed, due, notes = gather(now, args.hours)
    if args.json:
        until = now + dt.timedelta(hours=args.hours)
        print(json.dumps({"events": [event_to_json(e) for e in timed if in_window(e, now, until)],
                          "due": [event_to_json(e) for e in due if now <= e["start"] <= until],
                          "notes": notes}, indent=2))
    else:
        print(render(timed, due, notes, now, args.hours))
    return 0


if __name__ == "__main__":
    sys.exit(main())

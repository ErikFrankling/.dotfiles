"""Retention for ~/projects/kth/canvas-archive (run after each daily refresh).

Keeps:
  archive.json                        the latest full copy (refresh.py writes it)
  archive-prev.json                   the previous run, for diff.py
  snapshots/archive-YYYY-Www.json.gz  one full copy per ISO week (the first run of the week)
  changes/YYYY-MM-DD.json.gz          what changed that day: added, removed and changed
                                      Canvas objects per course (the full new object)
  changes/YYYY-MM-DD.md               diff.py's readable changes.md of that day

and deletes the old daily full copies (archive-YYYY-MM-DD.json) only after the
weekly snapshot covering that day exists and reads back as a valid archive, and
that day's change file is written.

usage: canvas-archive-retain.py [archive dir] [--dry-run]
"""
import gzip, json, re, shutil, sys
from datetime import date
from pathlib import Path

args = [a for a in sys.argv[1:] if not a.startswith("--")]
DRY = "--dry-run" in sys.argv
ROOT = Path(args[0] if args else Path.home() / "projects/kth/canvas-archive")
SNAP, CHG = ROOT / "snapshots", ROOT / "changes"
DAILY = re.compile(r"^archive-(\d{4}-\d{2}-\d{2})\.json$")
SKIP_TOP = {"requests", "retrieved_at"}


def load(p):
    with (gzip.open(p, "rt") if p.suffix == ".gz" else open(p)) as f:
        return json.load(f)


def day_of(arch):
    return arch["retrieved_at"][:10]


def week_of(d):
    y, w, _ = date.fromisoformat(d).isocalendar()
    return f"{y}-W{w:02d}"


def key(o):
    if isinstance(o, dict):
        for k in ("id", "page_id", "url"):
            if k in o:
                return f"{k}:{o[k]}"
    return json.dumps(o, sort_keys=True)


def diff_lists(a, b):
    a, b = {key(x): x for x in a or []}, {key(x): x for x in b or []}
    out = {"added": [b[k] for k in b if k not in a], "removed": [k for k in a if k not in b],
           "changed": [b[k] for k in b if k in a and a[k] != b[k]]}
    return {k: v for k, v in out.items() if v}


def diff(old, new):
    """Changes from one archive to the next, keyed by course id and collection."""
    out = {"from": old.get("retrieved_at"), "to": new.get("retrieved_at"), "courses": {}, "top": {}}
    oc = {c["course"]["id"]: c for c in old.get("courses", [])}
    for c in new.get("courses", []):
        cid, o = c["course"]["id"], oc.pop(c["course"]["id"], None)
        if o is None:
            out["courses"][cid] = {"added_course": c}
            continue
        d = {}
        for k in set(c) | set(o):
            if c.get(k) == o.get(k):
                continue
            if isinstance(c.get(k), list) or isinstance(o.get(k), list):
                dl = diff_lists(o.get(k), c.get(k))
                if dl:
                    d[k] = dl
            else:
                d[k] = {"new": c.get(k)}
        if d:
            out["courses"][cid] = d
    for cid in oc:
        out["courses"][cid] = {"removed_course": True}
    for k in (set(new) | set(old)) - SKIP_TOP - {"courses"}:
        if new.get(k) != old.get(k):
            out["top"][k] = diff_lists(old.get(k), new.get(k)) if isinstance(new.get(k), list) else {"new": new.get(k)}
    return out


def write_gz(p, obj):
    tmp = p.with_suffix(p.suffix + ".tmp")
    with gzip.open(tmp, "wt", compresslevel=9) as f:
        json.dump(obj, f, ensure_ascii=False)
    tmp.rename(p)


def snapshot_ok(p, week):
    try:
        a = load(p)
        return bool(a.get("courses")) and week_of(day_of(a)) == week
    except Exception as e:
        print("bad snapshot", p, e)
        return False


def ensure_snapshot(arch, src_name):
    week = week_of(day_of(arch))
    p = SNAP / f"archive-{week}.json.gz"
    if not p.exists():
        print(f"snapshot {p.name} from {src_name}")
        if not DRY:
            write_gz(p, arch)
            if load(p) != arch:  # reads back byte-for-byte equal as data
                p.unlink()
                print("snapshot did not read back equal:", p.name)
                return None
    return p if DRY or snapshot_ok(p, week) else None


def ensure_changes(old, new):
    d = day_of(new)
    p = CHG / f"{d}.json.gz"
    if not p.exists() and old is not None and day_of(old) != d:
        print(f"changes {p.name} ({day_of(old)} -> {d})")
        if not DRY:
            write_gz(p, diff(old, new))
    return p


def main():
    SNAP.mkdir(exist_ok=True)
    CHG.mkdir(exist_ok=True)
    before = sum(f.stat().st_size for f in ROOT.glob("archive*.json"))

    # Old daily copies, oldest first, then the previous and the current run.
    dailies = sorted((m.group(1), ROOT / m.group(0)) for f in ROOT.iterdir() if (m := DAILY.match(f.name)))
    chain = [(d, p, load(p)) for d, p in dailies]
    for name in ("archive-prev.json", "archive.json"):
        if (ROOT / name).exists():
            a = load(ROOT / name)
            if not chain or day_of(a) > day_of(chain[-1][2]):
                chain.append((day_of(a), ROOT / name, a))

    prev = None
    for d, p, a in chain:
        snap = ensure_snapshot(a, p.name)
        ensure_changes(prev, a)
        prev = a
        if DAILY.match(p.name):
            if snap is None:
                print(f"KEEP {p.name}: no valid weekly snapshot for {week_of(day_of(a))}")
                continue
            print(f"{'would delete' if DRY else 'delete'} {p.name} (covered by {snap.name})")
            if not DRY:
                p.unlink()

    md = ROOT / "changes.md"
    cur = ROOT / "archive.json"
    if md.exists() and cur.exists() and not DRY:
        shutil.copy(md, CHG / f"{day_of(load(cur))}.md")

    after = sum(f.stat().st_size for f in ROOT.glob("archive*.json"))
    extra = sum(f.stat().st_size for f in list(SNAP.iterdir()) + list(CHG.iterdir()))
    print(f"archive*.json {before / 1e6:.1f} MB -> {after / 1e6:.1f} MB; snapshots+changes {extra / 1e6:.1f} MB")


if __name__ == "__main__":
    main()

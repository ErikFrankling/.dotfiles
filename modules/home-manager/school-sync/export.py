"""Build the school calendar's item list from the local Canvas archive and push it
to https://school.erikfrankling.duckdns.org (homelab apps/school.yaml).

Reads only local files: archive.json (Canvas API data from refresh.py),
deadlines.json (dates found on course pages), each course's schedule.json
(TimeEdit) and the curated ~/projects/kth/school/overrides.json. Never talks
to Canvas, so it cannot change anything there.

usage: export.py [--no-push]   (SCHOOL_INGEST_TOKEN in the environment to push)
"""
import hashlib, html, json, os, re, sys, urllib.request
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser
from pathlib import Path
from zoneinfo import ZoneInfo

HOME = Path.home()
ARCHIVE = Path(os.environ.get("CANVAS_ARCHIVE", HOME / "projects/kth/canvas-archive"))
SCHOOL = Path(os.environ.get("SCHOOL_DIR", HOME / "projects/kth/school"))
URL = os.environ.get("SCHOOL_URL", "https://school.erikfrankling.duckdns.org")
TZ = ZoneInfo("Europe/Stockholm")


# ---------- HTML -> Markdown (enough for Canvas descriptions) ----------
class MD(HTMLParser):
    BLOCK = {"p", "div", "section", "article", "header", "footer", "blockquote", "table", "tr", "figure"}

    def __init__(self, base):
        super().__init__(convert_charrefs=True)
        self.base, self.out, self.links, self.lists, self.href, self.pre, self.skip = base, [], [], [], [], 0, 0

    def nl(self, n=2):
        cur = "".join(self.out[-3:])
        need = n - (len(cur) - len(cur.rstrip("\n")))
        if self.out and need > 0:
            self.out.append("\n" * need)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in ("script", "style"):
            self.skip += 1
        elif tag in self.BLOCK:
            self.nl()
        elif re.fullmatch(r"h[1-6]", tag):
            self.nl()
            self.out.append("#" * min(6, int(tag[1]) + 2) + " ")
        elif tag == "br":
            self.out.append("  \n")
        elif tag in ("ul", "ol"):
            self.nl(1 if self.lists else 2)
            self.lists.append([tag, 0])
        elif tag == "li":
            self.nl(1)
            lst = self.lists[-1] if self.lists else ["ul", 0]
            lst[1] += 1
            self.out.append("  " * (len(self.lists) - 1) + ("- " if lst[0] == "ul" else f"{lst[1]}. "))
        elif tag in ("strong", "b"):
            self.out.append("**")
        elif tag in ("em", "i"):
            self.out.append("*")
        elif tag == "code" and not self.pre:
            self.out.append("`")
        elif tag == "pre":
            self.nl()
            self.out.append("```\n")
            self.pre += 1
        elif tag in ("td", "th"):
            self.out.append(" | ")
        elif tag == "a":
            href = a.get("href") or ""
            if href and not href.startswith(("#", "javascript:", "mailto:")):
                href = absolute(href, self.base)
                self.href.append(href)
                self.out.append("[")
            else:
                self.href.append(None)
        elif tag == "img" and a.get("alt"):
            self.out.append(f"[image: {a['alt']}]")
        elif tag == "iframe" and a.get("src"):
            src = absolute(a["src"], self.base)
            self.links.append(("Embedded", src))
            self.out.append(f"\n[Embedded content]({src})\n")

    def handle_endtag(self, tag):
        if tag in ("script", "style"):
            self.skip = max(0, self.skip - 1)
        elif tag in self.BLOCK or re.fullmatch(r"h[1-6]", tag):
            self.nl()
        elif tag in ("ul", "ol"):
            if self.lists:
                self.lists.pop()
            self.nl(1 if self.lists else 2)
        elif tag in ("strong", "b"):
            self.out.append("**")
        elif tag in ("em", "i"):
            self.out.append("*")
        elif tag == "code" and not self.pre:
            self.out.append("`")
        elif tag == "pre":
            self.pre = max(0, self.pre - 1)
            self.nl(1)
            self.out.append("```")
            self.nl()
        elif tag == "a" and self.href:
            href = self.href.pop()
            if href:
                i = len(self.out) - 1
                while i >= 0 and self.out[i] != "[":
                    i -= 1
                text = "".join(self.out[i + 1:]).strip() or href
                del self.out[i:]
                text = re.sub(r"\s+", " ", text).replace("[", "(").replace("]", ")")
                self.out.append(f"[{text}]({href})")
                self.links.append((text, href))

    def handle_data(self, data):
        if self.skip:
            return
        self.out.append(data if self.pre else re.sub(r"\s+", " ", data))

    def markdown(self):
        text = "".join(self.out)
        text = re.sub(r"[ \t]+\n", "\n", text)
        text = re.sub(r"\*\*\s*\*\*", "", text)
        text = re.sub(r"\n{3,}", "\n\n", text)
        return text.strip()


def absolute(href, base):
    from urllib.parse import urljoin
    href = urljoin(base, href.strip())
    # API links in Canvas HTML point to the API; the browser wants the page.
    href = re.sub(r"canvas\.kth\.se/api/v1/", "canvas.kth.se/", href)
    return re.sub(r"[?&]wrap=1\b", "", href)


def to_md(h, base):
    if not h:
        return "", []
    p = MD(base)
    p.feed(h)
    p.close()
    return p.markdown(), p.links


def plain(h):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html.unescape(h or ""))).strip()


# ---------- helpers ----------
def iso(s):
    if not s:
        return None
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s):
        return datetime.fromisoformat(s).replace(hour=23, minute=59, tzinfo=TZ).astimezone(timezone.utc).isoformat()
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc).isoformat()


def local(s):
    return datetime.fromisoformat(s).astimezone(TZ) if s else None


def fmt(s):
    d = local(s)
    return d.strftime("%a %-d %b %Y, %H:%M") if d else "no date"


def norm(t):
    t = t.lower()
    t = re.sub(r"\bseminarium\b", "seminar", t)
    t = re.sub(r"^(assignment|exercise|uppgift):\s*", "", t)
    t = re.sub(r"\s*-\s*funka$", "", t)
    return re.sub(r"[^a-z0-9.]+", " ", t).strip()


def key_phrase(title):
    t = re.sub(r"^(Assignment|Exercise):\s*", "", title).strip()
    m = re.match(r"(.+?)\s+\(", t)
    if m and len(m.group(1)) >= 4:
        t = m.group(1)
    return t.strip()


def kind_of(title, fallback="assignment"):
    t = title.lower()
    if re.search(r"registration|register|sign-?up|signup", t):
        return "registration"
    if re.search(r"peer[- ]?review|give feedback|feedback to", t):
        return "peer review"
    if re.search(r"re-?exam|written exam|\bexam\b|tentamen|oral exam|c-exam", t):
        return "exam"
    if re.search(r"extra session|lecture|help session|office hour", t):
        return "event"
    if re.search(r"\bquiz", t):
        return "quiz"
    if re.search(r"\blab\b|laboration|dns lab", t):
        return "lab"
    if re.search(r"seminar", t):
        return "seminar"
    return fallback


def match(rule, course_id, title):
    if rule.get("course") and int(rule["course"]) != course_id:
        return False
    return bool(re.search(rule["title_re"], title, re.I))


# ---------- build ----------
def main():
    arch = json.loads((ARCHIVE / "archive.json").read_text())
    ov = json.loads((SCHOOL / "overrides.json").read_text())
    courses = {int(k): v for k, v in ov["courses"].items()}
    since = iso(ov.get("since", "2026-08-01"))
    by_course = {c["course"]["id"]: c for c in arch["courses"] if c["course"]["id"] in courses}
    items = []

    def new_item(cid, iid, title, kind, due, **kw):
        it = {"id": iid, "course": courses[cid]["code"], "course_name": courses[cid]["name"], "course_id": cid,
              "title": title, "kind": kind, "due": due, "start": None, "all_day": False, "lock_at": None,
              "unlock_at": None, "canvas": None, "auto_done": False, "auto_reason": None, "deferred": None,
              "description": "", "sources": [], "notes": [], "related": [], "facts": []}
        it.update(kw)
        return it

    def src(it, label, url):
        if url and url not in {s["url"] for s in it["sources"]}:
            it["sources"].append({"label": label, "url": url})

    # Module locations of every assignment/quiz/page.
    modules = {}
    for cid, c in by_course.items():
        for m in c.get("modules") or []:
            for i in m.get("items") or []:
                for k in filter(None, [i.get("content_id") and (cid, i["type"], i["content_id"]), i.get("page_url") and (cid, "Page", i["page_url"])]):
                    modules.setdefault(k, []).append((m["name"].strip(), i.get("html_url")))

    # 1. Canvas assignments (quizzes are assignments too).
    for cid, c in by_course.items():
        for a in c.get("assignments") or []:
            s = a.get("submission") or {}
            st = s.get("workflow_state")
            good_grade = st == "graded" and (s.get("score") or 0) > 0 and str(s.get("grade")).lower() not in ("incomplete", "f", "fail", "0")
            done = bool(s.get("submitted_at")) or good_grade or bool(s.get("excused"))
            it = new_item(cid, f"canvas-assignment-{a['id']}", re.sub(r"^Assignment:\s*", "", a["name"]), "quiz" if a.get("quiz_id") else kind_of(a["name"]),
                          iso(a.get("due_at")), lock_at=iso(a.get("lock_at")), unlock_at=iso(a.get("unlock_at")),
                          canvas={"state": st, "submitted_at": s.get("submitted_at"), "grade": s.get("grade"), "score": s.get("score"),
                                  "points": a.get("points_possible"), "missing": s.get("missing"), "late": s.get("late"),
                                  "types": a.get("submission_types") or []},
                          auto_done=done,
                          auto_reason=("submitted in Canvas " + fmt(iso(s["submitted_at"])) if s.get("submitted_at") else
                                       f"graded {s.get('grade')} in Canvas" if good_grade else "excused in Canvas" if s.get("excused") else None))
            md, links = to_md(a.get("description"), a.get("html_url") or "https://canvas.kth.se/")
            it["description"] = md
            src(it, "Canvas assignment", a.get("html_url"))
            for name, url in modules.get((cid, "Quiz" if a.get("quiz_id") else "Assignment", a.get("quiz_id") or a["id"]), []) + modules.get((cid, "Assignment", a["id"]), []):
                src(it, f"Module: {name}", url)
            for text, url in links:
                if "canvas.kth.se" in url or "kth.se" in url:
                    if len(text) < 6 or text.lower() in ("here", "this link", "link") or text.startswith("http"):
                        text = "file" if "/files/" in url else "page" if "/pages/" in url else "discussion" if "/discussion_topics/" in url else url.split("//")[-1][:60]
                    src(it, f"Linked: {text[:80]}", url)
            it["_norm"] = norm(a["name"])
            items.append(it)

    # Funka (accessibility) variants of a quiz are the same task.
    by_norm = {}
    for it in items:
        by_norm.setdefault((it["course_id"], it["_norm"]), []).append(it)
    for group in by_norm.values():
        if len(group) > 1:
            main_it = min(group, key=lambda x: (x["title"].lower().endswith("funka"), len(x["title"])))
            for o in group:
                if o is main_it:
                    continue
                if o["auto_done"] and not main_it["auto_done"]:
                    main_it["auto_done"], main_it["auto_reason"] = True, f"{o['title']}: {o['auto_reason']}"
                for s_ in o["sources"]:
                    src(main_it, f"{o['title']}: {s_['label']}", s_["url"])
                o["_drop"] = True
    items = [i for i in items if not i.get("_drop")]

    # 2. Canvas calendar events, de-duplicated; merged into an assignment when they are its deadline.
    seen = {}
    for cid, c in by_course.items():
        for e in c.get("calendar") or []:
            start = iso(e.get("start_at"))
            k = (cid, norm(e["title"]), start)
            if k in seen:
                src(seen[k], "Canvas calendar event", e.get("html_url"))
                continue
            ekind = kind_of(e["title"], "event")
            host = next((i for i in items if i["course_id"] == cid and i["due"] == start and i["_norm"] and
                         (i["_norm"] in norm(e["title"]) or (i["id"].startswith("canvas-assignment") and i["kind"] == ekind != "event"))), None)
            if host:
                seen[k] = host
                src(host, "Canvas calendar event", e.get("html_url"))
                continue
            end = iso(e.get("end_at"))
            it = new_item(cid, f"canvas-event-{e['id']}", e["title"], ekind, end if end and end != start else start,
                          start=start if end and end != start else None, all_day=bool(e.get("all_day")))
            it["description"], _ = to_md(e.get("description"), "https://canvas.kth.se/")
            if e.get("location_name"):
                it["facts"].append(("Where", e["location_name"] + (f", {e['location_address']}" if e.get("location_address") else "")))
            src(it, "Canvas calendar event", e.get("html_url"))
            it["_norm"] = norm(e["title"])
            seen[k] = it
            items.append(it)

    # 3. Dates found on course pages and KTH pages (deadlines.json), then TimeEdit exams.
    codes = ov["deadlines_course_codes"]
    pages = [d for d in json.loads((ARCHIVE / "deadlines.json").read_text()) if d.get("type") not in ("Assignment", "Calendar event")]
    windows = {}
    for d in pages:
        m = re.match(r"(.*?)\s+(opens|closes)(?:\s*\(.*\))?$", d["title"])
        if d.get("type") == "Registration" and m:
            windows.setdefault((d["course"], m.group(1)), {})[m.group(2)] = d
    for d in pages:
        cid = codes.get(d["course"])
        if cid not in courses or not d.get("due"):
            continue
        title, due = d["title"], iso(d.get("closes") or d["due"]) if d.get("type") != "Seminar" else iso(d["due"])
        m = re.match(r"(.*?)\s+(opens|closes)(?:\s*\(.*\))?$", title)
        start = None
        if d.get("type") == "Registration" and m and (d["course"], m.group(1)) in windows:
            w = windows.pop((d["course"], m.group(1)), None)
            if not w:
                continue
            title = m.group(1)
            if "closes" in w:
                due = iso(w["closes"]["due"])
                start = iso(w["opens"]["due"]) if "opens" in w else None
            else:
                title, due = d["title"], iso(w["opens"]["due"])
        elif d.get("type") == "Registration" and m:
            continue
        title = re.sub(r":\s*closes \d\d:\d\d$", "", title)
        n = norm(title)
        # Already a Canvas item? Fill a missing date or add the page as a source.
        pkind = kind_of(title, {"Seminar": "seminar", "Exam": "exam", "Quiz window": "quiz", "Registration": "registration"}.get(d.get("type"), "assignment"))
        cands = [i for i in items if i["course_id"] == cid and i["_norm"] and n and (i["_norm"] == n or re.match(re.escape(n) + r"\b", i["_norm"]) or re.match(re.escape(i["_norm"]) + r"\b", n))]
        cands = [i for i in cands if not i["due"] or not due or abs(datetime.fromisoformat(i["due"]) - datetime.fromisoformat(due)) <= timedelta(days=1)]
        if not cands and due:  # same kind of task at the same minute: the page restates a Canvas deadline
            cands = [next(i for i in items if i["course_id"] == cid and i["kind"] == pkind and i["due"] == due)] if any(
                i["course_id"] == cid and i["kind"] == pkind and i["due"] == due for i in items) else []
        if cands:
            for i in cands:
                if not i["due"]:
                    i["due"], i["all_day"] = due, bool(re.fullmatch(r"\d{4}-\d{2}-\d{2}", d["due"]))
                src(i, "Course page", d.get("source"))
                if d.get("notes"):
                    i["notes"].append(d["notes"])
            continue
        it = new_item(cid, "page-" + hashlib.sha1(f"{cid}|{title}".encode()).hexdigest()[:12], title,
                      pkind, due, start=start, all_day=bool(re.fullmatch(r"\d{4}-\d{2}-\d{2}", d["due"])))
        if d.get("notes"):
            it["notes"].append(d["notes"])
        src(it, "Course page" if "canvas.kth.se" in (d.get("source") or "") else "TimeEdit" if "timeedit" in (d.get("source") or "") else "KTH page", d.get("source"))
        for name, url in modules.get((cid, "Page", (d.get("source") or "").rstrip("/").split("/")[-1]), []):
            src(it, f"Module: {name}", url)
        it["_norm"] = n
        items.append(it)

    for cid, c in by_course.items():
        folder = next((p for p in ARCHIVE.glob(f"*-{cid}") if p.is_dir()), None)
        sched = folder / "schedule.json" if folder else None
        if not sched or not sched.exists():
            continue
        for e in json.loads(sched.read_text()):
            m = re.match(r"\s*(\d{4}-\d{2}-\d{2}) (\d\d:\d\d) - (\d\d:\d\d) (.*?) ID (\d+)", e.get("when", ""))
            if not m or not re.search(r"exam|tentamen|\bKS\b", m.group(4), re.I):
                continue
            s = datetime.fromisoformat(f"{m.group(1)}T{m.group(2)}").replace(tzinfo=TZ).astimezone(timezone.utc).isoformat()
            en = datetime.fromisoformat(f"{m.group(1)}T{m.group(3)}").replace(tzinfo=TZ).astimezone(timezone.utc).isoformat()
            if any(i["course_id"] == cid and i["kind"] == "exam" and s in (i["due"], i["start"]) for i in items):
                continue
            title = m.group(4).split(",")[0].strip()
            it = new_item(cid, f"timeedit-{m.group(5)}", f"{title} ({m.group(4).split(',', 1)[1].strip()})" if "," in m.group(4) else title,
                          "exam", s, start=None)
            it["facts"].append(("Time", f"{m.group(2)}–{m.group(3)}"))
            src(it, "TimeEdit schedule", next((l.split("Source: ")[1].strip() for l in (folder / "SCHEDULE.md").read_text().splitlines() if l.startswith("Source: ")), None) if (folder / "SCHEDULE.md").exists() else None)
            it["_norm"] = norm(title)
            items.append(it)

    # 4. Curated rules: exclusions, items settled for a later round, notes, extras.
    items = [i for i in items if i["due"] and i["due"] >= since and not any(match(r, i["course_id"], i["title"]) for r in ov.get("exclude", []))]
    for x in ov.get("extra", []):
        cid = int(x["course"])
        it = new_item(cid, x["id"], x["title"], x.get("kind", kind_of(x["title"])), iso(x["due"]), start=iso(x.get("start")))
        it["description"] = x.get("markdown", "")
        for s_ in x.get("sources", []):
            src(it, s_["label"], s_["url"])
        items.append(it)
    for it in items:
        for r in ov.get("deferred", []):
            if match(r, it["course_id"], it["title"]):
                it["deferred"] = {"until": r.get("until"), "note": r.get("markdown", "")}
        for r in ov.get("notes", []):
            if match(r, it["course_id"], it["title"]):
                it["notes"].append(r["markdown"])

    # 5. Announcements that mention the item.
    for it in items:
        c = by_course.get(it["course_id"])
        if not c:
            continue
        phrase = key_phrase(it["title"])
        pats = [re.escape(phrase)]
        m = re.match(r"homework (\d+)", phrase, re.I)
        if m:
            pats.append(rf"\bHW\s?{m.group(1)}\b")
        if len(phrase) < 4 and not m:
            continue
        rx = re.compile(r"(?<![\w])(" + "|".join(pats) + r")(?![\w])", re.I)
        hits = []
        for a in c.get("announcements") or []:
            txt = plain(a.get("message"))
            mm = rx.search(a.get("title", "") + " \n " + txt)
            if mm:
                pos = max(0, txt.lower().find(mm.group(1).lower()) - 120)
                excerpt = ("…" if pos else "") + txt[pos:pos + 360].strip() + ("…" if len(txt) > pos + 360 else "")
                hits.append({"title": a.get("title"), "date": a.get("posted_at"), "url": a.get("html_url"), "excerpt": excerpt})
        hits.sort(key=lambda h: h["date"] or "", reverse=True)
        it["related"] = hits[:5]
        for h in hits[:5]:
            src(it, f"Announcement: {h['title']}", h["url"])

    # 6. The markdown page and a content hash for "changed since".
    for it in items:
        it["markdown"] = page(it)
        it.pop("_norm", None)
        body = {k: it[k] for k in ("title", "due", "start", "lock_at", "markdown", "deferred", "auto_done")}
        it["hash"] = hashlib.sha1(json.dumps(body, sort_keys=True).encode()).hexdigest()[:16]
        for k in ("description", "notes", "related", "facts"):
            it.pop(k, None)
    items.sort(key=lambda i: (i["due"], i["course"], i["title"]))
    out = {"generated_at": datetime.now(timezone.utc).isoformat(), "archive_retrieved_at": arch.get("retrieved_at"), "items": items}
    (SCHOOL / "items.json").write_text(json.dumps(out, ensure_ascii=False, indent=1))
    counts = {}
    for i in items:
        counts[i["course"]] = counts.get(i["course"], 0) + 1
    print(len(items), "items", json.dumps(counts))
    if "--no-push" not in sys.argv:
        push(out)


KIND_WORD = {"assignment": "Assignment", "quiz": "Quiz", "lab": "Lab", "seminar": "Seminar", "exam": "Exam",
             "peer review": "Peer review", "registration": "Registration window", "event": "Event"}


def page(it):
    L = []
    if it["deferred"]:
        L += [f"> {it['deferred']['note']}", ""]
    facts = [("What", f"{KIND_WORD.get(it['kind'], it['kind'].title())} in {it['course']} {it['course_name']}")]
    if it["start"]:
        facts.append(("Opens" if it["kind"] == "registration" else "Starts", fmt(it["start"])))
    facts.append(("Due" if it["kind"] not in ("exam", "seminar", "event") else "When", fmt(it["due"]) + (" (date only)" if it["all_day"] else "")))
    if it["lock_at"] and it["lock_at"] != it["due"]:
        facts.append(("Closes", fmt(it["lock_at"]) + " (late submissions accepted until then)"))
    if it["unlock_at"]:
        facts.append(("Opens", fmt(it["unlock_at"])))
    cv = it["canvas"]
    if cv:
        if cv.get("points"):
            facts.append(("Points", f"{cv['points']:g}"))
        types = [t.replace("_", " ") for t in cv.get("types") or [] if t not in ("none", "not_graded")]
        if types:
            facts.append(("Hand in", ", ".join(types)))
        state = cv.get("state") or "unknown"
        if cv.get("submitted_at"):
            state += f", submitted {fmt(iso(cv['submitted_at']))}"
        if cv.get("grade") is not None:
            state += f", grade {cv['grade']}"
        facts.append(("Canvas status", state))
    facts += it["facts"]
    L += [f"- **{k}:** {v}" for k, v in facts]
    if it["notes"]:
        L += ["", "### Notes", ""] + [f"- {n}" for n in dict.fromkeys(it["notes"])]
    if it["description"]:
        L += ["", "### From Canvas", "", it["description"][:9000] + ("\n\n*(cut; the rest is on the Canvas page)*" if len(it["description"]) > 9000 else "")]
    if it["related"]:
        L += ["", "### Announcements that mention it", ""]
        for h in it["related"]:
            L.append(f"- [{h['title']}]({h['url']}) ({fmt(iso(h['date']))}): {h['excerpt']}")
    L += ["", "### Sources", ""] + [f"- [{s['label']}]({s['url']})" for s in it["sources"]]
    return "\n".join(L).strip()


def push(out):
    token = os.environ.get("SCHOOL_INGEST_TOKEN")
    if not token:
        tf = os.environ.get("SCHOOL_INGEST_TOKEN_FILE")
        token = Path(tf).read_text().strip() if tf else None
    if not token:
        sys.exit("no SCHOOL_INGEST_TOKEN(_FILE); wrote items.json only")
    req = urllib.request.Request(URL + "/api/ingest", data=json.dumps(out).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        print("pushed:", r.status, r.read().decode()[:300])


if __name__ == "__main__":
    main()

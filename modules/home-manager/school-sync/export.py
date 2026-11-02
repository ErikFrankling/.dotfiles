"""Build the school calendar's item list from the local Canvas archive and push it
to https://school.erikfrankling.duckdns.org (homelab apps/school.yaml).

Reads only local files: archive.json (Canvas API data from refresh.py),
deadlines.json (dates transcribed from course pages), each course's
schedule.json (TimeEdit) and the curated ~/projects/kth/school/overrides.json.
Never talks to Canvas, so it cannot change anything there.

Every date says where it came from (opens_source, due_source): "canvas", "course
page", "announcement", "schedule" or "inferred". A window with no stated opening
gets opens = null and is listed in no_opening; dates are never made up.

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
TERM_YEAR = datetime.now(TZ).year if datetime.now(TZ).month >= 8 else datetime.now(TZ).year - 1  # Aug-Jul


def dayKeyOf(s):
    return datetime.fromisoformat(s).astimezone(TZ).date().isoformat()


# ---------- HTML -> Markdown (enough for Canvas descriptions) ----------
class MD(HTMLParser):
    BLOCK = {"p", "div", "section", "article", "header", "footer", "blockquote", "table", "tr", "figure"}

    def __init__(self, base):
        super().__init__(convert_charrefs=True)
        self.base, self.out, self.links, self.lists, self.href, self.pre, self.skip = base, [], [], [], [], 0, 0
        self.titles = {}

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
            self.out.append("\u2028")  # becomes a markdown hard break after whitespace cleanup
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
                self.titles[href] = a.get("title") or ""
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
        elif tag in ("strong", "b", "em", "i"):
            if self.out:
                self.out[-1] = self.out[-1].rstrip(" ")  # "**x **" is not bold in markdown
            self.out.append("**" if tag in ("strong", "b") else "*")
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
                text = "".join(self.out[i + 1:]).strip()
                del self.out[i:]
                if not text:  # an icon-only link: keep it as a source, not as a bare URL in the text
                    self.links.append((self.titles.get(href) or href.rsplit("/", 1)[-1][:60], href))
                    return
                text = re.sub(r"\s+", " ", text).replace("[", "(").replace("]", ")")
                self.out.append(f"[{text}]({href})")
                # Canvas file links carry the file name in title; "here" is not a label.
                self.links.append((self.titles.get(href) if len(text) < 6 or text.lower() in ("here", "this link", "link") else text, href) if self.titles.get(href) else (text, href))

    def handle_data(self, data):
        if self.skip:
            return
        self.out.append(data if self.pre else re.sub(r"\s+", " ", data))

    def markdown(self):
        text = "".join(self.out)
        text = re.sub(r"[ \t]+\n", "\n", text)
        text = re.sub(r"\*\*[ \t]*\*\*(?=[ \t]*(\n|$))|(?<=\n)[ \t]*\*\*[ \t]*\*\*", "", text)  # empty bold only
        text = re.sub(r"\n{3,}", "\n\n", text)
        text = re.sub(r"[ \t]*\u2028[ \t]*", "  \n", text)
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
        return "action"
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


# ---------- dates written in course pages and announcements ----------
MONTHS = {m: i + 1 for i, m in enumerate("jan feb mar apr may jun jul aug sep oct nov dec".split())}
DATE = (r"(?:(mon|tue|wed|thu|fri|sat|sun)[a-z]*\.?,?\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+"
        r"(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?(?:,?\s+(20\d\d))?"
        r"(?:(?:,?\s*(?:at\s+)?)(\d{1,2})[:.](\d\d))?")
DATE_US = r"(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b"


def page_lines(h):
    """Plain text lines of a Canvas page: inline tags vanish without a gap, blocks break."""
    h = re.sub(r"(?i)</(tr|p|li|h\d|div|td|ul|ol)>|<br\s*/?>", "\n", h or "")
    text = html.unescape(re.sub(r"<[^>]+>", "", h)).replace("\xa0", " ")
    return [l for l in (re.sub(r"[ \t]+", " ", x).strip() for x in text.split("\n")) if l]


def implied_year(mo, day, ref):
    """A date without a year is the next one after ref (when it was written), or this academic year."""
    if not ref:
        return TERM_YEAR if mo >= 8 else TERM_YEAR + 1
    return ref.year + (1 if (mo, day) < (ref.month, ref.day) and ref.month - mo > 3 else 0)


def when(m, ref=None):
    """A DATE match as a Stockholm datetime and whether it had a time. A weekday that
    disagrees means we misread it, so it gives None."""
    wd, day, mon, year, hh, mm = m.groups()[:6]
    mo = MONTHS[mon.lower()]
    y = int(year) if year else implied_year(mo, int(day), ref)
    try:
        d = datetime(y, mo, int(day), int(hh or 0), int(mm or 0), tzinfo=TZ)
    except ValueError:
        return None, False
    if wd and d.strftime("%a").lower() != wd.lower():
        print(f"weekday mismatch, ignored: {m.group(0)}")
        return None, False
    return d, hh is not None


def utc(d):
    return d.astimezone(timezone.utc).isoformat()


def key(t):
    return re.sub(r"[^a-z0-9]", "", t.lower())


def set_opens(it, dt, all_day, source, url):
    """Canvas's own unlock date is the truth; anything else only fills a gap."""
    if it.get("opens_source") == "canvas" or not dt or dt >= it["due"]:
        return
    it.update(opens=dt, opens_source=source, opens_url=url, opens_all_day=all_day)


def page_sources(c):
    """(slug, url, lines) for a course's pages and syllabus."""
    base = f"https://canvas.kth.se/courses/{c['course']['id']}"
    for p in c.get("pages") or []:
        yield p.get("url"), f"{base}/pages/{p.get('url')}", page_lines((p.get("detail") or p).get("body"))
    if c["course"].get("syllabus_body"):
        yield "syllabus", f"{base}/assignments/syllabus", page_lines(c["course"]["syllabus_body"])


def read_pages(items, by_course, rules):
    """Live dates from course pages: release and due tables, quiz windows and curated lines.
    Read on every run, so an edit to the page reaches the calendar the next morning."""
    release = re.compile(DATE + r"\s*(release|due)\s*:\s*(.+)", re.I)
    quiz = re.compile(DATE + r"\s*-\s*(quiz \d+),\s*open from (\d{1,2})\s*am", re.I)
    for cid, c in by_course.items():
        mine = [i for i in items if i["course_id"] == cid]
        find = lambda thing: [i for i in mine if key(i["title"]).startswith(key(thing))]
        for slug, url, lines in page_sources(c):
            for line in lines:
                if m := release.search(line):
                    d, timed = when(m)
                    field, thing = m.group(7).lower(), m.group(8)
                    hits = find(thing)
                    if not d or not hits:
                        if d and field == "release":
                            print(f"release line matches no item: {cid} {line[:80]}")
                        continue
                    for i in hits:
                        if field == "release":
                            set_opens(i, utc(d), not timed, "course page", url)
                        elif i["due_source"] == "course page" and timed and i["due"] != utc(d):
                            print(f"due moved on the page: {i['title']} {i['due']} -> {utc(d)}")
                            i["due"] = utc(d)
                if m := quiz.search(line):
                    d, _ = when(m)
                    if d:
                        for i in find(m.group(7)):
                            set_opens(i, utc(d.replace(hour=int(m.group(8)))), False, "course page", url)
                for r in rules:
                    if int(r["course"]) == cid and slug == r["page"] and re.search(r["line_re"], line, re.I) and (m := re.search(DATE, line, re.I)):
                        d, timed = when(m)
                        if d:
                            for i in mine:
                                if re.search(r["items_re"], i["title"], re.I):
                                    set_opens(i, utc(d), not timed, "course page", url)


ACT = re.compile(r"\b(sign(?:ing)? up|sign-up|signup|register|registration|apply|applications?|enrol|book|fill in|submit your)\b", re.I)
BY = re.compile(r"\b(by|before|until|deadline|closes?|latest)\b", re.I)
SPAN = re.compile(r"\bopen\s+(\d{1,2})\s*[-–]\s*(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*(?:\s+(20\d\d))?", re.I)


def sentence_dates(sentence, ref):
    """Every date in a sentence, in order, in either "12 November" or "November 12" form."""
    out = []
    for m in re.finditer(DATE, sentence, re.I):
        d, timed = when(m, ref)
        if d:
            out.append((m.start(), d, timed))
    for m in re.finditer(DATE_US, sentence, re.I):
        if not any(abs(m.start() - p) < 12 for p, _, _ in out):
            try:
                mo = MONTHS[m.group(1).lower()]
                out.append((m.start(), datetime(implied_year(mo, int(m.group(2)), ref), mo, int(m.group(2)), tzinfo=TZ), False))
            except ValueError:
                pass
    return [(d, t) for _, d, t in sorted(out, key=lambda x: x[0])]


def read_announcements(c, cutoff):
    """Things to do stated in announcements: (announcement, sentence, opens, closes, timed)."""
    for a in c.get("announcements") or []:
        if not a.get("posted_at"):  # not published yet
            continue
        posted = datetime.fromisoformat(a["posted_at"].replace("Z", "+00:00")).astimezone(TZ)
        for line in page_lines(a.get("message")):
            for sentence in re.split(r"(?<=[.!?])\s+", line):
                if m := SPAN.search(sentence):
                    mo = MONTHS[m.group(3).lower()]
                    y = int(m.group(4) or implied_year(mo, int(m.group(1)), posted))
                    start = datetime(y, mo, int(m.group(1)), tzinfo=TZ)
                    end = datetime(y, mo, int(m.group(2)), 23, 59, tzinfo=TZ)
                    if end >= cutoff:
                        yield a, sentence, start, end, False
                    continue
                if not ACT.search(sentence):
                    continue
                dates = sentence_dates(sentence, posted)
                if not dates:
                    continue
                opener = re.search(r"\bopens?\b", sentence, re.I)
                closer = re.search(r"\bcloses?\b", sentence, re.I)
                if opener and closer and len(dates) >= 2:
                    (o, _), (e, t) = dates[0], dates[1]
                elif BY.search(sentence):
                    (e, t), o = dates[-1], None
                else:
                    continue
                e = e if t else e.replace(hour=23, minute=59)
                if e >= cutoff and e.isoformat()[:10] >= a.get("posted_at", "")[:10]:
                    yield a, sentence, o, e, t


# ---------- build ----------
def main():
    arch = json.loads((ARCHIVE / "archive.json").read_text())
    ov = json.loads((SCHOOL / "overrides.json").read_text())
    courses = {int(k): v for k, v in ov["courses"].items()}
    # refresh.py archives every course of the current term, so a new course needs no list
    # here; overrides only rename rooms that hold several course codes.
    for c in arch["courses"]:
        cid, name = c["course"]["id"], c["course"]["name"]
        if cid not in courses:
            code, _, rest = name.partition(" ")
            title = re.sub(r"\s*\([^)]*\)\s*$", "", re.sub(r"^(HT|VT)\d\d\s+", "", rest)).strip()
            courses[cid] = {"code": code.split("/")[0], "name": title or name}
            print(f"course without overrides: {code} {title}")
    since = iso(ov.get("since", "2026-08-01"))
    by_course = {c["course"]["id"]: c for c in arch["courses"]}
    cutoff = datetime.now(TZ) - timedelta(days=14)
    items = []

    def new_item(cid, iid, title, kind, due, **kw):
        it = {"id": iid, "course": courses[cid]["code"], "course_name": courses[cid]["name"], "course_id": cid,
              "title": title, "kind": kind, "due": due, "due_source": "canvas", "start": None, "all_day": False, "lock_at": None,
              "opens": None, "opens_source": None, "opens_url": None, "opens_all_day": False, "opens_group": None,
              "origin": "export", "canvas": None, "auto_done": False, "auto_reason": None, "deferred": None,
              "description": "", "sources": [], "notes": [], "related": [], "facts": []}
        it.update(kw)
        return it

    def same(u):  # one Canvas file, however it is linked
        m = re.search(r"canvas\.kth\.se/(?:courses/\d+/)?files/(\d+)", u or "")
        return ("file", m.group(1)) if m else u

    def src(it, label, url):
        if url and same(url) not in {same(s["url"]) for s in it["sources"]}:
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
                          iso(a.get("due_at")), lock_at=iso(a.get("lock_at")),
                          opens=iso(a.get("unlock_at")), opens_source="canvas" if a.get("unlock_at") else None,
                          opens_url=a.get("html_url") if a.get("unlock_at") else None,
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
            it["_group"] = a.get("group_category_id")
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
        origin = "schedule" if "timeedit" in (d.get("source") or "") else "course page"
        m = re.match(r"(.*?)\s+(opens|closes)(?:\s*\(.*\))?$", title)
        start = None
        if d.get("type") == "Registration" and m and (d["course"], m.group(1)) in windows:
            w = windows.pop((d["course"], m.group(1)), None)
            if not w:
                continue
            title = m.group(1)
            if "closes" in w:
                due = iso(w["closes"]["due"])
                start = utc(datetime.fromisoformat(w["opens"]["due"]).replace(tzinfo=TZ)) if "opens" in w else None
            else:
                title, due = d["title"], iso(w["opens"]["due"])
        elif d.get("type") == "Registration" and m:
            continue
        title = re.sub(r":\s*closes \d\d:\d\d$", "", title)
        n = norm(title)
        # Already a Canvas item? Fill a missing date or add the page as a source.
        pkind = kind_of(title, {"Seminar": "seminar", "Exam": "exam", "Quiz window": "quiz", "Registration": "action"}.get(d.get("type"), "assignment"))
        cands = [i for i in items if i["course_id"] == cid and i["_norm"] and n and (i["_norm"] == n or re.match(re.escape(n) + r"\b", i["_norm"]) or re.match(re.escape(i["_norm"]) + r"\b", n))]
        cands = [i for i in cands if not i["due"] or not due or abs(datetime.fromisoformat(i["due"]) - datetime.fromisoformat(due)) <= timedelta(days=1)]
        if not cands and due:  # same kind of task at the same minute: the page restates a Canvas deadline
            cands = [next(i for i in items if i["course_id"] == cid and i["kind"] == pkind and i["due"] == due)] if any(
                i["course_id"] == cid and i["kind"] == pkind and i["due"] == due for i in items) else []
        if cands:
            for i in cands:
                if not i["due"]:
                    i["due"], i["due_source"], i["all_day"] = due, origin, bool(re.fullmatch(r"\d{4}-\d{2}-\d{2}", d["due"]))
                src(i, "Course page", d.get("source"))
                if d.get("notes") and not (i["canvas"] and "may not yet have a Canvas" in d["notes"]):
                    i["notes"].append(d["notes"])
            continue
        it = new_item(cid, "page-" + hashlib.sha1(f"{cid}|{title}".encode()).hexdigest()[:12], title,
                      pkind, due, due_source=origin, all_day=bool(re.fullmatch(r"\d{4}-\d{2}-\d{2}", d["due"])))
        if start:
            it.update(opens=start, opens_source=origin, opens_url=d.get("source"), opens_all_day=True)
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
                          "exam", s, due_source="schedule", start=None)
            it["facts"].append(("Time", f"{m.group(2)}–{m.group(3)}"))
            src(it, "TimeEdit schedule", next((l.split("Source: ")[1].strip() for l in (folder / "SCHEDULE.md").read_text().splitlines() if l.startswith("Source: ")), None) if (folder / "SCHEDULE.md").exists() else None)
            it["_norm"] = norm(title)
            items.append(it)

    # 4. Curated rules: exclusions, items settled for a later round, notes, extras.
    items = [i for i in items if i["due"] and i["due"] >= since and not any(match(r, i["course_id"], i["title"]) for r in ov.get("exclude", []))]
    read_pages(items, by_course, ov.get("page_rules", []))

    # 5. Things to do that are not Canvas assignments.
    # Stated in an announcement; a date that is already an action just gains the source.
    for cid, c in by_course.items():
        for a, sentence, o, e, timed in read_announcements(c, cutoff):
            due, url = utc(e), a.get("html_url")
            host = next((i for i in items if i["course_id"] == cid and i["kind"] == "action" and dayKeyOf(i["due"]) == dayKeyOf(due)), None)
            if not host:
                host = new_item(cid, "ann-" + hashlib.sha1(f"{cid}|{a['id']}|{due[:10]}".encode()).hexdigest()[:12], a["title"].strip(), "action", due,
                                due_source="announcement", all_day=not timed)
                host["_norm"] = norm(a["title"])
                items.append(host)
            src(host, f"Announcement: {a['title']}", url)
            host["notes"].append(sentence)
            if o and not host["opens"]:
                set_opens(host, utc(o), True, "announcement", url)
    # An assignment that needs a group: joining it has no deadline of its own, so the
    # assignment's own dates are the inferred window, and Canvas tells if it is done.
    for it in [i for i in items if i["canvas"] and i.get("_group") and i["due"] >= utc(cutoff)]:
        cid, word = it["course_id"], it["title"].split()[0].lower()
        joined = next((g for g in arch.get("my_groups") or [] if g.get("course_id") == cid and
                       (g.get("group_category_id") == it["_group"] or word in g["name"].lower())), None)
        act = new_item(cid, f"join-{it['id']}", f"Join a group: {it['title']}", "action", it["due"], due_source="inferred",
                       auto_done=bool(joined), auto_reason=f"member of {joined['name']} in Canvas" if joined else None)
        act["notes"].append("Canvas gives no separate group deadline; this has to happen before the assignment is due.")
        set_opens(act, it["opens"], False, "inferred", it["opens_url"])
        src(act, "Assignment in Canvas", next((s_["url"] for s_ in it["sources"]), None))
        act["_norm"] = key(act["title"])
        items.append(act)
    # Canvas slots that must be booked; the last slot is the last chance, not a stated deadline.
    slots = {}
    for g in arch.get("appointment_groups") or []:
        cid = next((int(x.split("_")[1]) for x in g.get("context_codes") or [] if x.startswith("course_")), None)
        if cid in by_course and re.search(ov.get("book_slots_re", "$^"), g["title"], re.I) and g.get("start_at"):
            slots.setdefault((cid, re.sub(r"\s*\(Option \d+\)", "", g["title"]).strip()), []).append(g)
    for (cid, title), gs in slots.items():
        last, booked = max(g["start_at"] for g in gs), not any(g.get("requiring_action") for g in gs)
        act = new_item(cid, "book-" + hashlib.sha1(f"{cid}|{title}".encode()).hexdigest()[:12], f"Book a slot: {title}", "action", iso(last),
                       due_source="inferred", auto_done=booked, auto_reason="slot booked in Canvas" if booked else None)
        act["notes"].append(f"{len(gs)} slots in Canvas. The date is the last slot, so book before they fill up.")
        src(act, "Sign up in Canvas", gs[0].get("html_url"))
        act["_norm"] = key(title)
        items.append(act)
    # Levels of one task open together: the calendar shows one opening.
    for it in items:
        if it["opens"]:
            it["opens_group"] = re.sub(r"(\s*-\s*[A-F] level|\.[A-F])$", "", it["title"])

    items = [i for i in items if i["due"] >= since and not any(match(r, i["course_id"], i["title"]) for r in ov.get("exclude", []))]
    for it in items:
        for r in ov.get("deferred", []):
            if match(r, it["course_id"], it["title"]):
                it["deferred"] = {"until": r.get("until"), "note": r.get("markdown", "")}
        for r in ov.get("notes", []):
            if match(r, it["course_id"], it["title"]):
                it["notes"].append(r["markdown"])

    # 6. Announcements that mention the item.
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
                if pos:  # start at a word, not mid-word
                    pos = txt.find(" ", pos) + 1 or pos
                excerpt = ("…" if pos else "") + txt[pos:pos + 360].strip() + ("…" if len(txt) > pos + 360 else "")
                hits.append({"title": a.get("title"), "date": a.get("posted_at"), "url": a.get("html_url"), "excerpt": excerpt})
        hits.sort(key=lambda h: h["date"] or "", reverse=True)
        it["related"] = hits[:5]
        for h in hits[:5]:
            src(it, f"Announcement: {h['title']}", h["url"])

    # 7. The markdown page and a content hash for "changed since".
    for it in items:
        it["markdown"] = page(it)
        it["detail"] = detail_of(it)
        it.pop("_norm", None)
        it.pop("_group", None)
        body = {k: it[k] for k in ("title", "due", "opens", "start", "lock_at", "markdown", "deferred", "auto_done")}
        it["hash"] = hashlib.sha1(json.dumps(body, sort_keys=True).encode()).hexdigest()[:16]
        for k in ("description", "notes", "related", "facts"):
            it.pop(k, None)
    items.sort(key=lambda i: (i["due"], i["course"], i["title"]))
    now = utc(datetime.now(TZ))
    no_opening = [{"course": i["course"], "title": i["title"], "kind": i["kind"], "due": i["due"], "id": i["id"]} for i in items
                  if not i["opens"] and i["due"] > now and not i["auto_done"] and not i["deferred"] and i["kind"] not in ("exam", "seminar", "event")]
    out = {"generated_at": datetime.now(timezone.utc).isoformat(), "archive_retrieved_at": arch.get("retrieved_at"), "items": items, "no_opening": no_opening}
    (SCHOOL / "items.json").write_text(json.dumps(out, ensure_ascii=False, indent=1))
    counts = {}
    for i in items:
        counts[i["course"]] = counts.get(i["course"], 0) + 1
    print(len(items), "items", json.dumps(counts))
    opening = {}
    for key_ in {(i["course"], i["opens"], i["opens_group"]) for i in items if i["opens"]}:
        opening[key_[0]] = opening.get(key_[0], 0) + 1
    print("opening events", json.dumps(opening), "| open items with no known opening:", len(no_opening))
    if "--no-push" not in sys.argv:
        push(out)


KIND_WORD = {"assignment": "Assignment", "quiz": "Quiz", "lab": "Lab", "seminar": "Seminar", "exam": "Exam",
             "peer review": "Peer review", "action": "To do", "event": "Event"}


def page(it):
    L = []
    if it["deferred"]:
        L += [f"> {it['deferred']['note']}", ""]
    facts = facts_of(it)
    L += [f"- **{k}:** {v}" for k, v in facts]
    if it["notes"]:
        L += ["", "### Notes", ""] + [f"- {n}" for n in dict.fromkeys(it["notes"])]
    if it["description"]:
        L += ["", "### From Canvas", "", body_of(it)]
    if it["related"]:
        L += ["", "### Announcements that mention it", ""]
        for h in it["related"]:
            L.append(f"- [{h['title']}]({h['url']}) ({fmt(iso(h['date']))}): {h['excerpt']}")
    L += ["", "### Sources", ""] + [f"- [{s['label']}]({s['url']})" for s in it["sources"]]
    return "\n".join(L).strip()


def body_of(it):
    d = it["description"]
    return d[:9000] + ("\n\n*(cut; the rest is on the Canvas page)*" if len(d) > 9000 else "")


def detail_of(it):
    """The same content as page(), structured, so the web page can lay it out."""
    return {"facts": [[k, v] for k, v in facts_of(it) if k not in ("What", "Due", "When", "Opens")],
            "notes": list(dict.fromkeys(it["notes"])), "body": body_of(it) if it["description"] else "",
            "related": it["related"]}


def facts_of(it):
    facts = [("What", f"{KIND_WORD.get(it['kind'], it['kind'].title())} in {it['course']} {it['course_name']}")]
    if it["opens"]:
        tag = "" if it["opens_source"] == "canvas" else f" (per {it['opens_source']}, not a Canvas date)"
        facts.append(("Opens", (fmt(it["opens"]).rsplit(",", 1)[0] if it["opens_all_day"] else fmt(it["opens"])) + tag))
    if it["start"]:
        facts.append(("Starts", fmt(it["start"])))
    facts.append(("Due" if it["kind"] not in ("exam", "seminar", "event") else "When", fmt(it["due"]) + (" (date only)" if it["all_day"] else "")))
    if it["lock_at"] and it["lock_at"] != it["due"]:
        facts.append(("Closes", fmt(it["lock_at"]) + " (late submissions accepted until then)"))
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
    return facts


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

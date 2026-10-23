import datetime as dt
import json
import os
import tempfile
import time
import unittest
from pathlib import Path

# Local time = Stockholm, as on Erik's machines (the build sandbox has no tzdata).
os.environ["TZ"] = "CET-1CEST,M3.5.0,M10.5.0/3"
time.tzset()

import calendar_next as cn  # noqa: E402

CEST = dt.timezone(dt.timedelta(hours=2))
NOW = dt.datetime(2026, 10, 23, 12, 52, tzinfo=CEST)

ICS = "\r\n".join([
    "BEGIN:VCALENDAR",
    "BEGIN:VEVENT", "UID:a", "DTSTART:20261023T080000Z", "DTEND:20261023T090000Z",
    "SUMMARY:Lab extra session [IK2218/EP2120 HT26]", "LOCATION:Room 1\\, Kista", "END:VEVENT",
    "BEGIN:VEVENT", "UID:b", "DTSTART:20261023T170000Z", "DTEND:20261023T170000Z",
    "SUMMARY:Homework 5", "  [IK2218]", "END:VEVENT",
    "BEGIN:VEVENT", "UID:c", "DTSTART;VALUE=DATE:20261024", "SUMMARY:Holiday", "END:VEVENT",
    "END:VCALENDAR", ""])


def ev(title, start, minutes=60, source="google", **kw):
    s = dt.datetime.fromisoformat(start).replace(tzinfo=CEST)
    return cn.make_event(source, title, s, s + dt.timedelta(minutes=minutes), **kw)


class Parsing(unittest.TestCase):
    def test_canvas_timed_vs_due(self):
        timed, due = cn.canvas_events(ICS)
        self.assertEqual([e["title"] for e in timed], ["Lab extra session [IK2218/EP2120 HT26]"])
        self.assertEqual(timed[0]["where"], "Room 1, Kista")
        self.assertEqual(timed[0]["start"], dt.datetime(2026, 10, 23, 8, 0, tzinfo=dt.timezone.utc))
        self.assertEqual(sorted(e["title"] for e in due), ["Holiday", "Homework 5 [IK2218]"])

    def test_google_events_skip_declined_and_name_guests(self):
        value = {"events": [
            {"title": "Husk", "start": "2026-10-23T13:00:00+02:00", "end": "2026-10-23T14:00:00+02:00",
             "meetLink": "https://meet.google.com/x", "link": None, "where": None, "myResponse": "accepted",
             "attendees": [{"name": None, "email": "ef@x", "response": "accepted"},
                           {"name": "Patrik Tang", "email": "p@x", "response": "accepted"}]},
            {"title": "No", "start": "2026-10-23T15:00:00+02:00", "end": "2026-10-23T16:00:00+02:00",
             "myResponse": "declined", "attendees": []}]}
        out = cn.google_events(value)
        self.assertEqual([e["title"] for e in out], ["Husk"])
        self.assertEqual(out[0]["attendees"], ["ef@x", "Patrik Tang"])
        self.assertEqual(out[0]["meet"], "https://meet.google.com/x")


class Render(unittest.TestCase):
    def test_block(self):
        timed = [ev("Elias Agardh / Husk", "2026-10-23T13:00", meet="https://meet.google.com/x",
                    attendees=["Patrik Tang"]),
                 ev("Far", "2026-10-30T13:00")]
        text = cn.render(timed, [], ["google unavailable: x"], NOW, 24)
        self.assertIn("Calendar, next 24h (now Fri 23 Oct 12:52):", text)
        self.assertIn("Fri 23 Oct\n  13:00-14:00 Elias Agardh / Husk | https://meet.google.com/x | with Patrik Tang", text)
        self.assertNotIn("Far", text)
        self.assertIn("(google unavailable: x)", text)

    def test_empty(self):
        self.assertIn("nothing scheduled", cn.render([], [], [], NOW, 24))

    def test_in_progress_marked_and_past_hidden(self):
        timed = [ev("Now", "2026-10-23T12:30"), ev("Past", "2026-10-23T10:00")]
        text = cn.render(timed, [], [], NOW, 24)
        self.assertIn("12:30-13:30 (now) Now", text)
        self.assertNotIn("Past", text)

    def test_due_line_strips_course_tag(self):
        _, due = cn.canvas_events(ICS)
        late = dt.datetime(2026, 10, 23, 12, 0, tzinfo=dt.timezone.utc)
        self.assertIn("Due (Canvas): 19:00 Homework 5", cn.render([], due, [], late, 24))


class Reminders(unittest.TestCase):
    def test_window(self):
        e = ev("Husk", "2026-10-23T13:00")
        soon = NOW + dt.timedelta(minutes=7)  # 12:59
        self.assertEqual(cn.reminders_due([e], NOW - dt.timedelta(minutes=2), {}), [e])  # 12:50 = 10 min
        self.assertEqual(cn.reminders_due([e], soon, {}), [e])
        self.assertEqual(cn.reminders_due([e], NOW - dt.timedelta(minutes=30), {}), [])
        self.assertEqual(cn.reminders_due([e], e["start"], {}), [])  # already started
        self.assertEqual(cn.reminders_due([e], NOW, {e["uid"] + "|" + e["start"].isoformat(): "x"}), [])

    def test_all_day_never_reminded(self):
        e = ev("Holiday", "2026-10-23T13:00", all_day=True)
        self.assertEqual(cn.reminders_due([e], NOW, {}), [])

    def test_text(self):
        e = ev("Lab [IK2218 HT26]", "2026-10-23T13:00")
        self.assertEqual(cn.spoken_text(e, dt.datetime(2026, 10, 23, 12, 50, tzinfo=CEST)), "Lab in ten minutes")
        self.assertEqual(cn.spoken_text(e, dt.datetime(2026, 10, 23, 12, 55, tzinfo=CEST)), "Lab in 5 minutes")

    def test_remind_cli_with_fixture(self):
        with tempfile.TemporaryDirectory() as d:
            cn.STATE_DIR = Path(d)
            fx = Path(d) / "fx.json"
            fx.write_text(json.dumps([{"title": "Test meeting", "start": "2026-10-23T13:00:00+02:00",
                                       "end": "2026-10-23T14:00:00+02:00"}]))
            argv = ["remind", "--fixture", str(fx), "--speak-cmd", "true", "--now", "2026-10-23T12:50:00+02:00"]
            self.assertEqual(cn.main(argv), 0)
            self.assertIn("said 'Test meeting in ten minutes'", (Path(d) / "reminders.log").read_text())
            cn.main(argv)  # second run: already reminded
            self.assertEqual((Path(d) / "reminders.log").read_text().count("REMIND "), 1)


class Queue(unittest.TestCase):
    def test_add_queue_needs_asked_and_dedupes(self):
        with tempfile.TemporaryDirectory() as d:
            cn.STATE_DIR = Path(d)
            self.assertEqual(cn.main(["add", "--title", "T", "--start", "2026-11-05T15:30", "--end", "2026-11-05T17:00"]), 2)
            argv = ["add", "--queue", "--title", "T", "--start", "2026-11-05T15:30", "--end", "2026-11-05T17:00",
                    "--location", "L", "--asked", "put it in my calendar"]
            cn.main(argv)
            cn.main(argv)
            queued = json.loads((Path(d) / "pending-add.json").read_text())
            self.assertEqual(len(queued), 1)
            self.assertEqual(queued[0]["erikAsked"], "put it in my calendar")
            self.assertNotIn("attendees", queued[0])

if __name__ == "__main__":
    unittest.main()

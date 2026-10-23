import datetime as dt
import tempfile
import unittest
from pathlib import Path

import todo_nudge as tn

NOW = dt.datetime(2026, 10, 23, 12, 0, tzinfo=dt.timezone.utc)


def iso(minutes_ago):
    return (NOW - dt.timedelta(minutes=minutes_ago)).isoformat()


FIXTURES = {
    "a-actionable.md": "---\ntitle: A\nstatus: actionable\n---\nbody\n",
    "b-blocked.md": "---\ntitle: B\nstatus: blocked\nblocked_on: erik\n---\n",
    "c-blocked-past.md": "---\nstatus: blocked\nblocked_on: time\nblocked_until: 2026-10-23T06:00:00+02:00\n---\n",
    "d-blocked-future.md": "---\nstatus: blocked\nblocked_on: time\nblocked_until: 2026-10-24T06:00:00+02:00\n---\n",
    "e-flight-running.md": "---\nstatus: in_flight\nowner: mcp:run\n---\n",
    "f-flight-done.md": "---\nstatus: in_flight\nowner: mcp:done\n---\n",
    "g-flight-asking.md": "---\nstatus: in_flight\nowner: mcp:ask\n---\n",
    "h-flight-gone.md": "---\nstatus: in_flight\nowner: mcp:gone\n---\n",
    "i-standing.md": "---\nstatus: standing\n---\n",
    "j-done.md": "---\nstatus: done\n---\n",
    "k-no-front-matter.md": "just text\n",
    "l-bad-yaml.md": "---\ntitle: [oops\n---\n",
    "o-colon-title.md": "---\ntitle: Boxers: pick and buy\nstatus: actionable   # note\n---\n",
    "m-unknown-status.md": "---\nstatus: maybe\n---\n",
    "n-bad-until.md": "---\nstatus: blocked\nblocked_until: soon\n---\n",
    "README.md": "# not an item\n",
}

OWNERS = {
    "mcp:run": {"status": "running", "pendingRequestCount": 0},
    "mcp:done": {"status": "completed", "pendingRequestCount": 0},
    "mcp:ask": {"status": "running", "pendingRequestCount": 1},
}


class Items(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = Path(self.tmp.name)
        for name, text in FIXTURES.items():
            (d / name).write_text(text)
        (d / "done").mkdir()
        (d / "done" / "z-finished.md").write_text("---\nstatus: actionable\n---\n")
        self.dir = d

    def tearDown(self):
        self.tmp.cleanup()

    def test_each_status(self):
        items, errors = tn.read_items(self.dir)
        actionable, item_errors = tn.actionable_items(items, NOW, OWNERS.get)
        self.assertEqual(
            actionable,
            ["a-actionable", "c-blocked-past", "f-flight-done", "g-flight-asking", "h-flight-gone",
             "o-colon-title"],
        )
        self.assertEqual(sorted(s for s, _ in errors), ["k-no-front-matter", "l-bad-yaml"])
        self.assertEqual(sorted(s for s, _ in item_errors), ["m-unknown-status", "n-bad-until"])

    def test_done_folder_and_readme_ignored(self):
        items, _ = tn.read_items(self.dir)
        slugs = [s for s, _ in items]
        self.assertNotIn("z-finished", slugs)
        self.assertNotIn("README", slugs)

    def test_fingerprint_tracks_edits(self):
        before = tn.fingerprint(self.dir)
        (self.dir / "b-blocked.md").write_text("---\nstatus: actionable\n---\n")
        self.assertNotEqual(before, tn.fingerprint(self.dir))
        after = tn.fingerprint(self.dir)
        (self.dir / "README.md").write_text("changed")
        self.assertEqual(after, tn.fingerprint(self.dir))

    def test_in_flight_without_owner_is_actionable(self):
        items = [("x", {"status": "in_flight"})]
        actionable, errors = tn.actionable_items(items, NOW, OWNERS.get)
        self.assertEqual(actionable, ["x"])
        self.assertEqual(len(errors), 1)


class AgentIdle(unittest.TestCase):
    def thread(self, **kw):
        t = {"status": "completed", "activeRunId": None, "pendingRequestCount": 0,
             "usageLimit": None, "updatedAt": iso(5)}
        t.update(kw)
        return t

    def test_idle(self):
        self.assertTrue(tn.agent_idle(self.thread(), NOW)[0])

    def test_running(self):
        self.assertFalse(tn.agent_idle(self.thread(status="running", activeRunId="r"), NOW)[0])

    def test_queued(self):
        self.assertFalse(tn.agent_idle(self.thread(status="queued"), NOW)[0])

    def test_waiting_for_answer(self):
        self.assertFalse(tn.agent_idle(self.thread(pendingRequestCount=1), NOW)[0])

    def test_just_finished(self):
        self.assertFalse(tn.agent_idle(self.thread(updatedAt=iso(1)), NOW)[0])

    def test_usage_limit(self):
        limit = {"stoppedRunId": "r", "resetAt": iso(-60), "resumeAtReset": False,
                 "snoozedUntilReset": False}
        self.assertFalse(tn.agent_idle(self.thread(usageLimit=limit), NOW)[0])
        self.assertFalse(tn.agent_idle(self.thread(usageLimit={**limit, "resetAt": None}), NOW)[0])
        self.assertTrue(tn.agent_idle(self.thread(usageLimit={**limit, "resetAt": iso(10)}), NOW)[0])

    def test_updated_in_future_uses_observed_idle(self):
        # A wrong clock at boot stamped updatedAt two hours ahead.
        t = self.thread(updatedAt=iso(-110))
        self.assertFalse(tn.agent_idle(t, NOW)[0])
        self.assertFalse(tn.agent_idle(t, NOW, idle_since=iso(1))[0])
        self.assertTrue(tn.agent_idle(t, NOW, idle_since=iso(3))[0])

    def test_settled_key(self):
        self.assertIsNone(tn.settled_key(self.thread(status="running", activeRunId="r")))
        self.assertIsNone(tn.settled_key(None))
        a = tn.settled_key(self.thread(latestRunId="r1"))
        self.assertNotEqual(a, tn.settled_key(self.thread(latestRunId="r2")))

    def test_unreadable(self):
        self.assertFalse(tn.agent_idle(None, NOW)[0])


class Decide(unittest.TestCase):
    def state(self, **kw):
        s = {"last_nudge_at": iso(5), "last_fingerprint": "fp", "last_set": ["a"],
             "nudges": [iso(5)]}
        s.update(kw)
        return s

    def test_first(self):
        self.assertTrue(tn.decide(["a"], "fp", {}, NOW)[0])

    def test_unchanged_waits(self):
        self.assertFalse(tn.decide(["a"], "fp", self.state(), NOW)[0])

    def test_unchanged_after_30_min(self):
        s = self.state(last_nudge_at=iso(31), nudges=[iso(31)])
        self.assertTrue(tn.decide(["a"], "fp", s, NOW)[0])

    def test_files_changed(self):
        self.assertTrue(tn.decide(["a"], "fp2", self.state(), NOW)[0])

    def test_set_changed(self):
        self.assertTrue(tn.decide(["a", "b"], "fp", self.state(), NOW)[0])

    def test_hourly_cap(self):
        s = self.state(nudges=[iso(50), iso(40), iso(20), iso(5)])
        self.assertFalse(tn.decide(["a"], "fp2", s, NOW)[0])
        s = self.state(nudges=[iso(70), iso(40), iso(20), iso(5)])
        self.assertTrue(tn.decide(["a"], "fp2", s, NOW)[0])

    def test_future_nudges_do_not_count_toward_cap(self):
        s = self.state(nudges=[iso(-100), iso(-90), iso(-80), iso(5)])
        self.assertTrue(tn.decide(["a"], "fp2", s, NOW)[0])


class Message(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = Path(self.tmp.name)
        for name, text in FIXTURES.items():
            (d / name).write_text(text)
        self.items, errors = tn.read_items(d)
        self.unreadable = [s for s, _ in errors]
        self.actionable, _ = tn.actionable_items(self.items, NOW, OWNERS.get)
        self.text = tn.message(self.items, self.actionable, OWNERS.get, self.unreadable)
        self.lines = self.text.splitlines()

    def tearDown(self):
        self.tmp.cleanup()

    def line(self, slug):
        found = [l for l in self.lines if l[2:].startswith(slug + " ")]
        self.assertEqual(len(found), 1, f"{slug} listed once")
        return found[0]

    def test_marked_automated(self):
        self.assertTrue(self.text.startswith(tn.PREFIX))

    def test_lists_every_open_item_not_just_triggers(self):
        # Triggering items are marked *, the rest of the open list is there too.
        self.assertEqual(self.line("a-actionable"), "* a-actionable [actionable] A")
        self.assertTrue(self.line("e-flight-running").startswith(
            "- e-flight-running [in_flight, owner mcp:run running]"))
        self.assertIn("owner mcp:done stopped: completed", self.line("f-flight-done"))
        self.assertIn("owner mcp:ask stopped: asking", self.line("g-flight-asking"))
        self.assertIn("owner mcp:gone stopped: gone", self.line("h-flight-gone"))
        self.assertTrue(self.line("i-standing").startswith("- i-standing [standing]"))
        self.assertTrue(self.line("c-blocked-past").startswith("* c-blocked-past [blocked until"))
        self.assertIn("Boxers: pick and buy", self.line("o-colon-title"))
        self.assertTrue(self.line("m-unknown-status").startswith("- m-unknown-status [maybe]"))

    def test_blocked_and_done_left_out_but_counted(self):
        for slug in ("b-blocked", "d-blocked-future", "n-bad-until", "j-done"):
            self.assertFalse(any(l[2:].startswith(slug + " ") for l in self.lines), slug)
        # b, d and n (unparseable blocked_until) are blocked and not listed.
        self.assertIn("3 blocked (not listed)", self.lines[0])
        self.assertIn(f"{len(self.actionable)} need you now", self.lines[0])
        self.assertIn("2 unreadable (k-no-front-matter, l-bad-yaml)", self.lines[0])

    def test_one_line_per_item(self):
        items = [("x", {"status": "actionable", "title": "multi\nline   title"})]
        text = tn.message(items, ["x"], OWNERS.get)
        self.assertIn("* x [actionable] multi line title", text.splitlines())


if __name__ == "__main__":
    unittest.main()

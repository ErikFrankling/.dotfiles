from datetime import datetime, timezone
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("incident_state", Path(__file__).parents[1] / "incident_state.py")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


class RetryScenarios(unittest.TestCase):
    def setUp(self):
        self.line = "alert/DiskFillingUp/pc: disk low (firing since yesterday)"
        self.data = dict(now=10000, root="/repair", failing=self.line, previous="",
                         shell={"projects": [{"id": "p", "workspaceRoot": "/repair"}], "threads": []},
                         statuses=None, alerts=None)
        self.state = {"migrated": True, "attempts": {"alert/DiskFillingUp/pc": {"revision": "", "quota": 0}}}

    def test_elapsed_hours_and_midnight_never_retry(self):
        for elapsed in (3600, 86400, 7 * 86400):
            self.data["now"] += elapsed
            self.assertEqual(policy.decide(self.state, self.data)["eligible"], "")

    def test_timestamps_and_value_changes_are_not_new_evidence(self):
        self.data["failing"] = "alert/DiskFillingUp/pc: disk 18.8% (firing since now)"
        self.assertEqual(policy.decide(self.state, self.data)["reason"], "unchanged")

    def test_new_incident_does_not_resurrect_old_one(self):
        self.data["failing"] += "\nlan/kokoro (host): down; HTTP 503"
        self.assertEqual(policy.decide(self.state, self.data)["eligible"], "lan/kokoro (host): down; HTTP 503")

    def test_changed_revision_allows_one_attempt(self):
        self.state["revisions"] = {"alert/DiskFillingUp/pc": "cleanup commit abc; measured 50GiB freed"}
        self.assertTrue(policy.decide(self.state, self.data)["eligible"])
        self.state["attempts"]["alert/DiskFillingUp/pc"]["revision"] = self.state["revisions"]["alert/DiskFillingUp/pc"]
        self.assertFalse(policy.decide(self.state, self.data)["eligible"])

    def test_old_active_file_migrates_without_retry(self):
        self.data["previous"] = self.line
        self.assertEqual(policy.decide({}, self.data)["eligible"], "")

    def test_unavailable_or_silenced_monitor_cannot_clear_attempt(self):
        for _ in range(3):
            self.data["failing"] = ""
            self.data["now"] += 1000
            policy.decide(self.state, self.data)
        self.data["failing"] = self.line
        self.assertFalse(policy.decide(self.state, self.data)["eligible"])

    def test_recovery_needs_ten_minutes_then_recurrence_is_new(self):
        self.data.update(alerts=[], failing="")
        policy.decide(self.state, self.data)
        self.data["now"] += 599
        policy.decide(self.state, self.data)
        self.assertTrue(self.state["attempts"])
        self.data["now"] += 1
        policy.decide(self.state, self.data)
        self.data.update(failing=self.line, alerts=None)
        self.assertTrue(policy.decide(self.state, self.data)["eligible"])

    def test_maintenance_cannot_clear_attempt_while_alerts_rearm(self):
        self.data.update(alerts=[], failing="", maintenance=[{"end": 20000, "pattern": "DiskFillingUp"}])
        policy.decide(self.state, self.data)
        self.data["now"] += 1000
        policy.decide(self.state, self.data)
        self.assertTrue(self.state["attempts"])

    def test_short_recovery_does_not_allow_retry(self):
        self.data.update(alerts=[], failing="")
        policy.decide(self.state, self.data)
        self.data.update(alerts=None, failing=self.line, now=10599)
        self.assertFalse(policy.decide(self.state, self.data)["eligible"])

    def quota(self, auto=False):
        self.data["shell"]["threads"] = [{"projectId": "p", "limitRecovery": {
            "resetAt": datetime.fromtimestamp(20000, timezone.utc).isoformat(), "autoResume": auto}}]

    def test_quota_blocks_new_evidence_before_reset(self):
        self.quota()
        self.data["failing"] = "lan/new: down"
        self.assertEqual(policy.decide(self.state, self.data)["reason"], "quota-blocked")

    def test_reset_is_one_changed_blocker_not_hourly_retry(self):
        self.quota()
        policy.decide(self.state, self.data)
        self.data["now"] = 20001
        self.assertTrue(policy.decide(self.state, self.data)["eligible"])
        self.state["attempts"]["alert/DiskFillingUp/pc"]["quota"] = 20000
        self.data["now"] += 7200
        self.assertFalse(policy.decide(self.state, self.data)["eligible"])

    def test_t3_owns_automatic_quota_resume(self):
        self.quota(auto=True)
        self.data["now"] = 20001
        self.assertEqual(policy.decide(self.state, self.data)["reason"], "existing-owner")

    def test_missed_t3_resume_does_not_deadlock_after_reset(self):
        self.quota(auto=True)
        self.data["now"] = 21801
        self.assertTrue(policy.decide(self.state, self.data)["eligible"])
        self.state["attempts"]["alert/DiskFillingUp/pc"]["quota"] = 20000
        self.data["now"] += 3600
        self.assertFalse(policy.decide(self.state, self.data)["eligible"])

    def test_null_recovery_is_valid(self):
        self.data["shell"]["threads"] = [{"projectId": "p", "limitRecovery": None}]
        self.assertEqual(policy.decide(self.state, self.data)["reason"], "unchanged")


if __name__ == "__main__":
    unittest.main()

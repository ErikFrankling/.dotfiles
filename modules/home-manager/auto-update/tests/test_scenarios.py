"""Exercise the shipped jq decisions with failure/recovery scenarios, without services."""
import json
from pathlib import Path
import re
import subprocess
import unittest

SOURCE = (Path(__file__).parents[1] / "default.nix").read_text()


def query(start, end, data, **variables):
    block = SOURCE.split(start, 1)[1].split(end, 1)[0]
    program = block.split("'", 1)[1].rsplit("'", 1)[0]
    # Nix indented strings keep the backslashes in these jq programs.
    args = ["jq", "-c", program]
    for key, value in variables.items():
        args += ["--argjson", key, json.dumps(value)]
    result = subprocess.run(args, input=json.dumps(data), text=True,
                            capture_output=True, check=True)
    return result.stdout.strip()


def endpoint(successes):
    return [{"group": "phone", "name": "test", "results": [
        {"timestamp": f"2026-11-07T10:{i:02}:00Z", "success": ok}
        for i, ok in enumerate(successes)]}]


class IncidentScenarios(unittest.TestCase):
    def owned(self, threads):
        return query("if jq -e --arg root ${clone}", "<<< \"$snapshot\"", {
            "projects": [{"id": "repair", "workspaceRoot": "/repair"}],
            "threads": threads}, root="/repair") == "true"

    def test_running_owner_prevents_duplicate(self):
        self.assertTrue(self.owned([{"projectId": "repair", "activeRunId": "run"}]))

    def test_background_owner_prevents_duplicate(self):
        self.assertTrue(self.owned([{"projectId": "repair", "activeRunId": None,
                                    "pendingBackgroundTasks": [{"id": "child"}]}]))

    def test_finished_owner_allows_next_run(self):
        self.assertFalse(self.owned([{"projectId": "repair", "activeRunId": None,
                                     "pendingBackgroundTasks": []}]))

    def test_other_project_does_not_block(self):
        self.assertFalse(self.owned([{"projectId": "other", "activeRunId": "run"}]))

    def gatus(self, successes, windows=None):
        return query("failing=$(jq -r --argjson windows", "<<< \"$statuses\")",
                     endpoint(successes), windows=windows or [])

    def test_persistent_endpoint_failure_starts_repair(self):
        self.assertIn("phone/test", self.gatus([False] * 3))

    def test_two_failed_checks_are_not_an_incident(self):
        self.assertEqual("", self.gatus([False] * 2))

    def test_recovered_rollout_does_not_restart_repair(self):
        self.assertEqual("", self.gatus([False] * 10 + [True]))

    def test_healthy_endpoint_with_flaky_history_is_audit_only(self):
        self.assertEqual("", self.gatus([True, False] * 5 + [True]))

    def test_maintenance_excludes_failures(self):
        self.assertEqual("", self.gatus([False] * 3,
                         [{"pattern": "phone/", "end": 9999999999}]))

    def test_unrelated_maintenance_does_not_hide_failure(self):
        self.assertIn("phone/test", self.gatus([False] * 3,
                      [{"pattern": "lan/", "end": 9999999999}]))

    def alerts(self, start, windows=None):
        return query("failing_alerts=$(jq -r", "<<< \"$alerts\")", [{
            "labels": {"session": "true", "alertname": "ServiceDown"},
            "startsAt": start, "annotations": {}}],
            windows=windows or [], now=1794048000)

    def test_fresh_alert_waits_for_recovery(self):
        self.assertEqual("", self.alerts("2026-11-07T10:39:00Z"))

    def test_persistent_alert_is_not_silenced(self):
        self.assertIn("ServiceDown", self.alerts("2026-11-07T09:00:00Z"))

    def test_agent_jobs_are_owned_on_both_hosts(self):
        pattern = re.search(r"grep -qE '([^']*agent-job-[^']*)'", SOURCE)[1]
        for host in ("pc", "framework"):
            self.assertRegex(f"alert/SystemdUnitFailed/{host}/agent-job-heavy-123: failed", pattern)
            self.assertNotRegex(f"alert/SystemdUnitFailed/{host}/bluetooth: failed", pattern)


if __name__ == "__main__":
    unittest.main()

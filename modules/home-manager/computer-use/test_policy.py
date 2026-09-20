import unittest
from unittest.mock import patch
import json
import os
import subprocess

from desktop import run, session
from supervisor import allowed, decisions, eligible_windows


class AgentWindowPolicy(unittest.TestCase):
    def test_only_mapped_agent_windows_on_agent_output(self):
        monitors = [{"id": 0, "name": "DP-3"}, {"id": 2, "name": "AGENT-1"}]
        window = {"stableId": "a", "mapped": True, "monitor": 2, "workspace": {"name": "agent"}}
        for changes in ({"monitor": 0}, {"workspace": {"name": "1"}}, {"mapped": False}):
            self.assertEqual(eligible_windows(monitors, [window | changes]), set())
        self.assertEqual(eligible_windows(monitors, [window]), {"a"})
        self.assertEqual(eligible_windows([], [window]), set())

    def test_no_broad_observation_recording_or_launch_grants(self):
        request = {"capability": "control", "scope": {"kind": "window", "id": "a"}}
        self.assertTrue(allowed(request, {"a"}))
        self.assertFalse(allowed(request, {"b"}))
        for capability in ("record", "launch", "unknown"):
            self.assertFalse(allowed(request | {"capability": capability}, {"a"}))
        self.assertFalse(allowed(request | {"scope": {"kind": "workspace", "id": "a"}}, {"a"}))

    def test_pause_and_revocation_never_resume_or_approve(self):
        request = {"id": "r", "state": "pending", "capability": "control",
                   "scope": {"kind": "window", "id": "a"}}
        state = {"mode": "approve", "requests": [request], "grants": []}
        self.assertEqual(list(decisions(state, {"a"})), [("approve", {"id": "r", "seconds": 300})])
        for changed in ({"paused": True}, {"revocation_unconfirmed": True}, {"mode": "yolo"}):
            self.assertEqual(list(decisions(state | changed, {"a"})), [])
        grant = {"id": "g", "capability": "control", "scope": {"kind": "window", "id": "old"}}
        self.assertEqual(list(decisions(state | {"paused": True, "grants": [grant]}, {"a"})),
                         [("revoke", {"id": "g"})])


class SessionLaunch(unittest.TestCase):
    def test_subprocess_cannot_consume_mcp_stdin(self):
        with patch("desktop.subprocess.run") as process:
            process.return_value.stdout = "ok"
            run("hyprctl", "-j", "instances")
            self.assertEqual(process.call_args.kwargs["stdin"], subprocess.DEVNULL)

    def test_stale_session_refresh_clears_inherited_socket(self):
        with patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "old", "WAYLAND_SOCKET": "9"}):
            with patch("desktop.run", return_value=json.dumps([{"instance": "live", "wl_socket": "wayland-2"}])):
                session()
            self.assertEqual(os.environ["HYPRLAND_INSTANCE_SIGNATURE"], "live")
            self.assertEqual(os.environ["WAYLAND_DISPLAY"], "wayland-2")
            self.assertNotIn("WAYLAND_SOCKET", os.environ)

    def test_ambiguous_sessions_are_refused(self):
        with patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "old"}):
            with patch("desktop.run", return_value=json.dumps([
                {"instance": "one", "wl_socket": "wayland-1"},
                {"instance": "two", "wl_socket": "wayland-2"},
            ])):
                with self.assertRaises(RuntimeError):
                    session()


if __name__ == "__main__":
    unittest.main()

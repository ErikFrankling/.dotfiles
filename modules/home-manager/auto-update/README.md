# Unattended maintenance

Erik owns product decisions; automation owns routine engineering and recovery.
Updates, rebases, successful repairs, elapsed-time checkpoints and exhausted
retry budgets are records, not reasons to interrupt him. An escalation must
name a concrete action only he can perform, create an attention item, and link
the owning thread. Discord remains a fallback for that notification.

The controller uses existing systemd timers, locks, T3 ownership and
Alertmanager routing rather than introducing another orchestration service:

- Compare the desired Nix closure to the running system and system profile.
  Advancing git is not proof of a successful activation; retries must still run.
- Open maintenance at the activation boundary, before restarting services.
- Serialize watcher state and session launches. Check active T3/background and
  headless owners before touching their checkout. Preserve interrupted work.
- An unconfirmed launch is not permission to start a second worker. Recheck
  ownership on retry. Record launch failures without consuming the daily cap.
- Require consecutive endpoint failures and sustained monitor unavailability.
  Recovered/flaky history belongs in the daily audit. Agent job exit codes
  belong to the initiating session; independent service probes catch impact.
- Alertmanager keeps agent-owned incidents queryable without automatically
  paging after a timeout. Direct human-owned alert routes remain intact.
- `systems-check audit` exposes rolling 24-hour sessions, notifications,
  incident decisions and service logs. The skill requires full thread review,
  other notification sources, coverage gaps, corrective changes and evidence
  in `~/.local/state/systems-check/audit-YYYY-MM-DD.md`.
- `systems-check report` persists results quietly. Its watchdog retries a
  missing run through the same ownership guard instead of asking Erik to debug.

Regression checks: run `python3 modules/home-manager/auto-update/tests/test_scenarios.py`
in a Python environment with `jq` on PATH. Nix's `writeShellApplication` also
checks generated shell scripts when building. Verify deployed `health-watch
--dry-run`, Gatus results, Alertmanager routing and timer definitions.

Research informing these decisions:

- [Google SRE: Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/):
  user-visible symptoms and actionable alerts; historical events are diagnostic evidence.
- [StrongDM Software Factory](https://factory.strongdm.ai/):
  specify outcomes and validate scenarios, feeding failures back into autonomous work.
- [Gatus v5.37.0 client](https://github.com/TwiN/gatus/blob/v5.37.0/client/config.go):
  HTTP connections are pooled. The homelab's phone probes use `Connection: close`
  to avoid retaining a CONNECT tunnel created before Tailscale's route exists.

Limits: a local notification log is not a global ledger. The daily audit must
also inspect Executor, the Framework and Alertmanager; unread sources are
reported as coverage gaps. Offline laptops apply from their persistent update
timer when reachable on mains at home. Maintenance windows are bounded: a real
failure persisting after the window still needs repair.

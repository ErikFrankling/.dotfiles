# Deployment status

The repaired speech backend is applied and the complete long-recording browser
test passed on 2026-09-20. The tested T3 UI is source-fork revision `411a3466`.
Its final live activation is pending the independent rebuild job, because
restarting T3 also terminates the coding session it hosts.

Do not infer that the live UI is updated until the job replaces this status
with its activation result. It runs `rebuild switch`, checks the active system
and T3 package, then replays the full captured recording through the live route.

See [measured results and limitations](2026-09-20/DICTATION_REPAIR.md).
Private handoff logs: `2026-09-20/private/activation-job.log`, `rebuild.log`,
and `live-verification.json`. All original drafts and audio are retained.

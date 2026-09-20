# Deployment status

Applied and verified on the PC at 2026-09-20T09:06:21.230230+00:00.

- T3 runs source-fork revision `411a3466` with the responsive dictation workspace.
- Both speech workers are active, GPU-resident and configured to remain loaded; services start at boot.
- The full 400.896-second captured recording passed through the live T3 route, streaming preview and long-context VibeVoice final pass.
- Actual browser microphone replay, desktop/mobile rendering, non-destructive close, failure fallback and recovery were verified before activation.

See [repair results and limits](2026-09-20/DICTATION_REPAIR.md). Private live proof: `2026-09-20/private/live-verification.json`.

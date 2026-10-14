# Deployment status

Applied with `rebuild switch` and verified live on the PC on 2026-09-21.

- T3 runs source-fork revision `f837fdf587cdfbd9f4faf8f0c2d23e6da35c4534`.
- Stop queues automatic delivery to the original chat. Three refinement attempts precede unchanged live-draft fallback. Accepted jobs survive navigation and server restart.
- Both speech workers are active, GPU-resident and configured to remain loaded; services start at boot.
- Live browser microphone replay reached VibeVoice and produced exactly one message and one LLM reply after switching chats. Warm listening startup: 0.228 seconds; Stop-to-delivery: 3.074 seconds for the 12-second recording.
- Desktop and mobile browser checks passed: stable composer geometry, Enter sends, Shift+Enter newline, controls at least 44 × 44 CSS pixels, and touch Stop with forced refinement failure.
- The retained 400.896-second recording passed the updated whole-recording VibeVoice path, finishing 43.19 seconds after Stop. This was a separate long-audio service test, not a 400-second live browser run.
- Forced failure and restart tests confirmed draft fallback and duplicate suppression with actual LLM replies.

See [repair results, methodology and limits](2026-09-21/DELIVERY_REPAIR.md).
Private evidence: `2026-09-21/private/verification/`, including
`live-service-proof.json`, `live-dictation-result.json`, `live-llm-result.json`,
screenshots, test scripts and build logs. The temporary verification project
is removed after collecting its evidence.

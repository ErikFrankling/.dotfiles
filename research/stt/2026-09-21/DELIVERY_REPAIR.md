# Automatic dictation delivery and reliability — 2026-09-21

Stopping a recording now hands a durable job to T3. It refines the original
recording, retries refinement three times, then sends either the refined text
or the unchanged live draft to the original chat. Typed text and attachments
are captured with the destination. Changing chats does not cancel delivery.
Atomic, flushed checkpoints and stable orchestration command IDs provide
restart recovery and duplicate suppression. New threads and worktrees use the
same bootstrap implementation as interactive T3 turns.

The composer keeps its expanded geometry on focus/blur. Enter sends on desktop
and narrow screens; Shift+Enter adds a newline. The recording workspace retains
its read-only draft, large controls, and recoverable audio. Closing it also stops
and sends. Upload interruptions retain retry/download recovery; an offline
browser must finish uploading before the server can own the recording.

## Verified evidence

| Check | Result |
|---|---|
| Server/web typechecks | Passed |
| Durable delivery tests | 6 passed: refinement retry, outage fallback, restart recovery, deduplication, destination protection, dispatch retry |
| Existing thread/worktree bootstrap regressions | 6 passed |
| Composer logic tests | 47 passed |
| Speech coordinator tests | 11 passed |
| Real browser microphone replay | 12 seconds of Erik's original audio, real streaming and VibeVoice; Stop then change chat; refined message and LLM reply appeared exactly once in the original chat |
| Warm microphone startup | 0.18–0.23 seconds in browser tests |
| Forced final-worker failures | Three HTTP 503 responses, then unchanged live draft delivered automatically in 6.4 seconds; actual LLM reply confirmed |
| Restart after dispatch but before delivery checkpoint | Original saved command replayed; still one user message and one assistant response |
| Composer focus/blur at 1360 and 390 CSS pixels | Identical editor position and dimensions; Shift+Enter newline; Enter submitted and received an LLM reply |
| Recording controls at 390 × 844 | No visible control below 44 × 44 CSS pixels; touch-tapping Stop passed the automatic-fallback flow |
| Full retained audio | 400.896 seconds, all 12,828,672 PCM bytes covered by one final quality window; successful |
| Stop-to-final on full audio | 43.19 seconds including remaining background work; quality request itself 36.64 seconds |
| Full-audio peak resources | 14.84 GiB total device VRAM, 1.61 GiB maximum observed per-worker anonymous RAM, zero worker swap |
| Frozen-reference agreement | 98.27%, 17 edits / 983 reference words; 5 question checks and 7/8 content checks |

Reference agreement is **not human-measured accuracy**. The previous 20-second
encoder run had 16 edits. This one-word difference does not establish a quality
ranking. Both use the same original audio and full decoder context. The new
10-second internal stateful encoder block reduces temporary allocation without
turning final transcription into short, independently decoded fragments.
Ambient desktop VRAM differed between runs; the resource numbers are not a
controlled measurement of the block-size reduction alone.

Live deployment verification also passed on the pinned `f837fdf5` build: real
browser audio, navigation away after Stop, one refined message and one actual LLM
reply in the original chat. Warm startup was 0.228 seconds; Stop-to-delivery was
3.074 seconds for the short recording.

## Errors investigated

Historical logs contained actual empty-recognition failures and GPU memory-guard
terminations near the configured 17 GiB total-device limit. The guard remains;
GPU contention must not crash the desktop. Background refinement failures now
back off and remain diagnostic events rather than presenting a fatal recording
error while live capture continues. Final failures trigger T3's retries and draft
fallback. Both model workers remain configured to warm at boot and stay resident.

Speech logs now record recording/refinement starts, completion timing, error type,
and memory-guard resource values. T3 logs durable queue acceptance, refinement
attempts, delivery failures, and completion with recording/thread IDs. Transcript
text is excluded from these structured logs. The aiohttp websocket timeout
argument was updated to remove its deprecation warning.

A historical `PreviewAutomationNoAvailableHostError` came from browser preview
host discovery, not STT. Native Vulkan portability and legacy GGUF-schema warnings
were informational; they were not evidence of a failed transcription.

Browser testing caught a new-thread bootstrap omission in the first queue
implementation. That implementation was not deployed. The corrected shared
bootstrap path passed both existing regressions and the real new-chat test.

## Reproduction and boundaries

Fork: `ErikFrankling/t3code`, branch `erik/local-dictation`, commit `f837fdf5`.
The flake pins this source; no bundle patch was introduced. See
[deployment status](../DEPLOYMENT_STATUS.md) for actual live activation.

Private evidence is in `private/verification/`: browser scripts/screenshots,
check logs, queue checkpoints, injected-failure logs, long-audio provenance,
resource/quality results, and actual LLM delivery evidence. Historical service
logs are in `private/stt-before.log` and `private/t3-before.log`.

Tests cover the locally hosted web client, including a phone-sized viewport.
Electron shares this web composer. The separate React Native client has no new
recording interface in this change. External relay/multi-environment dictation
routing remains outside this same-origin deployment. Thirty-minute recordings
and arbitrary vocabulary coverage remain unverified.

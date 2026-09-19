# Streaming plus VibeVoice integration — 2026-09-19

The source fork is [ErikFrankling/t3code, erik/local-dictation](https://github.com/ErikFrankling/t3code/tree/erik/local-dictation),
based on upstream v0.0.40. Nix pins the fork revision in `flake.lock`; auth and
JSON-RPC changes are maintained in source rather than editing a generated bundle.
The host coordinator is in `tools/local-stt`, with a declarative systemd module.

## Verified before live activation

- A 24-second excerpt passed through Nemotron's Vulkan streaming socket and
  then independently through VibeVoice's audio API. A draft arrived before stop.
- The entire 398.739625-second recording passed through T3's authenticated
  `/api/dictation` route, with automatic vocabulary/context from the actual
  Naiaclaw repository. The final included NaiaClaw, Claude Code, Codex and Planet9.
  Finalization took 86.2 seconds including worker startup/context preparation;
  the accelerated upload-plus-final test took 104.1 seconds. Observed peak total
  VRAM was 15.97 GiB. This is an integration observation, not a controlled speed
  comparison with the earlier 42.1-second benchmark.
- Headless Firefox replayed real recorded audio as a MediaStream through T3's
  microphone button, capture code, upload path, streaming preview and final pass.
  The composer retained its existing introduction and replaced its own draft.
- Browser tests with controlled recognizer responses verified preservation of
  manual edits, explicit insertion after editing, cancellation restoring prior
  text, and thread switching finalizing the old recording without inserting its
  result into the new thread. These UI safety tests isolate state behavior;
  they are distinct from the real-model tests above.
- Server/web typechecks and the focused auth/protocol suites passed. Coordinator
  tests cover owner isolation, duplicate/out-of-order chunks, malformed PCM and
  rejecting empty recordings.

The real audio outputs still have recognition errors and disfluencies. VibeVoice
also emitted bracketed non-speech annotations; the coordinator now removes only
known event labels such as `[Music]` and `[Silence]`. No text-only LLM is rewriting
meaning. Do not treat successful integration as proof of perfect transcription.

Runtime behavior is deliberately bounded: preview exits before final inference,
final weights unload after two idle minutes, and the final worker exits before
preview restarts. Both use Vulkan on the RX 7900 XT. The coordinator retains audio
and provenance privately. The 30-minute upload cap is not a validated 30-minute
GPU capacity claim.

Private JSON outputs, browser screenshots, replay scripts, and the coordinator's
recordings/state are preserved under `private/integration/`. Public operator
instructions are in `tools/local-stt/README.md`; current research priorities and
remaining evaluation gaps are in `research/stt/METHODOLOGY.md`.

Live activation is tracked separately in `research/stt/DEPLOYMENT_STATUS.md`.
An isolated test server used a fresh private T3 data directory; the production
T3 SQLite database was not used as a test fixture.

# Agreed integration scope — 2026-09-19

The initial archive captured the agreed scope before implementation. The fork
and coordinator now have [isolated T3 integration evidence](2026-09-19/INTEGRATION.md).
See [deployment status](DEPLOYMENT_STATUS.md) for live activation; successful
research or isolated tests must not be confused with an activated service.

- One PC-hosted speech service, managed declaratively by Nix/systemd at startup.
  Prefer GPU for both preview and final inference; bound host RAM and preserve
  safe desktop VRAM headroom. GPU models may remain resident when safe.
- Explicit microphone start/stop. Pauses must never stop a recording. Show a
  streaming draft, then transcribe original retained audio with VibeVoice Q8
  and relevant project vocabulary/context for the final result.
- Obtain project context from the active T3 thread/repository. Harvest names,
  manifests, documentation, paths and symbols; exclude dependency noise and
  secrets. Select context within the actual model/resource budget. Do not
  present a manually curated 18-name test list as automatic repository coverage.
- Replace only the recording's own draft. Preserve preexisting composer text,
  manual edits, and thread ownership. Switching threads must not insert text
  into the wrong conversation. Users still edit and send normally.
- Retain recoverable audio/transcript state for transient failures and provide
  retry/cancel behavior. Aim to support long recordings up to 30 minutes;
  that duration still needs validation, not inference from the 6m39s study.
- Browser connects through T3's same-origin route; T3 and speech service run on
  the same PC. Keep service endpoints local rather than exposing an unauthenticated
  GPU worker directly. Other devices should use the T3 origin securely.
- Use a real source fork, not post-bundle patching. Fork created at
  https://github.com/ErikFrankling/t3code, branch `erik/local-dictation`, based on
  v0.0.40. Pin it as a flake source and migrate existing auth and JSON-RPC fixes.
- Initial preview candidate: Nemotron streaming via NeMo-Speech.cpp/Vulkan.
  Final candidate: audio.cpp VibeVoice ASR Q8. Service packaging, coexistence,
  live capture and failure recovery must be tested; this is not a claim they
  already run together successfully.
- Keep existing desktop dictation available while validating the T3 path.
  Future clients can share the speech service; Voxtype is not a stack constraint.

Acceptance requires a real T3 browser test showing a draft during recording,
an independent audio-based final result, correct project context, preserved
composer edits/thread ownership, retry/cancel behavior, and measured GPU/RAM
use, followed by the declarative rebuild and source/config commits.

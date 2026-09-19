# Local T3 speech service

Nix builds the coordinator, NVIDIA NeMo-Speech.cpp with Vulkan streaming,
and audio.cpp with VibeVoice ASR Q8. No runtime downloads or CPU model offload.
Enable `services.local-stt.enable` after importing `modules/nixos/local-stt.nix`.
T3 forwards authenticated requests through `/api/dictation`; only the T3 origin
should be exposed. Internal ports 8781–8783 bind loopback.

The coordinator starts at boot. Model workers start on demand. Preview exits
before final inference; the final model unloads after two idle minutes and its
worker exits before the next preview starts. A monitor stops the owned worker
above 17 GiB total GPU use, below 3 GiB available host RAM, above 6 GiB anonymous
worker RAM, or above 256 MiB worker swap. This observes memory rather than
reserving VRAM: competing GPU workloads can still cause a request to fail.

Recordings and state are private under `/var/lib/local-stt` (0700). Original PCM,
WAV, transcripts, selected vocabulary, context and runtime provenance are kept
for recovery/research. They are not sent to cloud providers. There is currently
no automatic retention deletion. Manage this directory as private user data.
Chunk sequence numbers prevent a retried upload from duplicating audio. An
interrupted service marks unfinished recordings recoverable for final-pass retry.

Context uses bounded tracked-file reads, excluding secret/credential/env/key
paths, dependencies, generated trees and symlinks. It favors project documentation,
project/tool names, and symbols relevant to the preview. The preview can be
wrong, so it never exclusively determines which project terms survive selection.
The current prompt is deliberately compact; large-context retrieval remains a
research question, not an established benefit. See [the research archive](../../research/stt/README.md).

The request cap is 30 minutes of 16 kHz mono PCM16. That is a transport limit,
not a guarantee that every 30-minute final pass fits the GPU. The verified study
recording is 6m39s; failures retain audio for retry. English is the configured
language. Known non-speech event annotations are removed from final dictation;
spoken self-corrections and filler wording are otherwise preserved.

Run protocol tests with a Nix Python environment containing aiohttp:
`python3 tools/local-stt/test_gateway.py`. They check recording ownership,
idempotent chunks, order/format rejection and empty-recording rejection.

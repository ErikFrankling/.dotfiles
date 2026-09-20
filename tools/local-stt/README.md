# Local T3 speech service

Nix builds the coordinator, NVIDIA NeMo-Speech.cpp with Vulkan streaming,
and audio.cpp with VibeVoice ASR Q8. No runtime downloads or CPU model offload.
Enable `services.local-stt.enable` after importing `modules/nixos/local-stt.nix`.
T3 forwards authenticated requests through `/api/dictation`; only the T3 origin
should be exposed. Internal ports 8781–8783 bind loopback.

The coordinator preloads both GPU model workers at boot and retains them.
Nemotron provides the live draft. VibeVoice refines completed 22–30-second
sections while recording, then performs a longer-context quality pass after
Stop. The short sections are progress feedback, not the final quality result:
benchmarks found worse wording when they were merely concatenated. The final
pass uses up to seven minutes of audio per window, with quiet boundaries or a
two-second overlap for continuous speech. Each pass has separate retry checkpoints.

The native runtime uses stateful 20-second acoustic-encoder blocks instead of
60-second blocks. Encoder state crosses those blocks and all latents enter the
same decoder prompt; this does not divide the transcript into 20-second pieces.
It also releases completed decoder-prefill scratch memory while retaining model
weights. These changes allow the tested long-context request with both workers
resident. See the [measured repair results](../../research/stt/2026-09-20/DICTATION_REPAIR.md).

A monitor stops the owned worker above 17 GiB total GPU use, below 3 GiB
available host RAM, above 6 GiB anonymous worker RAM, or above 256 MiB worker
swap. This observes memory rather than reserving VRAM: competing GPU workloads
can still cause a request to fail. Failure retains the original draft and audio.

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
not a guarantee of tested quality across every recording length. The verified study
recording is 6m39s; failures retain audio for retry. English is the configured
language. Known non-speech event annotations are removed from final dictation;
spoken self-corrections and filler wording are otherwise preserved.

Run protocol tests with a Nix Python environment containing aiohttp:
`python3 tools/local-stt/test_gateway.py`. They check recording ownership,
idempotent chunks, order/format rejection, chunk boundaries, draft/audio
retention on failure, and separation of background and quality checkpoints.

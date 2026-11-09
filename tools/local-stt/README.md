# Local T3 speech service

Nix builds the coordinator, NVIDIA NeMo-Speech.cpp with Vulkan streaming,
and audio.cpp with VibeVoice ASR Q8. No runtime downloads or CPU model offload.
Enable `services.local-stt.enable` after importing `modules/nixos/local-stt.nix`.
T3 forwards authenticated requests through `/api/dictation`; only the T3 origin
should be exposed. The coordinator listens on loopback port 8781.

The two recognisers are llama-swap models (`dictation-preview`,
`dictation-final`, defined in `modules/nixos/local-stt.nix` from
`workers.nix`), so one scheduler owns the whole GPU (since 2026-11-09). The
coordinator runs no model: it reaches them through
`http://127.0.0.1:8000/upstream/<model>/`, uploads WAV bytes for the final
pass (the recordings stay private to the coordinator's user), and never
unloads a model to make room. llama-swap keeps every set of models that fits
its VRAM pool loaded, unloads idle ones when a request needs room, queues a
request behind a model that is still answering one (speech first), and starts
a crashed recogniser again on the next request. Design and measurements:
[research/llama-swap/2026-11-07](../../research/llama-swap/2026-11-07/README.md).

Starting a recording never waits for a model: the coordinator accepts it at
once (the browser names it, so a retried start is harmless), stores the audio,
and loads the workers behind it. A new recording may start while earlier ones
are still being transcribed; final passes run one at a time.

llama-swap preloads the live recogniser at boot and keeps it (1.2 GiB fits
beside everything). The coordinator asks for the final recogniser when a
recording starts, and llama-swap unloads it after 30 idle minutes; after that
the coordinator lends the GPU to read-aloud's big voice once per idle period.
Nemotron provides the live draft by reading the stored audio, so it starts
late, catches up, and reconnects after a worker restart without losing the
recording. VibeVoice refines completed 22–30-second
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

A final pass that waits never gives up: it may queue behind a job that holds
the GPU (llama-swap does not interrupt a running request), retries with
backoff (2 s doubling to 60 s), restarts the recogniser through llama-swap
every second failure, and drops from 7-minute to 2-minute to 30-second
windows, which need less GPU scratch memory. A recording leaves `finalizing`
only with a transcript or after the recogniser twice heard no speech. A final
transcript with under half the draft's words is treated as truncated and
redone in shorter windows. Unfinished recordings and transcriptions resume
after a service restart.

Recordings and state are private under `/var/lib/local-stt` (0700). Original PCM,
WAV, transcripts, selected vocabulary, context and runtime provenance are kept
for recovery/research. They are not sent to cloud providers. There is currently
no automatic retention deletion. Manage this directory as private user data.
Chunk sequence numbers prevent a retried upload from duplicating audio.

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
idempotent chunks and starts, order/format rejection, chunk boundaries,
finalization through worker failures and restarts, silence, truncation, and
separation of background and quality checkpoints.

`test_scheduling.py` runs the real llama-swap binary with the PC's generated
llama-swap settings and fake model servers, and the real coordinator through
it (instructions at its top): which models stay loaded together, who waits
for whom, crash recovery, idle unloading, and whole recordings while the big
voice or a long LLM job holds the GPU.

## Monitoring

Every minute the gateway streams a bundled spoken clip to the live recogniser
and expects words back; a failure restarts it through llama-swap and tries
again.
`curl -s http://127.0.0.1:8781/health/deep` returns 503 with the reasons while
the self-test fails, its last pass is older than five minutes, or a final
transcription has been stuck for ten. The homelab probes that endpoint
(`modules/nixos/observability`); five minutes of failure fires
`LocalServiceDown`, which starts a repair session through health-watch. Look at
`journalctl -u local-stt` for `selftest.failed`, `preview.interrupted` and
`recording.retry`, and at the recognisers' own output in llama-swap's UI
(`http://127.0.0.1:8000`, Logs) or `curl -s localhost:8000/logs/stream/dictation-final`.

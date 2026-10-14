# Local T3 speech service

Nix builds the coordinator, NVIDIA NeMo-Speech.cpp with Vulkan streaming,
and audio.cpp with VibeVoice ASR Q8. No runtime downloads or CPU model offload.
Enable `services.local-stt.enable` after importing `modules/nixos/local-stt.nix`.
T3 forwards authenticated requests through `/api/dictation`; only the T3 origin
should be exposed. Internal ports 8781–8783 bind loopback.

Starting a recording never waits for a model: the coordinator accepts it at
once (the browser names it, so a retried start is harmless), stores the audio,
and loads the workers behind it. A new recording may start while earlier ones
are still being transcribed; final passes run one at a time.

The coordinator preloads both GPU model workers at boot and retains them.
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

A monitor stops the owned worker above 19.5 GiB total GPU use, above 6 GiB
anonymous worker RAM, above 256 MiB worker swap, or when the host has under
3 GiB available and the worker itself holds more than 1 GiB. Low host RAM alone
is not a reason: the models live on the GPU, and stopping a ~100 MiB process
only bought a minute-long reload on the next recording (this was the main
cause of unreliable dictation up to 2026-10-06). The final recogniser is not
started with less than 9.5 GiB of free GPU memory.

The monitor observes memory rather than reserving VRAM, so competing GPU
workloads can still fail a request. The final pass therefore never gives up:
it waits (2 s doubling to 60 s), asks llama-swap to unload, restarts the
worker, and drops from 7-minute to 2-minute to 30-second windows, which need
less GPU scratch memory. A recording leaves `finalizing` only with a transcript
or after the recogniser twice heard no speech. A final transcript with under
half the draft's words is treated as truncated and redone in shorter windows.
Unfinished recordings and transcriptions resume after a service restart.

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

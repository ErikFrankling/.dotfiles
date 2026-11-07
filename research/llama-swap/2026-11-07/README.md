# Centralizing local inference lifecycle in LlamaSwap

2026-11-07. Investigation and executable scheduling prototype, not a production migration.

## Decision

Centralize PC GPU model lifecycle in the existing LlamaSwap. Keep the recording
coordinator as the application that saves audio, streams drafts, produces final
transcripts, and retries interrupted work. It should stop being a second model
process manager. There is no demonstrated need for a new scheduling service or
custom wrapper around LlamaSwap.

The installed v268 already supports capacity pools, eviction costs, queue
priorities, concurrent compatible models, and active-request protection.
Our production configuration uses groups, and speech workers are outside it.
The earlier suggestion that LlamaSwap might lack these facilities was premature.

This investigation proves important scheduling properties with the real binary.
It also reproduces starvation and forced-unload behavior. It does NOT prove all
real-model workloads fit or that the migration is ready to activate.

## Code examined

- `tools/local-stt/gateway.py`, its test suite, packaging, native runtime patch,
  streaming/final server derivations, and README.
- `modules/nixos/local-stt.nix`, `llama-swap.nix`, `kokoro-tts.nix`, observability
  probe configuration, and T3 environment in `hosts/pc/home.nix`.
- T3 server `dictationHttp.ts`, dictation audio submission, and read-aloud routing,
  model readiness, and request deadlines in `apps/server/src/readAloud.ts`.
- LlamaSwap v268 source at commit
  `2576af3ac6aaec841706c212186f0475b086bb5b`: capacity planner, FIFO scheduler,
  router/process lifecycle, upstream passthrough, model settings, hardware and
  performance monitoring. Source obtained from the upstream v268 archive;
  archive root and installed binary version agree.

## Current ownership and problems

The gateway spawns Nemotron and VibeVoice directly. It monitors VRAM/RAM, warms
workers, restarts them, unloads VibeVoice after inactivity, and calls LlamaSwap's
admin unload API when it needs memory. LlamaSwap model command wrappers call the
gateway's `/release-gpu`; only Higgs has the additional `gpuRoom` start gate.

Specific weaknesses found in code:

1. `make_room()` calls admin unload endpoints. Despite its "idle models"
   docstring, it does not test whether a model is processing a request. Admin
   unload forcibly interrupts active work; the integration test reproduces it.
2. `releaseStt` ignores a refusal and still executes the model command. Higgs
   has a separate memory gate, but the large language-model commands do not.
3. Checking free VRAM and then launching a process is not a reservation. The
   gateway and LlamaSwap can make conflicting decisions concurrently.
4. The gateway's 200 ms memory watchdog is reactive: it kills speech workers
   after pressure appears. It is not scheduling or admission control.
5. Final-worker release/monitor paths do not consistently hold the same lock
   as startup. The system has several independent lifecycle authorities.

The gateway's durable audio and transcript checkpoints are valuable. Keep them;
do not replace the recording workflow with a raw speech HTTP proxy.

## Proposed operation

T3 continues to send recording commands to the coordinator on loopback. Start
acknowledges immediately and audio is saved even while inference waits.
The coordinator sends both inference streams through LlamaSwap:

- Nemotron: `/upstream/dictation-preview/v1/audio/transcriptions/realtime`
  (WebSocket, binary PCM frames).
- VibeVoice: `/upstream/dictation-final/v1/audio/transcriptions`
  (existing native JSON protocol, preserving the inner `model: vibevoice`).
- Summary, Higgs, Breeze, and local language models remain behind LlamaSwap.

LlamaSwap owns all their processes, startup readiness, idle TTLs, and eviction.
Use its capacity router with integer MiB budgets and conservative **peak**
requirements. Reserve desktop/driver headroom outside the model pool. Account
for weights, KV cache, image/audio encoder scratch space, and concurrent slots.
The prototype uses abstract units; they must not be copied as real VRAM sizes.

Keep the small streaming recognizer compatible with the allowed large-model
profiles if measurements prove that fit. An open speech WebSocket protects its
model from eviction for the whole recording. VibeVoice and a large LLM cannot
both be admitted if their declared requirements exceed the pool. The LLM waits
for an active final transcription; final transcription waits for an active LLM.
Compatible summary requests can proceed concurrently.

Set high FIFO priority for speech and `concurrencyLimit: 1` for competing large
background models. The latter limits *admitted* requests, including queued ones;
it returns 429 instead of accepting an unbounded background backlog. Preserve
that backlog in the calling application with bounded backoff and retry. Audit
each consumer before enabling the limit: a cloud-rate-limit handler that sleeps
for an hour would be wrong for local capacity pressure.

This is non-preemptive scheduling. Bound background job durations and output
budgets; break batch work into short requests. A queue priority cannot make a
five-minute active generation disappear. If immediate final speech is required
even during such a job, deliberately cancelling/retrying background work or
using another GPU is a separate policy decision. Never hide that delay behind
a claim of instant swapping.

Kokoro lives on another GPU in the homelab. It can share an API entrypoint, but
must not consume the PC's capacity pool. Its remote process lifecycle remains
with its existing homelab deployment. Cloud assistants likewise do not occupy
the local GPU. One owner per physical resource is the useful boundary.

## Integration details that cannot be skipped

- Remove `releaseStt`, `gpuRoom`, gateway process spawning/stopping, `make_room`,
  and automatic competing-model warming when replacing that lifecycle. Leaving
  old callbacks in place would retain races and forced eviction.
- Preserve the recording coordinator's storage, ownership checks, per-recording
  checkpoints, final-pass serialization, vocabulary, cleanup, and retry logic.
- Replace `workers`-based readiness and health answers with scheduler state.
  A legitimately queued or unloaded model is not a failed service.
- Current self-tests start the preview every minute. Health checks must not
  continuously reload an intentionally evicted model. The tested upstream
  `upstream.ignorePaths` setting can return 409 for unloaded health paths without
  triggering a swap. Synthetic inference checks still need an explicit policy:
  test an already resident worker, or run a scheduled idle-only full test.
- Do not ignore WebSockets for activity tracking: that would undermine idle
  protection. Close abandoned streams so they do not pin VRAM forever.
- Keep bounded retries for crashes and cancellation. Ordinary scheduling must
  never call the force-unload admin endpoint to make room.
- The gateway currently sends a local WAV **filename**, and recordings are
  private (0700). A speech process moved from `erikf` to LlamaSwap's `llama-cpp`
  account cannot read it. Choose supported audio upload or a deliberate private
  ownership/permissions arrangement; do not make recordings world-readable.
- LlamaSwap listens on all interfaces with an open firewall. Native speech
  endpoints accept server-local file paths. Do not expose those endpoints to
  additional callers as an accidental consequence of consolidation; retain
  loopback/authenticated access for speech and its admin controls.
- Preserve Vulkan device selection and native library compatibility, the audio
  encoder/prefill memory patch, container `cmdStop`, and resource safeguards.
  Capacity accounting is declared budgeting, not live GPU-memory enforcement.
- Existing gateway deadlines include a 30 s client default, 45 s self-test,
  60 s startup wrapper, and 300 s final request. Queue time and cold-load time
  must be considered separately from actual inference and health failures.
- Remove opportunistic Higgs warming at first. On-demand loading plus remote
  Kokoro fallback is simpler than a background warm request competing with speech.

## Tests run

`test_scheduler.py` uses the installed, unmodified v268 executable with isolated
loopback ports and tiny aiohttp subprocesses. No real model is loaded, no
production service is stopped, and all test processes/files are cleaned up.
Each test gets a fresh scheduler. Native process starts and actual HTTP/WebSocket
responses are observed, rather than mocking the scheduling algorithm.

All **15 tests passed** (23.485 s). Raw output: `scheduler-results.txt`.

| Scenario | Observed result |
| --- | --- |
| Preview + summary + final fit the declared pool | All remain resident |
| A large model needs room | Evicts required models, keeps compatible preview |
| Final inference is active when voice arrives | Voice waits; final response completes |
| Incompatible models requested cold simultaneously | Requests execute without overlapping incompatible inference |
| Five callers request one cold model | One backend process starts |
| Binary speech WebSocket plus compatible large model | Audio frames and subsequent messages survive |
| Long-lived incompatible WebSocket | Competing model waits until the stream closes |
| Speech and voice queue behind a running large job | Speech wins the queue; active job is not preempted |
| New requests keep arriving for the resident large model | Reproduced bypass of waiting high-priority speech |
| Same contention with one admitted large-model request | Extra background request gets 429; speech proceeds after current job |
| Queued client cancels | Its model is not started later |
| Health request for unloaded model with ignorePaths | 409, no model load; loaded health succeeds |
| Backend crashes | Next request restarts it successfully |
| Backend fails startup | Error returned; next request succeeds after cause is removed |
| Idle TTL with a longer active request | Active request survives; model unloads after becoming idle |
| Explicit admin unload during active work | Active request fails; next request restarts successfully |

Some tests assert known limitations, not desirable behavior. A green suite does
not mean starvation or forced-unload interruption has vanished.

The existing gateway suite also passed: **24 tests**, 0.305 s, output in
`gateway-results.txt`. It covers persistence/protocol checks, retry and
transcription recovery, silence, truncation, overlapping recordings, and existing
sharing logic. Those are mostly unit/mocked-backend tests, not a migrated gateway
integration or real-model quality test.

Reproduce without installing packages imperatively:

```sh
LLAMA_SWAP_BINARY=/nix/store/zhfyj24zyg9hl5gl0xp7y8mch37fq6a4-llama-swap-268/bin/llama-swap \
  /nix/store/qiqccdw5mm23af2pj7fl8iwfnh5gypjb-python3-3.14.8-env/bin/python3 \
  research/llama-swap/2026-11-07/test_scheduler.py
/nix/store/qiqccdw5mm23af2pj7fl8iwfnh5gypjb-python3-3.14.8-env/bin/python3 \
  tools/local-stt/test_gateway.py
```

These store paths are the installed versions on the investigation date. On a
later system use its packaged LlamaSwap and an aiohttp Python Nix environment.

## Remaining real-GPU acceptance work

Before claiming a smooth production migration, measure and exercise:

1. Peak VRAM for every enabled model/profile, cold start, long speech, images,
   context limits, and supported co-resident combinations with desktop headroom.
2. Real Nemotron WebSocket and VibeVoice payload through LlamaSwap with the
   intended service account, permissions, timeouts, and recovery behavior.
3. Dictation during long Qwen work, rapid repeat read-aloud, speech while Higgs
   starts, and time-tracker backlog. Measure time to live draft and final text,
   verify 429 retry behavior, and ensure no repeated load/unload oscillation.
4. Cancel while queued/loading/streaming, worker crash, LlamaSwap restart, and
   coordinator restart with pending audio. Verify no recording loss or duplicate
   transcript delivery, and that the *backend* stops work after cancellation.
5. Multiple simultaneous recordings, long and silent recordings, abandoned
   clients, and idle/wake cycles with the updated health probes.
6. Monitor GPU pressure and alerts across a normal interactive session. Preserve
   rollback to the existing declarative service configuration and private audio.

These are material untested conditions, not a claim that every possible scenario
has been covered. The concrete reasons against a blind cutover are starvation,
uncalibrated memory budgets, private file access, and health/recovery integration.
They are reasons to integrate carefully, not reasons to retain two GPU managers.

## Dashboard finding

The running service reports GPU identity through `/api/hardware`, but its logs
say `rocm-smi: no GPU monitoring tool available` and `sysfs: not implemented`.
Its systemd PATH excludes the installed rocm-smi package. The intended declarative
fix is `systemd.services.llama-swap.path = [ pkgs.rocmPackages.rocm-smi ];`, followed
by a real rebuild and telemetry verification. This investigation did not apply it.
Audio passthrough will not manufacture LLM token usage fields: model activity and
GPU telemetry are the relevant indicators for speech even after centralization.

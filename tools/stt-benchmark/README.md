# Speech transcription comparison

Optimize final transcription accuracy independently of the streaming preview.
Voxtype is an existing baseline/client, not an architectural constraint.

Start with [the technologies and why they behave differently](TECHNOLOGY.md).
Measured results: [proprietary APIs and revision experiments](CLOUD_RESULTS.md),
[initial local Codex comparison](RESULTS.md),
[new 6m39s naiaclaw dictation](FRESH_RESULTS.md), and
[research, access, and system plan](RESEARCH.md).

This is a standalone Nix benchmark, not a change to running system services.
Model revisions and SHA-256 hashes are recorded in `models.json`; package inputs
come from this repository's locked nixpkgs. No Python packages are installed.
Recordings and raw results are private inputs, not committed benchmark fixtures.

## Cloud comparison

`run_cloud.py` uses Python's standard library and OpenRouter's dedicated
transcription or audio-chat endpoints. It reads the key from
`~/.config/stt-benchmark/openrouter.key` (mode 0600), never from committed files.
It records the prompt, audio hash, provider response, usage, and failures, but
omits audio base64 and credentials from request metadata. Existing outputs are
not overwritten: use a new arm name for a deliberate retry.

```sh
python3 tools/stt-benchmark/run_cloud.py \
  --model openai/gpt-transcribe --mode stt \
  --technology dedicated-asr-undisclosed \
  --clips ~/stt-tone-test.wav --output tools/stt-benchmark/results/cloud
```

Audio-chat models additionally accept `--vocabulary`, `--draft-dir` (one `.txt`
per clip), `--context` for direct project documents, and `--text-only` for a
correction control. Dedicated transcription
conditioning uses documented `--provider-options` JSON; OpenRouter's top-level
STT `prompt` is ignored. Parameter forwarding varies by provider. Nonempty
responses still need inspection: a refusal, an answer to the speaker, or an
incomplete transcript is not a successful transcription. HTML comparisons are
grouped by technology, with model identities retained for reproducibility.

## Record a reusable sample

Run `pw-record --rate 16000 --channels 1 --format s16 ~/stt-test-1.wav`, speak
naturally, then press Ctrl+C. Use a different filename for each recording.
Two or three minutes of ordinary project dictation with technical names,
numbers, filenames, pauses, and self-corrections is more useful than a carefully
read list. Include ordinary speech without vocabulary terms to measure false
insertions. Keep a separate note of the correct spellings of unusual names.

## Run

From the repository root:

```sh
nix-shell tools/stt-benchmark/shell.nix
nix build --impure --no-link --print-out-paths --expr \
  'import ./tools/stt-benchmark/default.nix { model = "granite-bf16"; }'
```

Pass the printed store path as `--model-dir`:

```sh
python3 tools/stt-benchmark/run.py \
  --server "$(command -v llama-server)" \
  --model-dir /nix/store/MODEL-PATH \
  --family granite --name granite-bf16 \
  --audio-dir .stt-bench \
  --vocabulary tools/stt-benchmark/vocabulary.txt \
  --output tools/stt-benchmark/results

python3 tools/stt-benchmark/score.py \
  --results tools/stt-benchmark/results --references .stt-bench
```

The shell uses the PC flake's package set, including its llama.cpp overrides.
The llama.cpp server path and exact launch arguments are retained in each
result. Server lifetimes are bounded by startup/request timeouts and cleaned up
on exit. Run GPU benchmarks sequentially. The launcher refuses to start when
existing VRAM usage exceeds 8 GiB. This check does not reserve GPU memory;
avoid concurrent large model loads while testing.

The default server arms use greedy decoding with a 4096-token context.
Audio-instruction models also support explicitly recorded sampling and reasoning
settings. Check long-recording/context failures before interpreting
outputs. Record latency as a secondary metric, including separate startup time;
the first request can include cold shader/audio costs.

## Quality evaluation

The recovered three Codex recordings total 106.32 seconds. Their `.ref.txt`
files are machine transcripts. `score.py` measures normalized word disagreement
with those references; it does **not** establish true word error rate or prove
that Codex is correct. Human verification of ambiguous spans is required.

For new samples, keep both a verbatim reference and, when needed, an intended
cleaned dictation reference. Score recognition independently of stylistic
cleanup. Track exact project-name/command/number accuracy, omissions,
hallucinated words, and unwanted changes to meaning in addition to overall WER.

Compare no vocabulary, a frozen small relevant vocabulary, a large vocabulary
with distractors, and an automatically selected subset. Hold recordings out
when tuning selectors or prompts. A list constructed from the correct answer
is an oracle diagnostic, not a deployable quality result.

## Jev experiment

`jev.py` prepares typed relevance questions using TypeSafe's documented API.
Supply an explicit text context file and vocabulary file. Without `--send` it
only saves the request. The default route is OpenRouter's dedicated
`/api/alpha/decisions` endpoint with model `typesafe/jev-1.13` and
`OPENROUTER_API_KEY`. `--provider typesafe` instead uses the direct API,
`TYPESAFE_API_KEY`, and `jev-1.13.0`. With `--send`, it sends the specified text
and saves the response and ranked terms. No audio is sent.

Jev relevance is not acoustic evidence. The final ASR pass must receive audio;
retain plausible phonetic alternatives and project terms even when a faulty
first transcript misses their spelling. Test multiple subset sizes on separate
tuning recordings. Do not assume the provider's probability calibration
transfers unchanged to vocabulary selection.

## Additional candidate runtime

`nix build --impure --no-link --print-out-paths --file tools/stt-benchmark/nemo.nix`
builds NVIDIA's NeMo-Speech.cpp ASR CLI with Vulkan. The pinned model catalog
also includes English Nemotron, multilingual Nemotron 3.5, and Parakeet TDT v3.
Those models use this CLI, not the llama.cpp launcher.

`transcribe.nix` builds transcribe.cpp with Vulkan, including Granite
NAR/TurboCTC, Canary-Qwen, and Cohere Transcribe. Use `run_transcribe.py` with
`--binary`, `--model-dir`, `--name`, `--audio-dir`, and `--output`. CLI runner
elapsed times include model loading; server runner request timings do not.

`audio.nix` builds audio.cpp with Vulkan and both VibeVoice ASR families. Use
`run_audio.py` with `--family vibevoice_asr` or `vibevoice_asr_streaming` and the
same CLI runner arguments. Its `plain`, `vocabulary`, and `beam4` arms distinguish
context conditioning from wider decoding. Each CLI call includes model loading.
See [RESEARCH.md](RESEARCH.md) for the broader candidate and access map and
[RESULTS.md](RESULTS.md) for what actually ran.

## Audio-based refinement experiment

The llama.cpp runner accepts `--candidate-results results --arms drafts` to
re-transcribe the original audio with candidate transcripts in the prompt.
The default candidates are Canary-Qwen, Cohere, and Granite NAR. The reference
transcript is never provided to the model. Choosing those candidates from this
small dataset makes this exploratory; validate the frozen configuration on
new, held-out recordings before claiming an ensemble improvement.

Generate the private listening/comparison page with:

```sh
python3 tools/stt-benchmark/report.py \
  --results tools/stt-benchmark/results --audio-dir .stt-bench
```

## Audio-instruction and punctuation experiments

Use `run.py --family audiochat` for Gemma 4 and Qwen3-Omni, selecting `plain`,
`prosody`, `drafts`, and `textdrafts` with `--arms`. The last two use the same
candidate prompt with and without audio. None receives the reference transcript.
The prosody prompt is generic and never includes the expected punctuation.
Models must run sequentially and fit fully on the GPU. Large CPU-offloaded models
are prohibited on this desktop: they make it lag and retain excessive RAM. The
runner rejects partial offload and combined weights/projector sizes above 16 GB.
Qwen3-Omni's Q4 checkpoint is therefore excluded from further local runs.
The historical Qwen-Omni reasoning run used `--reasoning --reasoning-budget 768
--max-tokens 2048 --temperature 0.6 --top-p 0.95 --top-k 20`; Gemma uses the
default greedy, non-reasoning configuration. `--startup-timeout 600` accommodates
cold loading while model installations are doing disk I/O. Historical partial
offload arguments are retained in result provenance, not supported for reruns.

Gemma 4's documented audio window is 30 seconds. Prepare lossless chunks of at
most 28 seconds, with boundaries chosen from quiet audio:

```sh
python3 tools/stt-benchmark/chunks.py split --audio-dir .stt-bench \
  --output tools/stt-benchmark/results/chunks28
```

Use that directory as `--audio-dir`, save runs in `results/chunk-runs`, and merge
each model/arm using `chunks.py merge --manifest results/chunks28/manifest.json
--results results/chunk-runs --output results --name MODEL --arm ARM` (paths are
relative to `tools/stt-benchmark` in this abbreviated example). Compare against
a recognizer run on the same chunks as well as its whole-recording baseline.
The manifest records source hashes and exact sample boundaries; no samples are
dropped. Chunking itself can change recognition quality.

`consensus.py` selects the least-disputed whole transcript from a frozen model
list without using references. It is transcript selection, not trained audio
deliberation. `diagnostics.py --results results --references ../../.stt-bench
--output results/punctuation.json` records concrete question-mark, emphasis, and
instruction differences. The HTML report also includes punctuation-sensitive
diffs; normalized word counts alone cannot measure those distinctions.

For the fresh long recording, VibeVoice uses `--max-tokens 4096`; the shorter
window models use the lossless chunk manifest. `project-vocabulary.txt` is the
one-term control against the frozen 18-term list. No accuracy percentage is
computed for that recording without a verified reference. The Gemma marker-loop
diagnostic can be reproduced with `--no-reasoning-budget --clips
stt-tone-test-part00 --max-tokens 256`; omitting the server budget did not fix it.

### Interactive evidence dashboard

Generate the private offline dashboard from the combined saved results:

```sh
python3 tools/stt-benchmark/dashboard.py --results tools/stt-benchmark/results/technology-comparison
```

Open `results/technology-comparison/dashboard.html`. It groups results by technology and pipeline strategy, with word and combined punctuation/case agreement, context diagnostics, elapsed time, reported API costs, failures, original audio and transcript diffs. Only complete three-clip configurations enter the aggregate charts. Scores measure disagreement with saved Codex transcripts, not human-verified accuracy. The long project recording remains unscored. Generated transcripts and audio stay in ignored `results/`; the generator does not embed API requests, credentials, or background project documents.

Local residency preference: GPU-resident models may remain loaded when desktop VRAM headroom is safe. Avoid persistent large CPU/system-RAM residency competing with browsers and builds; unload RAM-heavy models after use. GPU offload does not imply zero host RAM use, which must be measured separately.

# Speech transcription comparison

Optimize final transcription accuracy independently of the streaming preview.
Voxtype is an existing baseline/client, not an architectural constraint.

This is a standalone Nix benchmark, not a change to running system services.
Model revisions and SHA-256 hashes are recorded in `models.json`; package inputs
come from this repository's locked nixpkgs. No Python packages are installed.
Recordings and raw results are private inputs, not committed benchmark fixtures.

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

Each arm currently uses the whole recording and greedy decoding, with a 4096
token server context. Check long-recording/context failures before interpreting
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

Further contenders to assess include VibeVoice ASR, larger Voxtral and
audio-capable language models, and hosted recognizers where access is available.
A runtime/model in the catalog is not evidence that it has passed a benchmark;
report actual execution separately.

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

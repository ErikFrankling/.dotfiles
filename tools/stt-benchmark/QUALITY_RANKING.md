# Long-recording quality ranking

The private report at `results/quality-ranking/ranking.html` now leads with
technology, best observed setup, why it is useful, remaining errors, and speed.
Completed same-audio outputs are included, including actual Codex,
chunked recognition, vocabulary retrieval, audio/draft revision and text editing.
Older reports link to it. Within 0.5 word-agreement points, the displayed
representative favors content/name checks, then speed. This is an explicit
practical tie rule, not a statistical test.

The interactive matrix puts technology and model together with 50 comparison
columns. It shows every condition, including failed-quality Gemma outputs;
unchecking “Show all” keeps eight category representatives. Unknown features are
labelled unmeasured. Resource peaks include merged chunk runs.

## GPU-first follow-up

Gemma 4 12B Q8 completed four full-recording conditions through Vulkan on the
RX 7900 XT: the documented ASR prompt and a stricter verbatim prompt, each with
and without vocabulary. All used 16 audio chunks and requested full GPU
offload. The maker-prompt conditions scored 89.2/71.1 agreement; the vocabulary
condition included an empty chunk and recited unspoken keywords. The stricter
prompt added unwanted translations and other non-transcript material, yielding
zero clamped word agreement. That measures these unusable outputs, not zero
recognition ability or a proven ceiling for Gemma. More prompt/runtime work is
needed before treating this as a fair model-capability verdict.

The runner now verifies the selected GPU is exposed by the executable before
loading weights, explicitly selects Vulkan0, and rejects CPU-only builds. Large
CPU offload is a temporary, explicitly selected fallback experiment, not the
default. Process cleanup unloads models; GPU and available-RAM guards bound
experiments. GPU placement does not imply zero host RAM or swap.

Qwen3-Omni completed GPU-first temporary-offload tests: 95.4 plain and 97.7
with vocabulary, with four of seven question checks. Audio Flamingo Next ran
entirely on GPU: 89.4 plain and 88.9 with faithful instructions plus vocabulary.
It recovered only two question checks and missed project spelling. See
[FRONTIER_ROUND.md](FRONTIER_ROUND.md) for runtime repairs and memory evidence.

Qwen reconsideration of the original audio plus VibeVoice's draft scored 98.0,
with seven of eight content checks and six of seven question checks. It takes
180.6 seconds after the draft, still misses Claude Code and retains the
already/only error. This does not establish an improvement over VibeVoice.

Wispr Flow's official browser demo also produced a transcript of the first
349.952 seconds. It reversed the opening instruction to “I don't want to
implement it.” Its supported excerpt is shorter than the original recording,
so it is excluded from the full-recording ranking. This is evidence about the
web demo, not a completed comparison of all commercial desktop products.
Superwhisper's browser endpoint returned errors on two browser attempts.

The reference is an assistant-reviewed **best estimate**, as Erik requested.
It uses Gemini vocabulary18 as the coverage scaffold, compares other outputs,
corrects established names, and uses the earlier independent audio-excerpt checks.
It retains the tenant self-correction. The late passage is “service script is
already gonna give us”, despite many full-recording outputs saying only/solely.
Exact decisions and uncertainty are saved beside the full private reference.
No recording, private transcript, or credential is committed.

## Current practical choices

| Technology | Best observed implementation | Reference word agreement | Observed seconds |
|---|---|---:|---:|
| Audio-language model with context | Gemini Flash, 18 names | 99.1 | 22.8 |
| Audio plus draft reconsideration | Gemini Flash | 98.9 | 21.5 + draft |
| Whole-recording autoregressive ASR with vocabulary | VibeVoice, name-only | 98.1 | 52.0 |
| Text-only draft cleanup | Gemini Pro | 97.8 | 44.1 + draft |
| Dedicated hosted ASR | MAI, 18 names | 97.0 | 2.2 |
| Codex desktop, undisclosed backend | Best of three unhinted runs | 96.6 | 7.3 |
| Chunked autoregressive ASR | Qwen, name-only | 95.9 | 17.4 |
| CTC draft plus trained parallel editor | Granite NAR | 94.4 | 83.2 |

These are descriptive best-condition results, not architecture benchmarks.
The reference scaffold favors Gemini vocabulary18; its repeated same-condition
output scores 97.7, showing why decimals cannot establish a reliable winner.
VibeVoice compact context scores 98.0 in 42.1 seconds, effectively the same
word agreement as the 52-second name-only condition. No evidence justifies
choosing the slower local condition over it from this difference.

## What the numbers mean

`100 * (1 - normalized word edits / reference words)`, clamped at zero.
This is agreement with our provisional reference, **not human WER accuracy**.
Normalize um/uh, selected adjacent function-word stutters, contractions,
gonna/going to and common spelling/number formats. Preserve negation and
emphatic repetitions. Other harmless differences can still count; this metric
is not a complete measure of readable-dictation quality.

Also show, separately:

- Eight explicit content checks, including negation and the tenant reversal.
- Seven question-clause/mark checks. These mix wording and punctuation, and
  are not a validated tone-understanding score. Ambiguous “Right?” is excluded.
- Exact naiaclaw count and Claude Code presence.
- An approximate ordinary-word diagnostic excluding reference-aligned
  name-associated edit blocks. Mixed blocks can exclude nearby ordinary words.
- GPU/anonymous RAM where measured, tested context capacity, and streaming gaps.

The Qwen 18-name condition reverses the opening implementation instruction;
its score cannot qualify it as recommended. No arbitrary weighted judge score
is used. Bulk audio judge evaluations were not used: the GPT judge failed
hidden omission/corruption controls and mixed candidate quotes.

Timings are saved run observations, with differing warm-up/chunking conditions.
Jev and draft conditions do not include upstream preparation in their displayed
time. Local capacities distinguish measured successful context from failed GPU
headroom checks; cloud tested sizes are not claimed vendor limits.

## Reproduce

Keep `results/quality-ranking/reference.txt`, `reference-decisions.json`, and
`manifest.json` alongside the original result directories. Run:

```sh
python3 tools/stt-benchmark/quality_report.py
```

The output records include reference hash, source paths, normalized edit counts,
all checks, and original transcripts. This regenerates the complete offline HTML.
The reviewed private reference is intentionally frozen rather than automatically
changing whenever a new model result arrives.

Validation: matching-hash result records; reference self-distance, harmless
cleanup, preserved negation/emphasis, half-omission, actual intent reversal,
score bounds and audio-link checks. Headless Firefox screenshot inspected.
The follow-up loaded models in isolated benchmark processes; no deployed system configuration changed.

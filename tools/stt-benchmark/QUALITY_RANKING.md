# Long-recording quality ranking

The private report at `results/quality-ranking/ranking.html` now leads with
technology, best observed setup, why it is useful, remaining errors, and speed.
All 47 successful same-audio outputs are included, including actual Codex,
chunked recognition, vocabulary retrieval, audio/draft revision and text editing.
Older reports link to it. Within 0.5 word-agreement points, the displayed
representative favors content/name checks, then speed. This is an explicit
practical tie rule, not a statistical test.

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

Validation: 47 matching-hash result records; reference self-distance, harmless
cleanup, preserved negation/emphasis, half-omission, actual intent reversal,
score bounds and audio-link checks. Headless Firefox screenshot inspected.
No model loading or system-configuration change was required.

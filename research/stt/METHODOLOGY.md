# How to revisit the comparison

## What the existing scores establish

The principal recording is 398.739625 seconds of natural project dictation.
The final report contains 60 full-recording outputs and a provisional reference.
The 349.952-second Wispr excerpt is a separate corpus; do not rank it against
full-recording runs. Early short clips total 106.32 seconds and are regression
material, not an independent large evaluation set.

The reference is an assistant-reviewed composite: Gemini vocabulary18 supplied
the coverage scaffold; other models, repeated Codex runs, known spellings and
blind audio-excerpt checks informed corrections. Its decisions and unresolved
ambiguities are preserved in `results/quality-ranking/reference-decisions.json`.
Agreement between independent models is evidence, not a guarantee: multiple
models can share the same wrong word. The “already” versus “only/solely” passage
is an example where majority wording was rejected after audio checks.

The headline number is normalized word agreement with that reference, not
human-verified accuracy. The normalization permits selected filler/stutter,
contraction and number-format differences while preserving negation/emphasis.
Gemini's 99.1 score partly reflects scaffold affinity; a repeat scored 97.7.
Small decimal differences cannot establish an architecture or model winner.
The report's 0.5-point tie rule is a practical display rule, not significance.

Inspect content checks, spelling, question marks, omissions and invented words
separately. Seven question-clause checks mix wording and punctuation; they do
not measure general understanding of tone. A controlled statement/question
and calm/incredulous recording remains needed. Bulk LLM judging was rejected
after a judge failed hidden corruption/omission controls.

## Lessons worth retaining

- Compare technologies with the actual tested model beside each category.
  Model families can span dedicated ASR and audio-language models; “Qwen” alone
  does not identify an architecture, checkpoint, or capability.
- VibeVoice whole-audio Q8 with compact context took 42.1 seconds, scored 98.0
  reference agreement, and reached 16.87 GiB total VRAM / 1.44 GiB anonymous RAM.
  These are one-run observations, not guaranteed deployment requirements.
- Adding Qwen audio-plus-draft reconsideration took another 180.6 seconds and
  did not demonstrate better fidelity. More passes are not inherently better.
- Context can recover spellings and also distort speech. A roughly 6k-character
  README exceeded the local GPU guard; Aqua's compact-context condition reversed
  intent twice. Neither API context capacity nor a giant advertised context
  window proves useful transcription conditioning.
- The 18-name list is a favorable controlled condition, not proof that automatic
  retrieval finds arbitrary project symbols. Test distractors and held-out names.
  Jev was proposed to select vocabulary from broad project context and a draft;
  it must not discard a name just because the draft misspells it. Its quality
  benefit for production selection has not been established.
- Custom shallow-fusion phrase bias and wider beams did not beat the practical
  prompt setup. They are not implementations of unavailable trained methods.
- Gemma's bad outputs reveal problems in the tested prompt/runtime setup, not
  a proven ceiling for the model. Runtime failures and unavailable endpoints
  receive no invented quality score. Research papers without usable checkpoints
  remain untested candidates, not accomplishments.
- Codex is a useful product baseline, not ground truth. Consumer web demos and
  batch APIs do not reproduce every paid desktop product configuration.
- GPU residency still consumes host memory. Measure anonymous RAM, RSS, swap,
  and total VRAM separately; preserve compositor headroom and unload experiments.

## Next comparison procedure

1. Create a dated directory. Record the current production baseline and its
   exact model/runtime revisions, quantization, prompts and source commit.
2. Audit new primary model cards, papers and releases. Prioritize genuinely
   different training/architectures or context mechanisms; avoid dozens of
   nearly identical checkpoints without a specific hypothesis.
3. Reuse the original audio for continuity, then add new natural recordings
   held out from prompt/retrieval tuning. Include uncommon symbols, distractors,
   ordinary speech, negation, self-corrections, pauses and controlled prosody.
4. Run matched plain, frozen vocabulary, compact project context, and automatic
   retrieval conditions. Test larger context only within measured resource
   limits. Keep audio, prompt, parameters, seed where available, provider/model
   identity, failures and hashes for every arm. Never overwrite an old run.
5. Compare complete same-audio coverage. Keep chunked and whole-audio behavior
   explicit. Repeat strong candidates to reveal variability and caching effects.
6. Inspect pairwise text and listen to disputed spans without showing listeners
   a preferred answer. Preserve uncertainty. Version any reference correction
   and recompute every candidate against the same reference version.
7. Rank fidelity first. Report meaning errors, omissions, false insertions,
   exact names/numbers, punctuation, and readable-dictation suitability alongside
   word agreement. Do not hide a negation reversal behind a high average score.
8. Among practically comparable outputs, compare local availability, streaming,
   warm/cold/end-to-end latency, context usefulness and tested capacity, VRAM,
   anonymous RAM/swap, licenses, provider costs and operational reliability.
   Label unknowns instead of filling them with guesses.
9. Regenerate the offline matrix and selectable pairwise diff using the saved
   `quality_report.py`/`pairwise_view.py`. Preserve the reference, its decisions,
   manifest, raw responses and private audio alongside the report.
10. Write a new decision record: why switch or retain the deployed model, which
    errors changed, and what evidence is still missing. Validate the real T3
    capture-to-final path separately from batch model quality.

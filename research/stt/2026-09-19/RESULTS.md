# Dictation comparison — 2026-09-18–19

Start with [TECHNOLOGY.md](TECHNOLOGY.md) for mechanisms and their implications.
The later [cloud API round](CLOUD_RESULTS.md) adds proprietary references and
audio-versus-text revision controls. Tables below preserve the original local
measurements; model identities are reproducibility details, not distinct
technological categories.

Status: **initial local comparison complete; no final quality winner established**.
The new 6m39s naiaclaw recording and vocabulary/context findings are reported
separately in [FRESH_RESULTS.md](FRESH_RESULTS.md).
The initial comparison executed ten recognizers on the PC's RX 7900 XT; additional
audio-model experiments follow below. The input corpus is three recovered recordings, **106.32 seconds and
258 reference words**. References are saved Codex transcripts, not independently
verified truth. Names such as `naiaclaw` are not adequately represented.

## What the punctuation and meaning differences actually look like

These excerpts are actual outputs for `f30ba90b.wav`, not illustrative rewrites.
The Codex reference is still a machine transcript; listening is needed to resolve
ambiguous words independently.

| Output | Question and sentence boundary | Final instruction |
| --- | --- | --- |
| Saved Codex | “Why? There's no gate to review.” | “and live and test it.” |
| Cohere | “Why? There's no gates or review.” | “and live and tested.” |
| Granite NAR | “why? there's no gate to review.” | “and live and test it.” |
| Qwen3-ASR | “Why there's no gates or review?” | “and live and tested.” |
| Parakeet | “Wait, there's no gates or review you you managed…” | “and live, untested.” |
| Canary-Qwen | “Wait, there's no gates to review you you managed…” | “and live untested” |

Moving the question mark changes the sentence structure. Substituting “Wait”
changes the spoken word. “Untested” changes the instruction's meaning. A low
normalized word-edit count can hide all three kinds of problem. Granite NAR
matches these two spans but makes other errors, including “that it told you”
where Codex has “I told you”; matching an isolated phrase does not make it a
reliable overall winner.

Cohere, Granite NAR, and Parakeet preserve “always, always, always” with commas.
Canary retains the repeated words without those commas. This preserves lexical
emphasis, but punctuation alone does not establish that the recognizer inferred
intonation: it might infer the same formatting from text alone.

## Additional controls — 2026-09-19

- Reference-free minimum-disagreement selection among Canary, Cohere, and
  Granite NAR gives **11/258** edits, versus **12/258** for each individual.
  It selects Canary on the workflow clip and Cohere on the other two. This is
  only a one-word improvement on an exploratory three-clip set. The selected
  final instruction still says “and tested.” No new audio understanding occurs.
- Running Cohere on the same lossless ≤28-second chunks prepared for Gemma
  gives **15/258**, versus **12/258** on whole recordings. Chunk boundaries
  matter. Compare chunked audio models with this control as well as whole-clip
  recognizers. Joining the input chunks was verified to recover every original
  PCM sample exactly.
- The comparison HTML now shows punctuation/capitalization differences
  separately from normalized word differences. `diagnostics.py` records the
  concrete question, repeated-emphasis, and instruction checks after generation.

## Larger audio models — 2026-09-19

| Configuration | Edits / 258 reference words | Interpretation |
| --- | ---: | --- |
| VibeVoice-ASR Q8, whole recordings, greedy | 18 | Preserves more fillers; fixes the testing instruction but hears “Wait” instead of “Why.” |
| VibeVoice-ASR Q8, beam width 4 | 17 | Changes “gates” to “gate” on the emphatic clip; still says “Wait.” |
| VibeVoice-ASR-Streaming-7B Q8, file-fed streaming model | 27 | Misses the rhetorical question and introduces “Subaltern” and “shame something.” |
| Gemma 4 12B Q8, ≤28-second chunks, direct | 31 | More recognition errors, including “sub-unit” and “reaper.” |
| Gemma 4 12B Q8, explicit prosody prompt | 31 | Same transcript as plain mode on the key question clip; no aggregate gain. |
| Gemma 4 12B Q8, audio + Cohere chunk draft | 15 | Copies the draft's normalized words on all five chunks. No correction gain. |
| Gemma 4 12B Q8, same draft prompt without audio | 30 | Often adds “Candidate 1” or a transcript preamble. These are output-format failures, not new acoustic errors. |
| Qwen3-Omni 30B Thinking Q4, direct | 25 | Reasoning does not recover the rhetorical question or consistently recognize “subagent.” |
| Qwen3-Omni, explicit prosody prompt | 25 | Adds useful commas on the key clip without fixing its word errors. |
| Qwen3-Omni, audio + Cohere whole-clip draft | 18 | Copies two drafts; adds six normalized words on the scan clip. No reference-agreement gain over Cohere's 12. |
| Qwen3-Omni, same draft prompt without audio | 18 | Copies the drafts with “Candidate 1” prefixes, adding six formatting words overall. |

Gemma's plain and prosody outputs both say **“Why there's no gate to review?”**
and **“and live and tested.”** The audio-plus-draft output restores Cohere's
**“Why? There's no gates or review.”** but keeps **“and live and tested.”**
Matching the draft exactly does not establish that the model listened to resolve
ambiguity. The matched chunked Cohere control is 15/258, so the apparent gain
over Gemma alone comes entirely from supplying a better recognizer's words.

VibeVoice instead says **“Wait, there's no gates to review.”**, **“I told you to
change something.”**, and **“and live and test it.”** It also emitted a literal
`[Silence]` at the end of the workflow recording. Raw output is retained rather
than silently cleaned before scoring. Extra spoken fillers versus Codex's
cleaner wording require listening before they can be classified as errors.

These are native Vulkan port/quantization results, not measurements of every
precision or official runtime. Gemma used greedy decoding, reasoning disabled,
4096 context, and the same generic prompts across all clips. The final reference
was never included. Recorded GPU usage during Gemma inference was about 16 GB;
VibeVoice was about 12.5–12.8 GB. These are sampled readings, not proven peaks.

Qwen-Omni's direct output says **“Wait, there's no gates or review”**, **“They
told you”**, and **“and live and tested.”** Its prosody prompt adds the commas
in **“always, always, always”** and **“You, you…”**, but leaves those recognition
errors. On the workflow clip it says “Subversion” or “sub-thing” instead of
“subagent.” Its audio-plus-draft pass retains Cohere's normalized words on the
workflow and emphatic clips. On the scan clip it adds fillers/repetitions and
turns the draft's **“when was the most recent scan?”** into a period-ended
sentence. The added fillers are not independently verified acoustic errors;
the punctuation change is still a concrete output difference.

Qwen-Omni used 28 GPU layers, Q4_K_M weights, a Q8 audio projector, 4096 context,
temperature 0.6, top-p 0.95, top-k 20, seed 42, reasoning enabled with a 768-token
budget, and 2048 maximum completion tokens. All 12 requests completed normally.
GPU usage was sampled around 15.5–15.6 GB. This is one bounded reasoning and
sampling configuration, not the model's exhaustively tuned quality ceiling.

**CPU-offload policy correction:** Erik explicitly rejected the desktop lag and
RAM residency of large CPU-offloaded models. The follow-up Qwen-Omni multi-draft
run was stopped immediately after one completed clip; its partial results are
not a three-clip comparison. No `llama-server` remained afterward. Large models
must now fit fully on the GPU; the launcher rejects partial offload and weights
plus projector above 16 GB. Qwen-Omni's measurements above are historical, not a
recommended local configuration. The persistent server config already requests
full GPU offload, and its idle routing proxy used approximately 10 MB RAM.

The newer VibeVoice streaming checkpoint says **“Wait, there's no gates or review
you... you... you managed…”** and **“I told you to shame something… and live and
tested.”** It also produces “Subaltern” for “subagent” in the workflow clip.
It is not a better final pass in this test. This was prerecorded audio passed
through the streaming model's file runner; microphone/network latency was not
measured. Speaker IDs are kept in raw output/structured metadata and excluded
from spoken-text scoring. The model's runtime metrics total about 11.72 seconds
for the 106.32-second corpus, separately from model loading.

## Initial recognizer word agreement

Numbers below are normalized word edits against the same saved machine reference,
not verified transcription error rates. Case and punctuation are ignored (curly
apostrophes are normalized to straight apostrophes);
contractions are not expanded. This can penalize equivalent spoken forms.

| Recognizer/configuration | Edits / reference words | Disagreement |
| --- | ---: | ---: |
| Canary-Qwen 2.5B Q8 | 12 / 258 | 4.65% |
| Cohere Transcribe March 2026 Q8 | 12 / 258 | 4.65% |
| Granite Speech 4.1 NAR Q8 | 12 / 258 | 4.65% |
| Qwen3-ASR 1.7B BF16, small vocabulary in system context | 14 / 258 | 5.43% |
| Qwen3-ASR 1.7B BF16, no vocabulary | 15 / 258 | 5.81% |
| Granite Speech 4.1 AR BF16, with or without small vocabulary | 15 / 258 | 5.81% |
| Parakeet TDT v3 Q8 through NeMo-Speech.cpp | 24 / 258 | 9.30% |
| Granite Speech 5 TurboCTC Q8 | 29 / 258 | 11.24% |
| Nemotron English Q8: offline, simulated streaming, or vocabulary boost | 30 / 258 | 11.63% |
| Voxtral Mini 3B Q4, vocabulary prompt | 58 / 258 | 22.48% |
| Voxtral Mini 3B Q4, no vocabulary | 60 / 258 | 23.26% |

GLM-ASR Nano BF16 was also executed. Its reference preprocessing uses a 30-second
window; the 43.5- and 48.06-second whole-clip results are excluded. On the valid
14.76-second clip it disagreed on 10/40 words without vocabulary and 9/40 with
vocabulary. These are not directly comparable to the three-clip totals.

The new Parakeet result is a different runtime/quantization from the previously
saved Voxtype outputs. Do not interpret its difference as a regression in the
running Voxtype installation.

## Actual second-pass experiment

Granite AR was given the original audio plus transcripts from Canary-Qwen,
Cohere, and Granite NAR, without the reference. On one clip it copied/repeated
candidate text extensively. The aggregate edit count rose to 2720/258. Reject
this particular generic draft-prompt configuration; it does not demonstrate that
all audio-based refinement or trained deliberation methods fail.

Granite NAR's own trained audio-conditioned editing path completed normally.
This is materially different from asking an arbitrary speech model to reconcile
several external drafts.

## Runtime observations

All completed local runs released their model processes afterward. The final
VRAM check showed 3.2 GiB used, back near the desktop baseline.

For 106.32 seconds of audio, server request totals were approximately 3.0–3.6 s
for Granite AR and 4.6–4.9 s for Qwen3-ASR. CLI totals, **including separate model
loads for each clip**, were 7.17 s for Cohere, 10.50 s for Canary-Qwen, and 11.13 s
for Granite NAR. These timing definitions differ. Downloads, compilation, and
heavy disk I/O also overlapped some measurements; do not use these as a clean
latency ranking. Final quality is the primary selection criterion.

## Vocabulary selection and access

The small vocabulary is frozen in `vocabulary.txt`. It produced little change on
the original three-clip corpus, which has few difficult proper nouns. The new
recording's no-list / one-term / 18-term comparison shows substantial spelling
changes and some regressions; see FRESH_RESULTS.md. Large distractor lists and
Jev-selected lists remain untested, and no optimal vocabulary size is established.

Jev is available through OpenRouter's `typesafe/jev-1.13` decision endpoint.
`jev.py` supports that route and the direct TypeSafe API. No live Jev request was
made: no usable OpenRouter/TypeSafe credential was located. OpenCode's current
auth file lists OpenAI and OpenCode Go; its two credential tables are empty.
Broader credential-focused scans included user/root configuration, other agent
stores, project/mounted storage, Docker volumes, and process environments. Some
filesystem scans hit their time bounds, so this does not prove that no key exists
anywhere on disk or in an encrypted/external secret store.

## Next evidence needed

1. The new 6m39s project dictation is recorded and tested. Add a separate held-out
   sample and controlled statement/question pairs; confirm intended spellings
   and include ordinary speech to measure false term insertions.
2. Verify reference transcripts by listening; retain a held-out recording before
   tuning vocabularies, segmentation, or prompts.
3. Extend the completed no-list / one-term / 18-term tests to genuinely large
   distractor lists and automatic selection. Measure term recall **and false
   insertions**, not only WER.
4. Use Jev once a valid credential is available. Compare it against deterministic
   context/phonetic retrieval; relevance scores do not establish what was spoken.
5. Compare hosted recognizers when access is available and resolve or port the
   research systems identified in RESEARCH.md. VibeVoice, Gemma, and Qwen-Omni
   were exercised above; large CPU-offloaded models are now excluded locally.

The original recognizer shortlist remains a useful baseline. The new recording
adds whole-context VibeVoice with relevant vocabulary as a promising final-pass
candidate, without establishing a quality winner. Streaming preview is separate;
Nemotron and VibeVoice streaming models were fed recorded files, but live
microphone/network latency has not been measured.

Raw per-run JSON, server logs, audio-linked comparisons, and transcript files are
in the ignored `results/` directory. Run `report.py` to refresh `comparison.html`.
Pinned artifact URLs and hashes are in `models.json`; exact runtime commands and
audio SHA-256 hashes are included in each local result.

## Sources for contracts and remaining options

- [TypeSafe on OpenRouter](https://openrouter.ai/typesafe/jev-1.13)
- [OpenRouter decisions API](https://openrouter.ai/docs/api/api-reference/alphadecisions/submit-a-decisions-questions-and-answers-request)
- [TypeSafe primitives](https://docs.typesafe.ai/primitives)
- [Qwen's context/system-message implementation](https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/inference/qwen3_asr.py)
- [GLM reference preprocessing](https://github.com/zai-org/GLM-ASR/blob/main/inference.py)
- [Granite NAR model and intended accuracy tradeoff](https://huggingface.co/ibm-granite/granite-speech-4.1-2b-nar)
- [transcribe.cpp model documentation](https://github.com/handy-computer/transcribe.cpp/tree/be7a8b35e9ba2df20298bd26e32d53407c3bcbcd/docs/models)
- [NeMo-Speech.cpp CLI contracts](https://github.com/NVIDIA/NeMo-Speech.cpp/blob/07003daa7eefea542076310722ccaa89709ee3c3/docs/cli.md)

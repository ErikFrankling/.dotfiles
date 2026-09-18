# Initial dictation comparison — 2026-09-18

Status: **initial local comparison complete; no final quality winner established**.
Ten recognizers were executed on the PC's RX 7900 XT through three native Vulkan
runtimes. The input corpus is three recovered recordings, **106.32 seconds and
258 reference words**. References are saved Codex transcripts, not independently
verified truth. Names such as `naiaclaw` are not adequately represented.

## Observed word agreement

Numbers below are normalized word edits against the same saved machine reference,
not verified transcription error rates. Case and punctuation are ignored;
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
this corpus, which has few difficult proper nouns. Large-list, distractor, and
Jev-selected-list tests still need vocabulary-rich recordings and held-out
validation; no evidence currently establishes an optimal vocabulary size.

Jev is available through OpenRouter's `typesafe/jev-1.13` decision endpoint.
`jev.py` supports that route and the direct TypeSafe API. No live Jev request was
made: no usable OpenRouter/TypeSafe credential was located. OpenCode's current
auth file lists OpenAI and OpenCode Go; its two credential tables are empty.
Broader credential-focused scans included user/root configuration, other agent
stores, project/mounted storage, Docker volumes, and process environments. Some
filesystem scans hit their time bounds, so this does not prove that no key exists
anywhere on disk or in an encrypted/external secret store.

## Next evidence needed

1. Record several minutes of natural project dictation, including unusual names,
   commands, filenames, numbers, corrections, and negative-control ordinary
   speech. Preserve raw audio and confirm intended name spellings.
2. Verify reference transcripts by listening; retain a held-out recording before
   tuning vocabularies, segmentation, or prompts.
3. Compare no list, small relevant list, large distractor list, and selected list
   on the same audio. Measure term recall **and false insertions**, not only WER.
4. Use Jev once a valid credential is available. Compare it against deterministic
   context/phonetic retrieval; relevance scores do not establish what was spoken.
5. Expand to hosted recognizers, VibeVoice, larger audio models, and additional
   precision/runtime comparisons where they offer plausible quality gains. These
   have not been benchmarked and no global "best transcription" claim is made.

The practical shortlist remains Canary-Qwen, Cohere, Granite NAR, Qwen3-ASR with
context, and Granite AR with its supported keyword prompting. Streaming preview
is an independent component; Nemotron's streamed-file path was exercised, but
live microphone/network streaming latency has not been measured.

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

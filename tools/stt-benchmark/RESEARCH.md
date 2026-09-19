# Quality-first speech transcription: research and access map

Research date: 2026-09-19. This is a map of materially different approaches,
not a claim to have tested every published system or established a global winner.
Read [TECHNOLOGY.md](TECHNOLOGY.md) first for the architecture-based explanation;
the vendor catalog below is an access inventory, not a technology taxonomy.
The later [cloud round](CLOUD_RESULTS.md) now includes paid API tests using the
funded OpenRouter account. Earlier lack-of-credential constraints are superseded
for endpoints available there.
See [RESULTS.md](RESULTS.md) for the saved-Codex comparison and
[FRESH_RESULTS.md](FRESH_RESULTS.md) for Erik's new 6m39s project recording.
Papers' benchmark improvements below are
against their own baselines, **not against Erik's Codex dictation**.

## The concrete quality target

Preserve words, speaker intent, sentence boundaries, rhetorical questions,
repeated emphasis, project names, numbers, and commands. Optimize final quality
independently of streaming preview latency. A transcription that reads smoothly
but turns “and test it” into “untested” fails this requirement.

The original three recordings total 106.32 seconds; Erik later supplied another
398.74 seconds of project dictation without a reference transcript. The saved Codex text is an
unverified machine reference. Its underlying model/version and any cleanup are
not identified; it must not be relabeled as an OpenAI API model. Normalized word
edit counts ignore punctuation, so they miss the specific “Why?” distinction.
`diagnostics.py` records those concrete distinctions separately, without feeding
expected answers to the recognizers.

## Approaches that could materially improve fidelity

| Approach | What could change in the text | Evidence and access |
| --- | --- | --- |
| Whole-recording, context-aware speech recognition | A name introduced earlier can help later mentions; fewer mistakes at artificial cuts | [VibeVoice-ASR](https://huggingface.co/microsoft/VibeVoice-ASR) has public weights and a native Vulkan port. This is a stronger context test than another small CTC/transducer model. |
| Larger instruction-following audio models | Can consider project context, punctuation instructions, and ambiguous alternatives while receiving the audio | [Gemma 4 audio](https://ai.google.dev/gemma/docs/capabilities/audio), [Qwen3-Omni](https://huggingface.co/Qwen/Qwen3-Omni-30B-A3B-Thinking), and [Voxtral](https://arxiv.org/abs/2507.13264) have public weights. Larger size/reasoning does not itself demonstrate better verbatim transcription. |
| Supported vocabulary/context conditioning | “naiaclaw” can receive the intended spelling instead of a familiar phonetic substitute | The fresh recording demonstrates this with VibeVoice, but also exposes omissions and a Qwen-ASR negation regression under vocabulary conditioning. Qwen-ASR and Granite AR support context/keywords; proprietary options below offer additional controls. |
| Trained audio-conditioned editing | Correct an initial hypothesis using both sound and surrounding words | [Granite Speech NAR](https://huggingface.co/ibm-granite/granite-speech-4.1-2b-nar) is locally tested. Its trained editor is not equivalent to prompting an arbitrary ASR model to reconcile drafts. It did not show a dramatic gain on these clips. |
| Google-style two-pass deliberation | Correct uncertain words/proper nouns using encoded audio plus several first-pass hypotheses | [Google's deliberation research](https://research.google/pubs/deliberation-model-based-two-pass-end-to-end-speech-recognition/) reports improvements including proper nouns. No downloadable checkpoint or public endpoint for that exact experimental system was established. Chirp/Gemini access does not prove access to that architecture. |
| Diffusion-based audio editing | Revisit several words jointly, including using right-hand context, rather than committing once left-to-right | [Whisper-LLaDA / Diffusion-ASR](https://github.com/liuzhan22/Diffusion-ASR) publishes code and a checkpoint link. Its paper reports a 12.3% relative improvement on LibriSpeech test-other over its Whisper-LLaMA baseline; text-only LLaDA failed to improve it. Not a demonstrated gain over modern Codex or the local shortlist. |
| Adaptive diffusion decoding | Spend more denoising steps on uncertain words and stop early on easy ones | [dLLM-ASR](https://arxiv.org/abs/2601.17902) principally demonstrates comparable accuracy with faster decoding. It is a distinct research mechanism, not evidence of a higher accuracy ceiling. A 17.4 GB checkpoint was found on HF, but a verified author-linked turnkey inference package was not established. |
| Learned choice between an internal answer, an external recognizer, and rewriting | Avoid copying a bad draft; revise only when the learned system has reason to do so | [Speech-Hands](https://github.com/YukinoWan/Speech-Hands) publishes training code and static examples. Its README explicitly says **checkpoints are not included**. The demo displays recorded predictions, so it cannot evaluate these recordings. Reproducing it requires training, not just installing the skill. |
| Selective correction using internal model features | Improve uncertain entities without rewriting every already-correct word | [Listen to the Latents](https://arxiv.org/html/2609.02940v1) uses Phi-4-Multimodal and its preserved base LM. It finds that naive global rescoring can degrade results; targeted correction improves entity accuracy. The linked Space inspected here is a hidden-state visualization, not a ready service for running the paper's full Hybrid Search method on uploads. |
| Beam search, N-best rescoring, or minimum-risk/consensus decoding | Recover an alternative the model considered instead of accepting its first choice | An available local experiment is VibeVoice greedy versus beam search. Broader fusion requires genuine alternative hypotheses and appropriate scores. Several recognizers repeating the same error do not constitute independent evidence. No generic “ask an LLM to vote” accuracy guarantee. |
| Audio-aware punctuation restoration | Distinguish “Why? There's…” from “Why there's…?” using pauses and intonation as well as words | [Google's acoustic/text punctuation research](https://research.google/pubs/replacing-human-recorded-audio-with-synthetic-audiofor-on-device-unspoken-punctuation-prediction/) found benefits from acoustic input. This capability is scientifically plausible, but the exact research model is not established as downloadable. A text-only cleanup LLM cannot directly hear intonation. |
| Personal/domain adaptation | Learn Erik's pronunciation and recurring names, or train a recognizer/editor on corrected dictation | Requires a sufficiently varied, consented, accurately labeled corpus and a held-out test set. Three short clips cannot support a trustworthy fine-tuning claim. Vocabulary retrieval is the lower-cost first experiment. |
| Better input, segmentation, and acoustic processing | Avoid clipped word endings, noise masking consonants, and context loss between chunks | Preserve raw audio; test enhancement only where noise is actually a problem. Denoising can damage phonetic detail, so it is not automatically an improvement. Never silently discard audio beyond a model window. |

## Proprietary candidates worth comparing

These are a provider access inventory, not separate architectural categories.
See [CLOUD_RESULTS.md](CLOUD_RESULTS.md) for actual uploaded-audio experiments
and unresolved access limits. A benchmark key was created through Erik's
OpenRouter account with authorization. OpenRouter now exposes both dedicated
transcription and audio-chat endpoints; its live catalog was saved with the
private results. Services absent from that catalog still require separate access.

| System | Why it is relevant | Source / access |
| --- | --- | --- |
| OpenAI `gpt-transcribe` | Current file-transcription guide recommends it; accepts context, keywords, and language hints | [Official API guide](https://developers.openai.com/api/docs/guides/speech-to-text). Requires API access. Separate from the saved Codex product output. |
| Gemini 3.1 Pro / 3.8 Flash with audio | Flexible audio + context prompting; a candidate for re-listening, punctuation, and correction ablations | [Audio guide](https://ai.google.dev/gemini-api/docs/audio), [current models](https://ai.google.dev/gemini-api/docs/models). Reasoning/understanding capability is not proof of verbatim superiority. |
| Gemini 3.5 Transcribe | Dedicated transcription with custom vocabulary, word timestamps, and speaker support | [Current Google model catalog](https://ai.google.dev/gemini-api/docs/models). Distinct from asking a conversational Gemini model to transcribe. |
| Google Chirp 3 | Production ASR with adaptation controls; independent hosted acoustic baseline | [Chirp 3 documentation](https://docs.cloud.google.com/speech-to-text/docs/models/chirp-3). Requires configured Google Cloud access. |
| AssemblyAI Universal-3.5 Pro | Natural-language transcription instructions plus up to 1,000 keyterms | [Prompting and keyterms](https://www.assemblyai.com/docs/pre-recorded-audio/universal-3-5-pro/prompting). The old Universal-3 Pro documentation redirects to this version. |
| ElevenLabs Scribe v2 | Explicit keyterms; useful comparison for unfamiliar names and dictation formatting | [Keyterm guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/batch/keyterm-prompting). Requires ElevenLabs API access. |
| Microsoft MAI-Transcribe-2 | Phrase-list biasing and explicit verbatim versus clean output | [Microsoft documentation](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe). Requires Azure Speech resource/access. |
| Mistral Voxtral Mini Transcribe 2 | Dedicated batch service with context biasing and timestamps | [Offline transcription docs](https://docs.mistral.ai/studio/audio/speech_to_text/offline_transcription). Do not equate it with the older local Voxtral Mini 3B checkpoint we tested. |
| Soniox `stt-async-v5` | Structured contextual information and improved handling of names, codes, and formatting | [Models](https://soniox.com/docs/stt/models), [context](https://soniox.com/docs/stt/concepts/context). Requires Soniox API access. |
| Deepgram Nova-3 | Keyterm prompting gives a focused domain-vocabulary comparison | [Keyterm docs](https://developers.deepgram.com/docs/keyterm). Flux is principally the conversational streaming alternative; it is not automatically the best final pass. |
| Speechmatics Melia / Enhanced | Multilingual recognition and commercial deployment options | [Features and deployments](https://www.speechmatics.com/product/features-and-deployments). Commercial on-premises access is different from public downloadable weights. |
| Gladia Solaria-3 | Vendor focuses on noisy, accented European-language speech | [Release](https://www.gladia.io/blog/solaria-3-speech-to-text-model-for-european-languages). Its marketing benchmark is not our result. |
| Smallest Pulse Pro | Additional high-quality English batch candidate | [Model card](https://docs.smallest.ai/models/model-cards/speech-to-text/pulse-pro). Requires provider access. |
| xAI speech-to-text | Another independently trained hosted candidate | [API docs](https://docs.x.ai/developers/model-capabilities/audio/speech-to-text). No local accuracy result here. |

## Other open-weight candidates and actual local constraints

- **VibeVoice-ASR and VibeVoice-ASR-Streaming-7B:** public Q8 GGUFs are about
  9.86 GB each. Native Vulkan runtime was built using pinned Nix sources. The
  streaming model is included because it is a distinct newer checkpoint with
  context support, not because fast preview is being used to select final quality.
  [Model](https://huggingface.co/microsoft/VibeVoice-ASR-Streaming-7B),
  [native runtime](https://github.com/0xShug0/audio.cpp).
- **Gemma 4 12B:** Q8 model about 12.67 GB plus 0.18 GB audio/vision component.
  Its documented 30-second audio limit requires segmentation. Tests start with
  4096 context; chunk boundaries are selected from audio energy, never the answer.
  This is a local audio-instruction model, not just a text cleanup model.
- **Qwen3-Omni 30B-A3B Thinking:** Q4 weights are about 18.56 GB plus 1.33 GB
  Q8 projector. Full GPU loading would exceed the safe budget alongside the
  desktop and inference buffers. A partial-offload experiment was completed,
  but Erik explicitly rejected the CPU/RAM impact. It is excluded from further
  local use; large models must fit fully on the GPU. Historical results remain
  available, but the benchmark now rejects that configuration.
- **Voxtral Small 24B:** public audio-language weights; more capable sibling
  of the old 3B checkpoint, but still a related architecture. Worth a later
  scaling comparison if larger audio models show a benefit. Not newly benchmarked.
- **Phi-4-Multimodal:** important because the selective-correction paper uses
  it. Its full research algorithm needs access to internal activations and the
  preserved text model, beyond the generic llama.cpp chat endpoint.
- **Kimi-Audio 7B, Step-Audio 2 mini, Step-Audio-R1/R1.1:** additional open
  audio-understanding/reasoning families. The R1.1 published weights total about
  67 GB, and its [reference setup](https://github.com/stepfun-ai/Step-Audio-R1)
  targets multiple NVIDIA GPUs. A compatible GPU-quantized or remote-GPU port
  would be additional engineering work, not an already functioning native AMD
  installation. Large CPU offload is explicitly excluded on Erik's desktop.
  [Kimi source](https://github.com/MoonshotAI/Kimi-Audio),
  [Step-Audio2 source](https://github.com/stepfun-ai/Step-Audio2).
- **StepAudio 2.5:** a newer [technical report](https://arxiv.org/abs/2605.23463)
  covers ASR, TTS, and realtime regimes. A verified downloadable ASR checkpoint
  was not located in this investigation; do not substitute its TTS model.
- **FireRedASR2S:** public ASR, punctuation, language-identification and VAD
  system focused on Chinese, English, and code-switching. It is a useful
  integrated pipeline candidate, rather than evidence of a unique English
  dictation breakthrough. [Source](https://github.com/FireRedTeam/FireRedASR2S).
- **Whisper-LLaDA:** the published setup includes CUDA-specific k2 dependencies,
  a Whisper encoder, LLaDA-8B, and an adaptation checkpoint. The inference script
  truncates to 30 seconds. Running it fairly here requires a compatible Nix
  environment and a measured quantization/offload path; installing plain LLaDA
  would not reproduce the audio-conditioned system.
- **Speech-Hands:** missing released trained weights are the blocker; another
  generic prompt on Qwen-Omni would not be an honest test of the paper's model.

## How to establish that it hears tone

The existing “Why?” clip provides a useful output check but cannot isolate
acoustics from linguistic expectations. Use paired recordings of identical words
with different intonation, such as “You're deploying today.” / “You're deploying
today?” and “Really.” / “Really?”. Add rhetorical questions, emphatic repetition,
and contrasting pauses. Keep the intended punctuation separately; never include
it in the model prompt. Compare audio-aware output to a text-only punctuation
baseline. Listen to ambiguous spans before treating the Codex reference as truth.

Punctuation can preserve some tone, but emotion tags, sarcasm explanations, and
rewritten prose are separate products. The desired final dictation should retain
the speaker's words, using punctuation only where supported, rather than inventing
an interpretation. A model describing someone as angry does not demonstrate that
it faithfully transcribed their request.

## What remains necessary beyond these local tests

Separate provider access for services absent from the cloud round; released/ported research
systems where noted; more real dictation containing difficult names; corrected
reference transcripts; a held-out evaluation; vocabulary retrieval and false-term
insertion tests; and paired-prosody recordings. Jev has now been tested as a
text-based vocabulary selector in the cloud round, not an acoustic verifier. No observed result establishes
perfect transcription or that extra reasoning always improves it.

## Provisional system to build after selecting the final pass

1. **Capture and retain the original audio.** Keep a local WAV, timing, active
   project identifier, and the preview/final transcripts. This creates reusable
   evaluation examples and permits correction without re-recording. Capture is
   independent of Voxtype; a hotkey client can use a local transcription server.
2. **Stream a provisional transcript.** Use a lightweight recognizer for early
   feedback. Mark it provisional and allow the final pass to replace it. Preview
   speed does not determine which model gets the final word.
3. **Gather rich project context, then adapt it to the final model's capacity.**
   Preserve project documents, recent task context, known names and spellings,
   and the provisional transcript as separate sources with provenance. Prefer
   testing a capable audio-language model with that context directly: a short
   vocabulary discards relationships and meaning. For a recognizer that only
   accepts limited vocabulary hints, use Jev to rank candidates from the broad
   context and preview, with a budget matching that endpoint's actual limits.
   The 24-term experiment is not a universal production limit. Canonicalize
   spellings and retain a route for phonetic alternatives absent from a faulty
   preview. Compare direct rich context, large unfiltered lists, and selected
   lists on the same recordings, including false insertions on ordinary speech.
4. **Run the strongest validated final recognizer.** Give it the original audio
   and supported context. Preserve long-recording context where the model allows
   it; use explicit, lossless segmentation where it does not. Store model version,
   prompt, vocabulary, decoding settings, and output alongside the audio.
5. **Reconsider uncertain spans only if testing supports it.** A second
   recognizer can identify disagreements; an audio model can examine the original
   span plus surrounding sound and alternatives. Do not automatically rewrite all
   text or assume agreement means correctness. First demonstrate that the editor
   fixes more mistakes than it introduces on held-out dictation.
6. **Preserve meaning when formatting.** Punctuation may reflect pauses and tone;
   repeated emphasis and actual spoken instructions should survive. Keep optional
   prose cleanup separate from the faithful transcript, with an inspectable diff.
   A fluent sentence that changes “and test it” to “untested” is a regression.
7. **Deliver the final text and retain corrections for evaluation.** Archive
   user corrections as labels, then reevaluate frozen configurations on new
   recordings. Fine-tuning becomes justified only when enough varied corrections
   show a recurring failure that retrieval or acoustic reconsideration cannot fix.

This architecture does not require a voting stage or an audio editor to ship.
Either may be omitted if it lowers fidelity. Hosted versus local execution is a
quality/access decision to make from comparable tests, not a premise imposed by
the current desktop setup.

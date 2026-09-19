# Cloud transcription and vocabulary selection, by technology

Date: 2026-09-19. Actual paid API requests through Erik's OpenRouter account,
not vendor benchmark claims. Thirteen audio model endpoints were exercised,
plus TypeSafe Jev. Account-reported spend after this round: **$3.490**. The
separate benchmark key has a $20 total limit and expires 2026-10-19; it is stored
outside the repository with owner-only permissions. No large local model ran.

The corpus is the original three Codex clips (106.32 seconds, 258 reference
words), plus the 398.74-second naiaclaw recording. The saved Codex text is an
unverified machine reference, not human truth. The new recording has no reference.
No experiment received the Codex reference as input. Revision experiments use
the new dedicated API's plain output as their draft. Audio instructions are data,
not authorization to perform the actions spoken in them.

Read [TECHNOLOGY.md](TECHNOLOGY.md) for the architecture explanation. Private
audio, exact requests, outputs, errors, usage, and hashes are under `results/cloud/`.
The combined listening page is `results/technology-comparison/comparison.html`.

## 1. Dedicated speech recognition

These endpoints specialize in transcription. Their full encoder/decoder and
training recipes were not established, so they are not labeled CTC, diffusion,
or deliberation based on brand. Specialized transcription behavior is distinct
from a general conversational model receiving a transcription instruction.

The closest result to saved Codex is 5 word edits out of 258, versus 12 for
the closest individual local recognizers. That is **better reference agreement**,
not proof of better-than-Codex accuracy. Its workflow clip matches all normalized
reference words. The remaining differences are concrete:

| Saved Codex | Dedicated API output | Consequence |
| --- | --- | --- |
| “You you managed…” | “You managed…” | Removes a repetition |
| “and live and test it” | “and live and tested” | Changes imperative wording |
| “…a separate page in the site” | “…a separate site, separate page in the site” | Adds two words relative to saved reference; needs listening to determine correctness |
| “Why? There's no gate to review.” | Same wording and question boundary | Preserves this rhetorical-question structure |

An 18-term vocabulary request retains 5/258 disagreement overall but changes
which words differ; aggregate equality does not mean identical output.

Reproducibility table within this technology group (not an architecture ranking):

| Endpoint | Short clips completed | Word edits / 258 |
| --- | ---: | ---: |
| OpenAI gpt-transcribe | 3 | 5 |
| Deepgram Nova-3 | 3 | 22 |
| Fish Transcribe-1 | 3 | 15 |
| Google Chirp-3 | 3 | 15 |
| Meta Muse Voice Transcribe-1.0 | 3 | 14 |
| Microsoft MAI-Transcribe-2 | 3 after retry | 23 |
| Mistral Voxtral Mini Transcribe | 3 | 17 |
| xAI Grok STT-1.0 | 3 | 14 |

All eight also produced a long-recording transcript, but Chirp required eight
lossless chunks of at most 55 seconds after the whole-recording request failed.
Its chunked result is labeled separately. Microsoft initially returned 429 and
succeeded on a bounded retry. Meta succeeded after Erik completed the required
age confirmation himself.

## 2. General audio-understanding / instruction-following models

These accept sound plus arbitrary instructions. This allows vocabulary and
revision experiments, but also introduces conversational behavior: a model can
refuse, answer the speaker, or rewrite. Broad reasoning capability is not a
guarantee of faithful transcription.

| Endpoint | Short clips completed | Word disagreement |
| --- | ---: | ---: |
| GPT Audio, plain | 3 | 9/258 |
| Gemini 3.1 Pro Preview, plain | 3 | 27/258 |
| Gemini 3.8 Flash, plain | 3 | 24/258 |
| Inkling, plain | 3 | 20/258 |
| Muse Spark 1.3 | 1 of 3 | 4/40; not comparable to a complete-corpus score |

Muse Spark claimed no audio had been received on one clip and returned no final
text on another, despite audio being included. It did transcribe the long clip.
OpenRouter itself warns its audio support is incomplete. Inkling's long request
failed twice after about a minute, returning whitespace rather than valid JSON;
this is an access/runtime failure, not an intrinsic accuracy measurement.

Examples on the short rhetorical-question clip:

- Dedicated recognition: **“Why? There's no gate to review.”**
- Audio-understanding, plain Flash: **“Wait, there's no gates to review.”**
- Audio-understanding, plain Pro: **“I totally just changed something.”** where
  saved Codex has **“I told you to change something.”**

These show that grammatical output and more reasoning do not guarantee the
right words. They do not isolate architecture from training, decoding, or prompts.

## 3. Audio-conditioned reconsideration versus text-only editing

Both receive the same dedicated recognizer draft and frozen 18-term vocabulary.
The audio arm additionally receives the original recording. These are prompted
correction experiments, not a reproduction of a trained deliberation model.

| Mechanism / implementation | Short-clip result |
| --- | --- |
| Original dedicated draft | 5/258 |
| Audio + draft, Flash | 10/258 |
| Audio + draft, Pro | 15/258 |
| Audio + draft, GPT Audio | 2/218 on two clips; refuses the third |
| Text-only draft, Flash | 2/218 on two clips; refuses the third |
| Text-only draft, Pro | 2/218 on two clips; empty final output on the third |
| Text-only GPT Audio | Endpoint rejects requests without audio input/output |

The two easier clips already account for 2/218 in the dedicated draft. Matching
that score while failing the difficult clip is not an improvement. On the long
recording, GPT Audio with vocabulary alone corrected some project spellings,
but with a draft it retained the draft's wrong “Nyakla” spelling. Draft anchoring
is a plausible explanation; this experiment does not establish its internal cause.

## 4. Vocabulary conditioning on the long project recording

The 18 terms were frozen before the fresh recording. Counts below are
case-insensitive exact-word occurrences of `naiaclaw`, **not verified recall or
accuracy**. Nine is an observed output count, not a human-labeled denominator.

| Mechanism / implementation | Plain | With 18 spellings | Other concrete behavior |
| --- | ---: | ---: | --- |
| Dedicated recognition, OpenAI | 0 | 4 | Opening still “NiaClaw”; omits the other tool phrase in “several Codex sessions” |
| Dedicated recognition, Microsoft | 0 | 1 | Other names are attached to preceding words, e.g. “thenaiaclaw”; retains “Claude Code” |
| Audio instruction, GPT Audio | 0 | 3 | Opening gets `naiaclaw` and `Claude Code`, but spelling drifts later |
| Audio instruction, Flash | 0 | 9 | Gets `naiaclaw` and `Claude Code`; retains “now I want to implement it” |
| Local autoregressive long-context ASR, VibeVoice | 0 | 9 | Names improve but “Claude Code” is lost in the tool phrase |

Flash with 18 spellings is a useful **contextual cloud reference** for the new
recording. It is not a demonstrated global winner: it performs worse on the
short rhetorical-question clip and the long recording has no verified reference.

Both the dedicated whole-recording API and contextual audio model preserve
“will that be enough information to set up a new tenant?” The earlier local
chunked output split this into “set up? A new tenant.” This supports preserving
context and reconsidering chunk boundaries. It does not prove tone sensitivity;
the controlled identical-words/different-intonation recordings are still absent.

## 5. Jev: broad project context → compact vocabulary

Erik's proposed role is a selector: give Jev a large body of project context and
a noisy first transcript, and have it select spellings for the final recognizer.
The initial 18-term relevance test was only a smoke test, not this architecture.

The proper follow-up uses:

- **16 tracked naiaclaw documents**, with code blocks, URLs, email addresses,
  and credential-shaped literals omitted; about **72,781 JSON characters**
  including the rough transcript and metadata.
- **400 candidate terms**, mechanically drawn from project documents and source
  filenames plus the frozen 18-term user vocabulary. Many are irrelevant.
- The existing **unconditioned local transcript** as a preview surrogate. This
  was batch-produced; this experiment does not measure an actual live stream.
- One independent Jev inclusion question per candidate. Full context is repeated
  across 13 batches of at most 32 candidates because the all-at-once call exceeded
  the token limit. No context was silently truncated.
- **Top 24** spellings selected by probability, fixed before seeing these scores.
  The final audio model receives those spellings and the original audio, not
  all the project documents.
- A controlled selector comparison using the same 400 candidates and questions,
  but only the preview/active-project metadata, without the project documents.

Full-context selection took **7.83 seconds** sequentially, costing about **$0.0122**.
It can be parallelized later; that latency has not been measured here.

| Candidate | Preview-only rank / probability | With project documents |
| --- | --- | --- |
| `naiaclaw` | 28 / 0.24 | 1 / 0.82 |
| `Planet9` | 20 / 0.32 | 5 / 0.72 |
| `Claude Code` | 16 / 0.40 | 126 / 0.11 |
| `OpenClaw` | 250 / 0.06 | 31 / 0.28 |
| `Hyprland` | 395 / 0.03 | 397 / 0.03 |

The pool also contains `NaiaClaw`, a casing duplicate. Preview-only selection
retained that variant at rank 23, so rank 28 for lowercase `naiaclaw` is **not**
proof that the concept was absent from its final hints. Canonicalization matters.

Downstream results using the same audio-understanding endpoint:

| Hints sent to final recognizer | `naiaclaw` occurrences | Tool phrase |
| --- | ---: | --- |
| Frozen 18 terms | 9 | “Claude Code and Codex sessions” |
| Full 400-term list | 9 | “Claude Code and Codex sessions” |
| Jev 24, preview only | 9 | “Claude Code and Codex sessions” |
| Jev 24, full project context | 9 | “Cod- Code and Codex sessions” |

All these runs retain the positive “now I want to implement it” statement.
The full-context shortlist also produced excessive line breaks. There is no
human-verified whole-recording score, so the table describes specific properties,
not overall accuracy. No clear downstream quality advantage for Jev's full-context
shortlist is established on this recording. It does demonstrate the intended
large-context filtering pipeline, including both a useful project-name effect
and a relevant-name omission.

The next selector design should canonicalize duplicate spellings, keep a path
for phonetic alternatives from the preview, and separate specialized names from
generic code identifiers. Tune and test on held-out recordings; do not repair
this shortlist using knowledge of the desired answer and call that a fair result.

## 6. Direct rich project context plus audio

Erik's preferred route is to let a capable audio-language model consume rich
context directly. Jev should compress context only where a model's vocabulary
input is constrained, with a budget appropriate to that model.

This round therefore also sends all **16 documents directly with the original
398.74-second audio**. The document-only background is 67,696 JSON characters.
The documents include `naiaclaw` and `Planet9`, but contain no exact `Claude Code`
phrase. A second arm additionally includes the unconditioned local preview and
all 400 vocabulary candidates: the same information available to the selector,
without discarding it into a shortlist. The prompt says that background is
reference data, that the speaker may contradict the current design, and that
facts from documents must not be inserted merely because they are present.

| Direct-context input | Final model | Observed output |
| --- | --- | --- |
| Documents + original audio | Flash | 9 `naiaclaw` occurrences and “Claude Code”; excessive line breaks |
| Documents + original audio | Pro | 9 `naiaclaw` occurrences and “Claude Code”; normal paragraphs |
| Documents + preview + 400 terms + original audio | Flash | 10 `naiaclaw` occurrences and “Claude Code”; includes an extra project-name repetition relative to the other runs |
| Documents + preview + 400 terms + original audio | Pro, default reasoning | Incomplete at both 16,384 and 32,768 total output-token limits; excluded |
| Documents + preview + 400 terms + original audio | Pro, explicitly low reasoning, 32,768 output budget | Complete in 21.2 seconds; 11 name occurrences and “Claude Code,” but also sound-event text and possible over-biasing |

The larger Pro request consumed 31,457 of 32,764 generated tokens in reasoning,
leaving an incomplete 952-word transcript after 181.9 seconds. Increasing the
total budget alone did not resolve it. This is a decoding/configuration failure,
not evidence that the complete rich-context transcript would be inaccurate.
Gemini 3 uses thinking levels rather than a precise hard reasoning-token cap;
[OpenRouter documents this distinction](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens).
A bounded retry with explicitly low reasoning completed using 1,704 reasoning
tokens. It writes “Naiaclaw build” where other outputs have “Naya build,” includes
an extra project-name repetition, and adds an unintelligible-speech tag. Without
a verified reference, those differences require listening; more exact project-name
occurrences are not automatically an improvement. This is a working configuration
test, not a claim that lower reasoning maximizes quality.

Both document-only runs retain “now I want to implement it” and the full question
“will that be enough information to set up a new tenant?” The Flash full-input
arm writes “Correct. Right.” where its 18-term vocabulary arm writes
“Correct? Right?” for the same recording. That is another reason to evaluate
punctuation separately rather than infer reliable tone recognition from fluent
text or additional context.

The capability to accept and use substantial project documents with audio is
available now. These examples demonstrate useful context-conditioned outputs;
they do not establish that adding every available document always improves
fidelity or that this is a perfected context-aware transcription system.

## What these tests establish, and what remains missing

We now have stronger proprietary reference outputs and a functioning API harness.
The evidence favors testing **specialized recognition and audio-language models
with direct rich context**, and using
audio-based correction only where measured benefits justify it. Blindly chaining
an increasingly capable conversational model did not improve the short corpus.

This is not an exhaustive world-state-of-the-art evaluation. AssemblyAI,
ElevenLabs, Soniox, Speechmatics, Gladia, Smallest, and Gemini's separate dedicated
transcription offering were not exposed in the inspected OpenRouter STT catalog
and have not been tested with separate provider access. Their documented access
routes remain in [RESEARCH.md](RESEARCH.md). Unreleased research checkpoints and
unported diffusion systems also remain untested; hosted access is not evidence
of access to their internal algorithms.

Human-corrected references, paired-tone recordings, repeated trials, held-out
prompts, and vocabulary false-insertion checks remain necessary before declaring
one configuration the final production choice.

Primary API sources: [OpenRouter dedicated STT](https://openrouter.ai/docs/guides/overview/multimodal/stt),
[audio input](https://openrouter.ai/docs/guides/overview/multimodal/audio),
[TypeSafe structured state](https://docs.typesafe.ai/concepts/state),
[TypeSafe question API](https://docs.typesafe.ai/api),
[Microsoft vocabulary/style options](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe),
[Muse Spark audio limitation](https://openrouter.ai/meta/muse-spark-1.3).

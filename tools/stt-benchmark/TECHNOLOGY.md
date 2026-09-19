# Speech transcription, organized by technology

Model names identify implementations; they do not explain their behavior.
Architecture, training objective, audio context, vocabulary conditioning, and
decoding strategy are separate dimensions. A single system can combine several
of the techniques below. These are not rungs on an automatic quality ladder.

## 1. Acoustic alignment: CTC and transducers

An audio encoder extracts evidence from the sound. CTC predicts symbols aligned
to audio frames and collapses blanks/repetitions. Transducers also condition
predictions on previously emitted text; duration variants explicitly model
advancing through audio. Streaming configurations restrict future audio to
provide immediate output, but these architectures are not inherently streaming
or incapable of punctuation. Their encoder, training, and lookahead matter.

Local implementations tested: Granite Turbo CTC, Parakeet TDT, Nemotron.
The tested transducer output included “live, untested” where saved Codex had
“live and test it.” This illustrates an acoustically confusable but consequential
error. It does not prove transducers uniquely cause that error.

## 2. Autoregressive speech-to-text

An audio encoder feeds a decoder that generates the transcript left to right,
conditioning on sound and earlier output. The decoder may be speech-specific
or derived from a language model. Language priors help resolve unclear sounds,
but can favor familiar phrases over rare project names. Ordinary generation
does not go back and edit already emitted words, even if the audio encoder has
access to later sound.

Local implementations tested include Canary-Qwen, Cohere Transcribe, Qwen ASR,
Granite AR, and VibeVoice ASR. VibeVoice's ASR decoder is autoregressive; do not
confuse it with the diffusion audio head used by related speech-generation work.
[Microsoft source](https://github.com/microsoft/VibeVoice).

**Long context is an additional capability, not a separate decoder architecture.**
The whole-recording recognizer produced “enough information to set up a new
tenant?” where independently decoded chunks produced “enough information to
set up? A new tenant.” The cut really fell there. This suggests a segmentation
problem, but the comparison also changes models and therefore does not isolate
architecture or context as the sole cause.

## 3. Trained bidirectional transcript editing

A recognizer makes a draft, then a trained editor receives both acoustic
features and the draft, with access to words on both sides of each position.
IBM's tested NAR implementation predicts copy/insert/delete/replace edits in
one parallel pass. It is neither a generic cleanup prompt nor iterative diffusion.
Its maker positions it for efficiency and recommends its AR sibling when
accuracy is the main concern. [IBM architecture](https://huggingface.co/ibm-granite/granite-speech-4.1-2b-nar).

It got “why? there's no gate to review” on the short clip, but other words still
went wrong. The architectural ability to revise is real; a large accuracy gain
on these recordings was not established.

## 4. Instruction-following audio-language models

These models accept audio and flexible text instructions. This permits supplying
project context, asking for faithful transcription, or providing drafts for
reconsideration. General audio understanding and reasoning training do not
guarantee verbatim accuracy. Responses can also be affected by conversational
behavior such as answering, rewriting, or refusing instead of transcribing.

Local examples tested: Gemma audio, Qwen Omni, Voxtral. Cloud experiments include
Gemini, GPT Audio, Inkling, and Muse Spark. Their undisclosed internals should not
be inferred from their product names. See [cloud results](CLOUD_RESULTS.md).

Giving an arbitrary audio-language model a draft is **prompted revision**.
Google's trained deliberation research instead combines audio and multiple
hypotheses with a specifically trained second pass. Testing the former does not
reproduce or disprove the latter. [Deliberation research](https://research.google/pubs/deliberation-model-based-two-pass-end-to-end-speech-recognition/).

## 5. Diffusion / masked parallel refinement

The transcript is developed through repeated audio-conditioned refinement of
masked or uncertain text positions. Unlike ordinary left-to-right generation,
later words can help revise earlier positions within the refinement process.
This could help ambiguous names and phrases, but more iterations need not
improve fidelity. Whisper-LLaDA reports gains over its own baseline, not over
Erik's Codex dictation. It has not been ported and benchmarked here.
[Research and implementation](https://github.com/liuzhan22/Diffusion-ASR).

## Capabilities layered onto these architectures

| Technique | What changes | What can go wrong / evidence here |
| --- | --- | --- |
| Whole-recording context | More surrounding sound and discourse is available | Fewer artificial sentence cuts; long context alone does not identify a rare spelling |
| Vocabulary biasing | Raises the plausibility of supplied names | Corrects naiaclaw in some runs; can omit words or change unrelated phrases |
| Vocabulary retrieval / Jev | Selects which spellings reach the recognizer | Text selector cannot hear the name; preliminary transcript errors can exclude the right term |
| Beam / N-best search | Retains multiple candidate continuations | More search through a mistaken distribution still selects mistakes; beam-4 changed only one word here |
| Consensus | Combines independent recognizers' hypotheses | Shared errors survive; our three-way selection improved agreement by only one word |
| Audio-aware punctuation | Uses acoustic cues alongside words | Correct “Why?” may reflect syntax rather than intonation; paired-tone recordings are still needed |
| Text-only punctuation | Uses the transcript's syntax and meaning | Cannot recover acoustic cues omitted by recognition |
| Personal adaptation | Learns the speaker/domain from labeled examples | Requires accurate labels and held-out evaluation; not yet trained here |

The observed vocabulary regression from “now I want to implement it” to
“I don't want to implement it” shows why correct name spelling is insufficient.
That is a measured conditioning effect in a particular local run, not a universal
property of vocabulary lists.

## Hosted dedicated recognition: disclose what is unknown

Cloud hosting is not an architecture. The dedicated transcription APIs are
grouped separately when their precise encoder/decoder and training recipe are
not established. Their specialized task and exposed controls are known; a claim
that a particular proprietary endpoint uses CTC, diffusion, or deliberation
requires separate evidence. The saved Codex product transcript also has an
unidentified underlying recognizer and cleanup pipeline.

The meaningful comparison is which words and punctuation survive, which context
or correction intervention changes them, and whether the output preserves the
recording. A model's release date or general reasoning benchmark cannot answer
that by itself.

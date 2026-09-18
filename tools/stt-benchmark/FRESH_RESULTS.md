# Naiaclaw dictation — 2026-09-19

Input: Erik's new `~/stt-tone-test.wav`, **398.739625 seconds**, mono 16 kHz.
SHA-256: `5ad529c00f4404edf93273adada5e05906807b837b4748c8d326b1a8ab86cdf8`.
A private copy and all outputs are in `results/tone-round/`.

This is natural project dictation, not a controlled pair of identical words with
contrasting intonation. There is **no Codex transcript or human-verified reference
for this recording**, so no WER or “beats Codex” percentage is reported.
The older, separately scored Codex comparison remains in [RESULTS.md](RESULTS.md).

## Conditions

- Cohere, Granite NAR, Qwen-ASR, and Gemma use the same 16 lossless chunks,
  each ≤28 seconds, with boundaries selected by audio energy. Gemma's documented
  audio window requires segmentation. Boundary effects are part of the comparison.
- VibeVoice uses the entire recording in one pass, with a 4096-token generation
  budget. It reaches the final “Good.”; the recording is not silently truncated.
- Vocabulary conditions are no list, the pre-existing **18-term** `vocabulary.txt`,
  and the one-term `project-vocabulary.txt` containing `naiaclaw`. The intended
  project spelling was supplied by Erik independently of the model outputs.
- This is exploratory. No prompted model receives a corrected transcript or
  the expected punctuation. Jev was not called; these are fixed-list controls.
- All runs on this new recording use GPU inference. The CPU-offloaded Qwen-Omni
  experiment was stopped and excluded from further local use before these runs.

Gemma's fresh run is **incomplete and excluded**: after one normal plain result,
its vocabulary-conditioned output repeated internal thought-channel markers to
the token limit. Two further requests also failed before the run was stopped.
The embedded template already includes Google's documented empty-thought prefix.
A bounded, fresh-server check of the same failing chunk with the server reasoning
budget omitted also repeated markers and hit its 256-token cap. This did not fix
the failure or establish its cause. It is a runtime/configuration limitation,
not a measured full-recording transcription score or proof of the model's ceiling.
[Google's thinking-template documentation](https://ai.google.dev/gemma/docs/capabilities/thinking).

## Vocabulary helps, but can change unrelated words

| Configuration | Opening project spelling | Implementation instruction |
| --- | --- | --- |
| Cohere, no vocabulary | “NayaClaw”; later also “Niaclaw” / “NIA Cloud” | “but now I want to implement it” |
| Granite NAR, no vocabulary | “naya claw”; later also “nacla” / “nla” | “but now i want to implement it” |
| Qwen-ASR, no vocabulary | “Naya Cloud” | “but now I want to implement it” |
| Qwen-ASR, 18 terms | “Naiaclaw” | **“but I don't want to implement it”** |
| Qwen-ASR, project name only | “Niaclaw” | “but now I want to implement it” |
| VibeVoice, no vocabulary | “Naya Cloud” | “but now I want to implement it” |
| VibeVoice, 18 terms | “naiaclaw” | “but now I want to implement it” |
| VibeVoice, project name only | “naiaclaw” | “but now I want to implement it” |

VibeVoice's two vocabulary outputs each contain nine exact `naiaclaw` spellings,
where its unprompted output contains none. This is an observed spelling count,
not a verified entity-accuracy denominator. Qwen-ASR's 18-term output contains
six exact spellings, but the instruction's negation changes in the same run.
Its one-term output preserves that instruction but still misses the spelling.

The phrase before “Codex” remains troublesome. Unprompted VibeVoice writes
**“in several code code and Codex sessions”**; the 18-term version reduces this
to **“in several Codex sessions”**; the one-term version writes **“in several
code and codex sessions.”** The likely intended “Claude Code” is not reliably
recovered, even though it is in the 18-term list. Confirm the intended wording
against the audio rather than treating the most fluent output as correct.

## Exact punctuation differences

| Chunked Cohere / Qwen-ASR | Whole-recording VibeVoice |
| --- | --- |
| “will that be enough information to set up? A new tenant.” | “will that be enough information to set up a new tenant?” |
| Cohere: “is there any? Information we need about the tenant…” | “is there any information we need about the tenant that's not included in the token?” |

The chunk boundaries fall inside these questions. The whole-recording system
preserves the complete question structure. This demonstrates a practical context
advantage over these independently decoded chunks; it does not prove that the
model identified the punctuation from pitch rather than language structure.

VibeVoice itself changes **“Correct. Right.”** without vocabulary to
**“Correct? Right?”** with either vocabulary list, despite receiving identical
audio. The vocabulary changes model conditioning beyond the spelling of names.
Question marks therefore still need a genuine paired-intonation evaluation.

VibeVoice also retains many fillers and emits tags such as `[Silence]`,
`[Breathing]`, and `[Unintelligible Speech]`. The raw comparison retains them.
Removing known non-speech labels is a separate presentation operation; it is not
an improvement in word recognition and must not erase uncertain speech silently.

## What this supports so far

Whole-recording VibeVoice with a small relevant vocabulary is a promising local
final-pass candidate for **project spelling and sentence continuity**. This does
not establish an overall winner: name omissions, other word disagreements,
fillers, and punctuation changes remain. The one-term list is not universally
better—the Qwen-ASR results show the opposite spelling tradeoff.

Keep streaming preview separate. Preserve the original recording, use project
context as a spelling aid, and inspect disagreements in the audio. The earlier
generic Gemma/Qwen-Omni correction experiments did not demonstrate a dependable
improvement over their input recognizer. A trained audio-aware correction system
or a proprietary service remains a separate, unproven comparison on this corpus.

Provider credentials, a corrected reference, and genuinely held-out recordings
are still needed before selecting an absolute quality winner. The full research
and access map is in [RESEARCH.md](RESEARCH.md).

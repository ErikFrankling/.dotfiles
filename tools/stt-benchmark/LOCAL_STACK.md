# Local contextual transcription

This is a runnable local GPU stack and research experiment, not a claim of
perfect transcription or a proven replacement for the current dictation setup.
No Codex or cloud transcript is supplied during inference.

## Run

From the repository root:

```sh
bin/local-stt ~/stt-tone-test.wav \
  --vocabulary tools/stt-benchmark/project-vocabulary.txt \
  --strategy prompt --output ./tools/stt-benchmark/results/my-local-run.json
```

The launcher builds pinned dependencies with Nix and creates no `result` link.
It uses the existing VibeVoice ASR Q8 weights, whole-recording audio and Vulkan.
Names must be one per line. Optional `--context FILE` supplies project background
(up to 16,000 characters in this conservative runner). All outputs remain local.

Three mechanisms are available:

- `--strategy plain`: unconditioned control; rejects context and vocabulary.
- `--strategy prompt`: original audio plus background and vocabulary prompting.
- `--strategy bias --bias-weight 0.5 --beams 2`: optional background plus
  contextual shallow fusion during recognition. Names are tokenized into
  leading-space and unprefixed variants. Each partial phrase earns a token
  bonus; mismatch removes the unfinished prefix bonus from the beam score.
  Completed phrases keep their reward. Bias is confined to generated transcript
  strings, not timestamps or speaker metadata.

This is **not LOGIC, COALA, learned acoustic retrieval, or a trained deep-biasing
module**. It is a custom, training-free shallow-fusion experiment inspired by
contextual-decoding research. Model log probabilities still come from original
audio. Bias does not prove a name was spoken. Larger bonuses can force mistakes;
the experimental option is not automatically promoted to the default.

Beam scoring preserves the original model's log-softmax normalization, adds
context scores afterward, and retains upstream length normalization. Renormalizing
each biased beam separately would change this objective and invalidate the
intended rollback accounting. Greedy decoding cannot undo an emitted mistake;
beam search can retain alternatives, at extra GPU memory cost.

## Resource and output behavior

Only one cooperating local-stt inference runs at a time. The runner refuses to
start above 8 GiB existing GPU use or below 8 GiB available host RAM. During
inference it samples total VRAM, process RSS, anonymous RAM, process swap and
available host RAM. It stops on total VRAM above 17 GiB, available RAM below
5 GiB, process anonymous memory above 8 GiB, process swap above 256 MiB, or the
request deadline. Samples are observational, not a guaranteed GPU reservation.

No large CPU offload is requested. The model process exits after each request,
including interruption or failure. A future persistent GPU service is permitted
by Erik's preference if host-RAM residency is measured and bounded; this runner
does not keep one resident. CPU file cache and private anonymous RAM are reported
separately through process RSS/anonymous fields; RSS is not synonymous with
unreclaimable RAM.

The JSON stores settings, audio hash, transcript, structured speaker turns,
resource samples and paths identifying the exact runtime/model. Raw runtime logs
and text are retained in the adjacent `.artifacts` directory. Existing outputs
are never overwritten. Output returned successfully does not establish faithful
coverage of the recording; `completion_verified` remains false until reviewed.

## Frontier research availability audit — 2026-09-19

| Method | What could actually be established |
|---|---|
| [COALA](https://github.com/Guo0911/COALA) | Official repository explicitly says training/evaluation code release is postponed. No installable implementation was available there. |
| [LOGIC](https://arxiv.org/html/2601.15397v3) | Published algorithm describes a vLLM logits processor. No official runnable release was located in the paper/search. Its results cannot be attributed to this custom implementation. |
| [TRADE](https://arxiv.org/html/2606.08486v1) | Requires a trained transducer-augmented speech LLM. The paper does not make our existing VibeVoice weights into that model; no verified ready-to-run checkpoint was located in this audit. |
| [Diffusion LM rescoring](https://arxiv.org/html/2604.14001v1) | Requires matched acoustic/LM tokenization, trained diffusion weights and decoding integration. The paper is not a drop-in option for the installed GGUF recognizers. |
| [Diffusion-ASR](https://github.com/liuzhan22/Diffusion-ASR) | A distinct, available research implementation: Whisper encoder, LLaDA 8B, trained adapter and iterative transcript revision. The released loader loads LLaDA in FP16 plus the encoder, exceeding our 15–16 GB weight budget before working memory. It needs a separately validated quantized ROCm port; it was not run or scored. The supplied inference script also truncates audio at 30 seconds, so using it unchanged on our long recording would invalidate the comparison. |

Granite Speech 4.1 Plus is not automatically an upgrade for this task: its
[official model card](https://huggingface.co/ibm-granite/granite-speech-4.1-2b-plus)
says it omits punctuation and capitalization. The base model already supports
keyword prompting and was included in previous tests.

## Judging quality

Codex transcripts are machine references, not verified answers. Disagreement
with them cannot establish that Codex outperforms cloud or local recognition.
The three short clips support a regression comparison only. The long natural
project recording has no verified transcript. Exact spelling counts are not
entity recall, and increased occurrences may be hallucinations. Promotion to
the daily dictation path requires evidence of improved fidelity rather than a
newer technique name or a more fluent output.

## Measured implementation round — 2026-09-19

Default: **whole-audio VibeVoice Q8 with vocabulary prompting, greedy decoding**.
This is a practical local candidate, not a verified overall quality winner.
Bias and beam search remain opt-in experiments.

| Mechanism | Three short clips: differences from 258 machine-reference words | Long project recording |
|---|---:|---|
| Unprompted beam search, two beams | 17 | Separate long control stopped at GPU limit; no quality score |
| 18-name vocabulary prompt, greedy | 13 | 42.9 s; nine exact `naiaclaw` spellings; `Claude Code` absent |
| Decoder phrase bias 0.5, two beams | 17; identical short text to matched beam control | 100.7 s; no exact `naiaclaw`; includes “Naya Cloud” and “code code and Codex” |
| Compact project overview plus 18 names, greedy | Not run | 42.1 s; nine case-insensitive `naiaclaw` spellings; `Planet9`; `Claude Code` absent |
| Full 6,236-character project README plus 18 names | Not run | Stopped at GPU headroom limit; no transcript |

The compact overview consists of the introduction and Overview sections of the
existing project README, with no transcript supplied. It changes “Planet Nine”
to “Planet9”, but also changes one “correct server script” to “correct service
script”. Context therefore improves spellings without establishing a net gain
in fidelity. The vocabulary-only output contains “but now I want to implement
it” and “will that be enough information to set up a new tenant?”; punctuation
plausibility is not a controlled test of tone understanding.

The patched runtime with bias disabled reproduced the earlier short plain
transcript exactly. Native phrase-score tests cover partial rollback, completed
phrases, overlaps and disabled bias. Four Python guard tests and the actual
`bin/local-stt` launcher passed. The compact-context long run peaked at 16.87 GiB
total VRAM and 1.44 GiB anonymous process RAM, with no process swap observed.
The long bias run used up to 3.03 GiB anonymous RAM. Every inference process
exited; no model service was left resident. Timings include model load and
are affected by caches, so they are not controlled speed rankings.

An initial short run exceeded an overly strict 64 MiB swap guard while over
11 GiB host memory remained available; that failed attempt is retained. The
final guard is 256 MiB. Failed GPU-limit runs remain failures, not low-scoring
transcripts. A full README fitting the character limit does not guarantee it
fits alongside long audio in GPU memory; the runtime guard remains necessary.

Private outputs and resource samples are in `results/contextual-round/`.
The existing `results/technology-comparison/dashboard.html` and
`comparison.html` include these runs with playable recordings and text diffs.
The streaming preview and daily hotkey path are not replaced by this command.

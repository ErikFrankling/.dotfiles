# Dictation reliability and responsive UI

This follow-up revisits deployment behavior, not the original model ranking.
The selected technology remains an autoregressive audio encoder/decoder ASR
model with project vocabulary (VibeVoice Q8), alongside a separate real-time
Nemotron draft. Both run through Vulkan on the AMD GPU.

## Failure reproduced

The previous live deployment passed a short recording but failed longer user
recordings. The coordinator's 17 GiB total-VRAM guard terminated the final
worker. The browser displayed a generic disconnection error. Persisted user
recordings and journal messages established the failure; previous isolated or
short passing tests did not establish reliability under the user's workload.

## Runtime fix and quality decision

The original encoder processes 60-second acoustic blocks. That temporary GPU
workspace is too large alongside the two resident models and this desktop.
The native patch reduces those blocks to 20 seconds, carrying tokenizer state
across them and concatenating their audio latents into the same decoder prompt.
It also releases the offline decoder-prefill graph after its owning CPU results
have been copied out. Model weights remain loaded on the GPU.

The prefill-release change alone did **not** fix the failure. Reducing the
internal acoustic blocks did. Raising the guard or unloading the preview was
rejected: the latter completed once but peaked at 19.05 GiB total VRAM.

All comparisons below use the same browser-captured PCM (400.896 seconds,
including capture padding around the original 398.74-second recording), with
the frozen 983-word normalized reference. Agreement is **not human-verified
accuracy**. See [methodology](../METHODOLOGY.md).

| Candidate | Reference agreement | Word edits | Question checks | Outcome |
| --- | ---: | ---: | ---: | --- |
| Independent 30-second transcriptions, fixed silence threshold | 93.69% | 62 | 6/7 | Runs, but rejected as final quality |
| Independent 30-second transcriptions, adaptive noise floor | 96.03% | 39 | 3/7 | Fewer overlap errors; still inferior final wording |
| Independent 90–120-second transcriptions, repaired runtime | 97.46% | 25 | 6/7 | Better context, still more word changes |
| Whole recording, repaired runtime, 12 vocabulary names | 98.37% | 16 | 5/7 | 36.07 s, 14.90 GiB peak total VRAM |
| Whole recording, repaired runtime, project excerpt + 32 names | 98.17% | 18 | 5/7 | 36.43 s, 15.25 GiB peak total VRAM |

Punctuation did not improve uniformly: the full-context result missed two of
seven targeted question checks. These are small-sample results, not a claim of
perfect punctuation or a statistically established advantage from one prompt.
The project-context configuration is retained for general project vocabulary,
not optimized to the two special names in this recording.

The deployed design therefore keeps short background refinements as progress
and performs a long-context quality pass after Stop. It does **not** claim that
all final work has already finished during recording. On this fixture the
quality pass takes roughly 36 seconds, compared with 2–4 seconds of final waiting
when accepting the lower-quality concatenated sections. Longer recordings use
bounded windows of at most seven minutes with independent quality checkpoints;
recordings longer than the study fixture are not established by this test.

The original draft, original audio and completed sections survive failure and
retry. Adaptive noise-floor detection avoids treating all pauses in a noisy
microphone as continuous speech. Confirmed pauses split without overlap;
continuous speech retains two seconds of acoustic overlap with conservative
word-sequence deduplication. Long-window boundaries remain a limitation worth
retesting on longer recordings.

## Interface and verification scope

Dictation opens a large dedicated workspace. Desktop shows provisional and
refined text together; phones use large tabs. Text is read-only there and is
appended to the composer only after explicit acceptance. Closing stops capture
and retains the result. A failed final pass offers the original draft. Audio
and session state remain on disk; the current browser can download its WAV.
Both panes follow incoming text until the reader scrolls back. Dictation targets
are at least 48px; the primary control is 64px. The layout was tested at 390px
and 320px widths, including refinement failures. These are browser viewport
tests, not a claim of physical iOS/Android microphone compatibility.

Reference designs reviewed: upstream [voice beta #5213](https://github.com/pingdotgg/t3code/pull/5213),
[web dictation #10195](https://github.com/pingdotgg/t3code/pull/10195), and
[environment transcription #8928](https://github.com/pingdotgg/t3code/pull/8928).
The adopted waveform/level feedback, timer and stop control are implemented in
our source fork. A dedicated large workspace and draft retention are specific
to this workflow.

The real browser harness replays the original WAV through a MediaStream and
T3's microphone capture, uploads and authenticated route. It checks that the
composer is unchanged before acceptance and that refined text arrives before
Stop. Separate controlled-response browser tests exercise failed refinement,
close/reopen, reload recovery and draft insertion. Phone target dimensions are
measured, and screenshots are visually inspected. Mocked failure tests are not
presented as actual recognizer success.

The final browser replay passed using source-fork revision `411a3466` and the
repaired Nix-built service: 0.909 s to listening, early refinement observed,
36.613 s from Stop to the accepted final transcript, and no composer mutation
before acceptance. Output was appended exactly once. This fresh microphone
capture scored 98.37% reference agreement (16 word edits), 5/7 question checks,
and 7/8 targeted content checks. The known “already”/“solely” content error
remains; this is not a perfect transcript.

An external 50 ms sampler measured 15.26 GiB peak total VRAM, 1.66 GiB peak
combined worker anonymous RAM during inference, and zero worker swap. An idle
snapshot before the final pass showed about 217 MiB combined anonymous RAM.
The higher transient inference memory must not be confused with permanently
resident CPU model weights. Ten backend regression tests and the frontend
TypeScript check passed. Controlled browser failures passed at 320px and 390px;
the full actual-audio replay switched between desktop and phone viewports.

Archiving exposed a missing disk serialization field for the new quality
checkpoints. This did not change the successful browser transcript. The save
path and regression test were corrected, then a fresh exact-PCM replay passed
on the applied service with all 12,828,672 bytes covered by persisted quality
checkpoints. That replay scored 17 word edits (98.27% reference agreement).
The replay was uploaded faster than real time, so its 51.2-second final wait
must not replace the real browser latency measurement above.

Private `comparison-final.html` shows normalized differences against the frozen
reference; `verification/` contains browser scripts, screenshots, raw results,
resource measurements and rejected experiments. `final-browser-recording/`
preserves the exact audio and service provenance for the final replay.

See [deployment status](../DEPLOYMENT_STATUS.md) for the applied revision and
final verification. Raw outputs, screenshots, scripts, logs, retained recordings
and comparisons are private under this directory's `private/` subdirectory.

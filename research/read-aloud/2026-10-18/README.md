# Read-aloud model taste test (2026-10-18)

Picking the local models for T3 Code's read-aloud button: a small LLM rewrites
an assistant message as a short spoken briefing, then a TTS voice reads it.
Erik picks by ear and by reading, as with dictation, from the side-by-side page.

- **Page:** `compare.html` (audio in `private/audio/`, not committed). Serve this
  directory, e.g. `python3 -m http.server 8086`, and open `/compare.html`.
- **Decision:** pending, Erik's picks go here.

## Method

- Summary prompt: `tools/read-aloud-bench/prompt.md` (the `/bro` idea plus
  spoken-style rules). Inputs: two long assistant answers from the planning
  thread (`inputs/`). Same prompt, temperature 0.3, thinking off, Q4_K_M GGUF,
  llama.cpp Vulkan (`tools/read-aloud-bench/run_llm.py`), one model at a time.
- In-budget models ran with dictation resident (the real setup). Bigger
  references ran after `local-stt` released its GPU memory.
- Voices all read Qwen3.5-4B's summary of input 1, sentence by sentence (how
  read-aloud will stream), after one warm-up call (`run_tts.py`, `tts/`).
  Cloning-only models used the mathvid narrator reference clip.
- Whisper small.en transcribed every clip to check nothing was dropped
  (`tts/check_audio.py`, `results/asr-check.json`).
- Budget: dictation plus desktop peak at about 15.3 GiB during a final pass
  (`research/stt/2026-09-20/DICTATION_REPAIR.md`), so about 3.7 GB is left for
  anything that stays loaded beside it.

## Summary models

| Model | Released | VRAM loaded (GiB) | Load (s) | Time to full summary, input 1 / 2 (s) | Decode tok/s |
|---|---|---|---|---|---|
| Qwen3.5-2B | 2026-03 | 1.47 | 2.0 | 0.8 / 0.9 | 213 |
| Gemma 4 E2B | 2026-04 | 1.55 | 7.2 | 1.4 / 0.8 | 173 |
| LFM2.5-2.6B | 2026-08 | 1.91 | 1.4 | 11.2 / 4.3 (thinks) | 222 |
| Qwen3.5-4B | 2026-03 | 3.17 | 5.6 | 1.6 / 2.0 | 130 |
| Granite 4.2 3B | 2026-08 | 3.32 | 4.6 | 1.6 / 0.5 | 160 |
| Gemma 4 E4B | 2026-04 | 3.32 | 13.4 | 1.6 / 1.3 | 119 |
| Ministral 3 3B | 2025-12 | 3.65 | 10.4 | 2.0 / 2.0 | 164 |
| LFM2.5-8B-A1B | 2026-05 | 5.08 | 11.6 | 3.4 / 2.8 (thinks) | 284 |
| Qwen3.5-9B | 2026-03 | 5.43 | 13.2 | 2.4 / 2.0 | 89 |
| Gemma 4 12B | 2026-05 | 7.41 | 15.0 | 4.4 / 3.3 | 66 |
| Qwen3.5-27B (reference) | 2026-02 | ~16 | n/a | about 7 | 32 |

Notes from reading the outputs (Erik decides):

- Qwen3.5-2B gets facts wrong (Kokoro "on your laptop"). Ministral 3 3B says
  "big summary model" and runs long. Granite 4.2 3B reads out file paths.
- LFM2.5 only exists as a reasoning model: `--reasoning off` is ignored, and
  with a 600-token budget it returned nothing. Rerun with room to think.
- Gemma 4 E4B fits the budget: its 5 GB file loads to 3.3 GiB of VRAM.
- No small Qwen3.8 exists; 27B is the smallest Qwen3.8.

## Voices

| Voice | Released | Added VRAM (GiB) | First sentence (s) | Speed vs real time | Words heard |
|---|---|---|---|---|---|
| Kokoro 82M, CPU (af_heart / am_michael) | 2025-01 | 0 | 1.7 | 9-10× | 99-100% |
| Pocket TTS, CPU | 2025-12 | 0 | 2.0 | 4.8× | 100% |
| Supertonic 3, CPU | 2026-04 | 0 | 4.3 | 2.9× | 98% |
| Kokoro 82M, GPU | 2025-01 | 2.0 | 1.4 | 6.7× | 100% |
| VibeVoice Realtime 0.5B | 2025-12 | 3.2 | 3.9 | 3.6× | 99% |
| Qwen3-TTS 0.6B | 2026-01 | 3.9 | 9.8 | 1.3× | 98% |
| Chatterbox Turbo | 2025-12 | 4.1 | 3.3 | 3.0× | 100% |
| Qwen3-TTS 1.7B | 2026-01 | 6.1 | 14.3 | 1.2× | 98% |
| Breeze TTS 2 (narrator clone) | 2026-08 | 8.7 | 19.9 | 0.6× | 100% |
| Higgs TTS 3 4B | 2026-06 | ~15 (vLLM reserve) | 5.2 | 2.4× | 89% |

Did not run here:

- **Fish Audio S2 Pro** needs 24 GB. Even with a 4k context it reached
  20.0 GB encoding the reference and decoding; a VRAM watchdog stopped it.
- **Voxtral 4B TTS** segfaults in vLLM-Omni ROCm v0.28.0's audio decoder
  warm-up on RDNA3.
- **Fish Audio Drama 3** (newest #1 open voice) is 41 GB and NVIDIA-only.
- **Magpie, Kani TTS** need NVIDIA NeMo.

## Findings for the build

- Every CPU voice uses no GPU memory, so a CPU voice plus a small summary
  model fits beside dictation on the PC. That may make the homelab 1060
  unnecessary.
- Every GPU voice except Kokoro is too big to stay loaded beside dictation and
  a summary model.
- PyTorch TTS on ROCm needs `MIOPEN_FIND_MODE=FAST`: without it Qwen3-TTS
  spent 35 s compiling kernels for its first sentence.
- The existing `qwen3.5-27b` llama-swap entry filled VRAM to 20.0 GB (0.0 free)
  with dictation unloaded, tighter than the 19.6 GB AGENTS.md records.

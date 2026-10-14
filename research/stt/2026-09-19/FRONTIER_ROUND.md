# GPU-first frontier experiments

These are isolated Nix benchmark environments, not resident services or a
change to the desktop's deployed transcription stack. Audio and raw responses
remain under ignored `results/` paths.

## Execution policy

Try GPU execution first. A temporary CPU-offload experiment requires an
explicit reason documenting the GPU failure or capacity constraint. It does
not authorize persistent CPU residency. Both runners terminate their inference
processes when finished or when their resource/deadline guards fire.

`run.py` verifies that its executable exposes the requested GPU before loading
weights. `-ngl 999` by itself is insufficient: a CPU-only llama.cpp build can
otherwise accept an offload request without providing GPU inference. The
benchmark explicitly selects Vulkan0 and disables multi-device splitting.

`run_frontier.py` uses ROCm, selects the RX 7900 XT by name, and refuses a model
with non-GPU parameters. PyTorch calls the AMD device `cuda:0`; its HIP version
and actual device name are checked. No automatic `device_map="auto"` CPU
fallback is used. The tested runtime is PyTorch 2.10 / ROCm 7.2, Transformers
5.5, and TorchAO 0.15. Both BF16 matrix multiplication and Int8WeightOnlyConfig
inference passed on the Radeon. The full Audio Flamingo model subsequently
completed both whole-recording conditions entirely on that GPU.

Resource guards use 17 GiB total GPU memory and at least 2 GiB available system
RAM. Total GPU memory includes the desktop. RSS, anonymous RAM, and swap are
separate measurements; GPU execution does not make host memory disappear.

## Reproduce the Hugging Face runtime

```sh
nix-build tools/stt-benchmark/frontier-python.nix --no-out-link --cores 4 --max-jobs 1
nix-build tools/stt-benchmark/frontier-model.nix --no-out-link --cores 4 --max-jobs 1
```

Use the returned Python environment's `bin/python3` to run
`tools/stt-benchmark/run_frontier.py --model-dir MODEL_STORE_PATH --audio AUDIO.wav
--output RESULT.json`. Int8 GPU weights are the default; `--quant bf16` is an
explicit higher-memory comparison. The model files have pinned revisions and
SHA256 hashes in `frontier-models.json`. The model runner never downloads code
or weights itself. Full-model loading and audio inference were validated on
the 398.7-second recording, including checking for missing/mismatched weights.

Audio Flamingo Next's released checkpoint uses the MusicFlamingo architecture
identifier. The older Transformers 5.3 package lacks that implementation, so
the isolated environment pins 5.5. Its weights are available for
[non-commercial research](https://huggingface.co/nvidia/audio-flamingo-next-hf),
which is a deployment restriction even if the quality test succeeds.

## Evidence collected

Audio Flamingo Next Int8 completed the entire recording on GPU. A simple
transcription prompt scored 89.4 reference word agreement; explicit faithful
transcription/punctuation instructions plus 18 names scored 88.9. Neither
condition improved on VibeVoice. Both miss project spelling and Claude Code,
and recover only two of seven question checks. These are agreement scores
against a provisional reference, not human accuracy percentages.

Two runtime repairs were necessary: per-tensor CPU staging before ROCm copies
prevented private mapped weights becoming a large anonymous RAM copy (about
14.4 GiB down to 1.7 GiB); native ATen GPU convolution avoided MIOpen's HIPRTC
architecture error. Neither moves inference to CPU. The simple-prompt run
peaked at about 13.4 GiB total GPU memory, 10.2 GiB RSS, 1.73 GiB anonymous RAM,
and 232 MiB process swap. GPU placement still uses host memory.

Qwen3-Omni Q4's weights plus projector total 18.52 GiB, before desktop, cache,
and workspace. A 38-GPU-layer attempt hit the 17 GiB guard. After a successful
4k-context probe, 34 GPU layers at 8k context completed the full recording:
95.4 plain and 97.7 with 18 names. Both pass seven of eight content checks and
four of seven question checks. The vocabulary run reused its audio-prefix
cache; its 110.8 seconds must not be treated as independent cold-audio timing.
The plain request took 148.4 seconds. Temporary CPU layers were unloaded with
the process. Peak total GPU memory was about 16.3 GiB.

Qwen also reconsidered VibeVoice's compact-context draft with the original
audio and 18 names, without receiving the reference. At 32 GPU layers and
12k context it completed without a memory guard failure: 98.0 agreement,
seven of eight content checks and six of seven question checks. It still
omits Claude Code, retains someone's portal and only instead of already,
and renders Naia build as Nya build. Its 180.6-second request excludes loading
and the first ASR pass. Audio-prefix caching was disabled. Peak total GPU
memory was 15.89 GiB and RSS 10.77 GiB; the process unloaded afterward.
This does not demonstrate a quality gain over the 42.1-second VibeVoice draft.

Gemma completed four full-recording GPU conditions. The maker prompt scored
89.2 word agreement without vocabulary and 71.1 with vocabulary. Vocabulary
leakage, omissions, and unwanted translations in the stricter-prompt controls
remain unresolved. These are configuration results, not a proven model ceiling.

The public Wispr demo accepted a 349.952-second excerpt. Fresh unhinted Gemini
and VibeVoice runs used the same excerpt. Wispr reversed the opening request;
the other two preserved it. The shorter corpus has its own comparison and
provisional reference in `results/frontier-round/excerpt350/`, and is not mixed
into the full-recording ranking. Its word-agreement metric also penalizes some
harmless cleanup. Neither the metric nor the public demo establishes the
quality of every paid desktop configuration.

Superwhisper browser requests failed at the service endpoint. Aqua's virtual
microphone attempts returned no text and did not show an active recording
state. These are access/integration failures, not low transcription scores.
NVIDIA's hosted Nemotron Omni endpoint returned “No audio provided” for both
the long recording and a short audio diagnostic; neither response is scored.

## Runtime references

- [ROCm private-mapping copy behavior and per-tensor staging](https://github.com/ROCm/legacy-rocm-build/issues/6523).
- [MIOpen/HIPRTC architecture error in Nixpkgs](https://github.com/NixOS/nixpkgs/issues/498371).
- [Gemma audio capabilities and input limits](https://ai.google.dev/gemma/docs/capabilities/audio).

These explain the runtime choices; quality conclusions come from the saved
same-recording outputs, not vendor benchmarks.

"""Compare whole-audio VibeVoice decoding, context, and beam search locally."""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import time
import wave


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--binary", required=True)
    p.add_argument("--model-dir", type=pathlib.Path, required=True)
    p.add_argument("--name", required=True)
    p.add_argument("--family", choices=["vibevoice_asr", "vibevoice_asr_streaming"], required=True)
    p.add_argument("--audio-dir", type=pathlib.Path, required=True)
    p.add_argument("--output", type=pathlib.Path, required=True)
    p.add_argument("--vocabulary", type=pathlib.Path)
    p.add_argument("--max-tokens", type=int, default=1024)
    p.add_argument("--arms", nargs="+", choices=["plain", "vocabulary", "beam4"], default=["plain", "vocabulary", "beam4"])
    args = p.parse_args()
    model = args.model_dir / "model.gguf"
    if not model.is_file():
        raise SystemExit("Model build is incomplete")
    if model.stat().st_size > 16_000_000_000:
        raise SystemExit("Model exceeds the conservative full-GPU weight budget; do not use CPU offload")
    for used in pathlib.Path("/sys/class/drm").glob("card*/device/mem_info_vram_used"):
        if int(used.read_text()) > 8 * 1024**3:
            raise SystemExit("GPU already uses more than 8 GiB; defer this benchmark")
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "artifacts").mkdir(exist_ok=True)
    vocabulary = args.vocabulary.read_text().strip() if args.vocabulary else ""
    clips = sorted(args.audio_dir.glob("*.wav"))
    if not clips:
        raise SystemExit("No WAV files found")
    for clip in clips:
        with wave.open(str(clip)) as w:
            duration = w.getnframes() / w.getframerate()
        for arm in args.arms:
            if arm == "vocabulary" and not vocabulary:
                continue
            transcript = args.output / f"{args.name}.{clip.stem}.{arm}.txt"
            turns_path = args.output / "artifacts" / f"{args.name}.{clip.stem}.{arm}.turns.json"
            transcript.unlink(missing_ok=True)
            turns_path.unlink(missing_ok=True)
            prompt = "Relevant spellings, only when actually spoken: " + vocabulary if arm == "vocabulary" else ""
            cmd = [args.binary, "--task", "asr", "--family", args.family,
                   "--model", str(model), "--backend", "vulkan", "--threads", "8",
                   "--audio", str(clip), "--text-out", str(transcript), "--turns-out", str(turns_path), "--metrics",
                   "--temperature", "0", "--max-tokens", str(args.max_tokens), "--num-beams", "4" if arm == "beam4" else "1",
                   "--audio-chunk-mode", "none", "--language", "en"]
            if prompt:
                cmd += ["--request-option", "context=" + prompt] if args.family.endswith("streaming") else ["--text", prompt]
            if args.family.endswith("streaming"):
                cmd += ["--session-option", "vibevoice_asr_streaming.max_history_steps=4096"]
            started = time.monotonic()
            try:
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
                status, stdout, stderr = result.returncode, result.stdout, result.stderr
            except subprocess.TimeoutExpired as exc:
                status, stdout, stderr = 124, "", "Inference exceeded 600 seconds"
                if exc.stdout:
                    stdout = exc.stdout.decode(errors="replace") if isinstance(exc.stdout, bytes) else exc.stdout
            raw_text = transcript.read_text().strip() if transcript.exists() and status == 0 else None
            turns = json.loads(turns_path.read_text()) if turns_path.exists() and status == 0 else []
            # Speaker identifiers are metadata, not spoken words. Preserve the
            # raw labeled text, but score the runtime's structured speech fields.
            text = " ".join(t["text"].strip() for t in turns) if turns else raw_text
            runtime_ms = re.search(r"^metrics\.wall_ms=([0-9.]+)$", stdout, re.M)
            record = {"model": args.name, "model_family": args.family, "arm": arm, "clip": clip.name,
                      "audio_sha256": hashlib.sha256(clip.read_bytes()).hexdigest(),
                      "audio_seconds": duration, "elapsed_seconds": time.monotonic()-started,
                      "timing_includes_model_load": True, "command": cmd, "prompt": prompt,
                      "runtime_inference_seconds": float(runtime_ms[1])/1000 if runtime_ms else None,
                      "returncode": status, "stdout": stdout, "stderr": stderr,
                      "response": {"text": text, "raw_text": raw_text, "speaker_turns": turns}}
            out = args.output / f"{args.name}.{clip.stem}.{arm}.json"
            out.write_text(json.dumps(record, indent=2) + "\n")
            print(f"{out.name}: {record['elapsed_seconds']:.2f}s, exit {status}", flush=True)


if __name__ == "__main__":
    main()

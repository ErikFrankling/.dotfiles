"""Benchmark transcribe.cpp models, saving clean text separately from CLI logs."""
import argparse
import hashlib
import json
import pathlib
import subprocess
import time
import wave


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--binary", required=True)
    p.add_argument("--model-dir", type=pathlib.Path, required=True)
    p.add_argument("--name", required=True)
    p.add_argument("--audio-dir", type=pathlib.Path, required=True)
    p.add_argument("--output", type=pathlib.Path, required=True)
    args = p.parse_args()
    if not (args.model_dir / "model.gguf").is_file():
        raise SystemExit("Model build is not complete: model.gguf does not exist")
    for used in pathlib.Path("/sys/class/drm").glob("card*/device/mem_info_vram_used"):
        if int(used.read_text()) > 8 * 1024**3:
            raise SystemExit("GPU already uses more than 8 GiB; defer this benchmark")
    args.output.mkdir(parents=True, exist_ok=True)
    for clip in sorted(args.audio_dir.glob("*.wav")):
        with wave.open(str(clip)) as w:
            duration = w.getnframes() / w.getframerate()
        transcript = args.output / f"{args.name}.{clip.stem}.transcript.txt"
        # Do not mistake a stale successful output for a failed rerun.
        if transcript.exists():
            transcript.unlink()
        cmd = [args.binary, "-q", "-m", str(args.model_dir / "model.gguf"),
               "--backend", "vulkan", "--n-ctx", "4096", "-l", "en",
               "--output", str(transcript), str(clip)]
        begin = time.monotonic()
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        record = {"model": args.name, "arm": "plain", "clip": clip.name,
                  "audio_sha256": hashlib.sha256(clip.read_bytes()).hexdigest(),
                  "audio_seconds": duration, "elapsed_seconds": time.monotonic()-begin,
                  "timing_includes_model_load": True, "command": cmd,
                  "returncode": result.returncode, "stderr": result.stderr,
                  "stdout": result.stdout,
                  "response": {"text": transcript.read_text().strip() if transcript.exists() else None}}
        out = args.output / f"{args.name}.{clip.stem}.plain.json"
        out.write_text(json.dumps(record, indent=2) + "\n")
        print(f"{out.name}: {record['elapsed_seconds']:.2f}s, exit {result.returncode}", flush=True)


if __name__ == "__main__":
    main()

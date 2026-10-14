"""Compare whole-file and simulated streaming ASR with the same saved audio."""
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
    p.add_argument("--vocabulary", type=pathlib.Path)
    p.add_argument("--offline-only", action="store_true")
    args = p.parse_args()
    if not (args.model_dir / "model.gguf").is_file():
        raise SystemExit("Model build is not complete: model.gguf does not exist")
    for used in pathlib.Path("/sys/class/drm").glob("card*/device/mem_info_vram_used"):
        if int(used.read_text()) > 8 * 1024**3:
            raise SystemExit("GPU already uses more than 8 GiB; defer this benchmark")
    args.output.mkdir(parents=True, exist_ok=True)
    arms = {"plain": []}
    if not args.offline_only:
        arms["streaming"] = ["--stream"]
    if args.vocabulary:
        boosted = ["--speech-context-boost", "2"]
        for term in args.vocabulary.read_text().replace("\n", ",").split(","):
            if term.strip():
                boosted += ["--speech-context", term.strip()]
        arms["vocabulary"] = boosted
    for clip in sorted(args.audio_dir.glob("*.wav")):
        with wave.open(str(clip)) as w:
            duration = w.getnframes() / w.getframerate()
        for arm, extra in arms.items():
            cmd = [args.binary, "transcribe", str(clip), "--model", str(args.model_dir / "model.gguf"),
                   "--backend", "vulkan", "--format", "text", *extra]
            begin = time.monotonic()
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            record = {"model": args.name, "arm": arm, "clip": clip.name,
                      "audio_sha256": hashlib.sha256(clip.read_bytes()).hexdigest(),
                      "audio_seconds": duration, "elapsed_seconds": time.monotonic()-begin,
                      "timing_includes_model_load": True, "command": cmd,
                      "returncode": result.returncode, "stderr": result.stderr,
                      "response": {"text": result.stdout.strip()}}
            out = args.output / f"{args.name}.{clip.stem}.{arm}.json"
            out.write_text(json.dumps(record, indent=2) + "\n")
            print(f"{out.name}: {record['elapsed_seconds']:.2f}s, exit {result.returncode}", flush=True)


if __name__ == "__main__":
    main()

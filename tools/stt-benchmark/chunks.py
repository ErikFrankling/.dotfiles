"""Split at low-energy boundaries without dropping samples; merge benchmark records."""
import argparse
import array
import hashlib
import json
import pathlib
import sys
import wave


def split(args):
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = []
    for clip in sorted(args.audio_dir.glob("*.wav")):
        with wave.open(str(clip)) as w:
            if (w.getframerate(), w.getnchannels(), w.getsampwidth()) != (16000, 1, 2):
                raise ValueError("Expected mono 16 kHz signed 16-bit WAV")
            params = w.getparams()
            raw = w.readframes(w.getnframes())
        samples = array.array("h", raw)
        if sys.byteorder != "little":
            samples.byteswap()
        start, parts = 0, []
        limit = int(args.seconds * 16000)
        while start < len(samples):
            end = min(start + limit, len(samples))
            if end < len(samples):
                # Find a quiet 20 ms window in the last 5 seconds of this chunk.
                choices = range(max(start + 16000, end - 80000), end - 320, 160)
                cut = min(choices, key=lambda i: sum(s*s for s in samples[i:i+320]))
                end = cut + 160
            name = f"{clip.stem}-part{len(parts):02d}.wav"
            with wave.open(str(args.output / name), "wb") as w:
                w.setparams(params)
                w.writeframes(raw[start*2:end*2])
            parts.append({"clip": name, "start_frame": start, "end_frame": end})
            start = end
        manifest.append({"clip": clip.name, "audio_sha256": hashlib.sha256(clip.read_bytes()).hexdigest(),
                         "audio_seconds": len(samples)/16000, "parts": parts})
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


def merge(args):
    manifest = json.loads(args.manifest.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    for clip in manifest:
        parts = [json.loads((args.results / f"{args.name}.{pathlib.Path(p['clip']).stem}.{args.arm}.json").read_text())
                 for p in clip["parts"]]
        if any(p["returncode"] != 0 or not isinstance(p.get("response", {}).get("text"), str) for p in parts):
            raise ValueError("Cannot merge a failed or missing chunk: " + clip["clip"])
        record = {"model": args.name, "arm": args.arm, "clip": clip["clip"],
                  "audio_sha256": clip["audio_sha256"], "audio_seconds": clip["audio_seconds"],
                  "elapsed_seconds": sum(p["elapsed_seconds"] for p in parts), "returncode": 0,
                  "chunk_manifest": clip["parts"], "chunk_results": parts,
                  "response": {"text": " ".join(p["response"]["text"].split("<asr_text>")[-1].strip() for p in parts)}}
        (args.output / f"{args.name}.{pathlib.Path(clip['clip']).stem}.{args.arm}.json").write_text(json.dumps(record, indent=2)+"\n")


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    s = sub.add_parser("split")
    s.add_argument("--audio-dir", type=pathlib.Path, required=True)
    s.add_argument("--output", type=pathlib.Path, required=True)
    s.add_argument("--seconds", type=float, default=28)
    m = sub.add_parser("merge")
    m.add_argument("--manifest", type=pathlib.Path, required=True)
    m.add_argument("--results", type=pathlib.Path, required=True)
    m.add_argument("--output", type=pathlib.Path, required=True)
    m.add_argument("--name", required=True)
    m.add_argument("--arm", required=True)
    args = parser.parse_args()
    if args.command == "split" and args.seconds <= 5:
        parser.error("Chunk duration must exceed five seconds")
    (split if args.command == "split" else merge)(args)


if __name__ == "__main__":
    main()

"""Reference-free minimum-disagreement selection among existing transcripts.

This selects an existing candidate; it does not hear audio or invent a merged
transcript. Candidate order is a deterministic tie-break, not a quality score.
"""
import argparse
import json
import pathlib
import time
from score import distance, words


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--results", type=pathlib.Path, required=True)
    p.add_argument("--output", type=pathlib.Path, required=True)
    p.add_argument("--models", nargs="+", default=["canary-qwen-q8", "cohere-q8", "granite-nar-q8"])
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for path in sorted(args.results.glob(f"{args.models[0]}.*.plain.json")):
        started = time.monotonic()
        first = json.loads(path.read_text())
        stem = pathlib.Path(first["clip"]).stem
        candidates = [json.loads((args.results / f"{model}.{stem}.plain.json").read_text()) for model in args.models]
        if any(c["returncode"] != 0 or c.get("input_limit_exceeded") for c in candidates):
            raise ValueError("Cannot use a failed or unsupported-input candidate")
        if len({c["audio_sha256"] for c in candidates}) != 1:
            raise ValueError("Candidate recordings differ")
        transcripts = [c["response"]["text"].split("<asr_text>")[-1] for c in candidates]
        tokens = [words(t) for t in transcripts]
        costs = [sum(distance(a, b) for b in tokens) for a in tokens]
        chosen = min(range(len(costs)), key=costs.__getitem__)
        record = {"model": "consensus-select", "arm": "plain", "clip": first["clip"],
                  "audio_sha256": first["audio_sha256"], "audio_seconds": first["audio_seconds"],
                  "elapsed_seconds": time.monotonic()-started + sum(c["elapsed_seconds"] for c in candidates),
                  "timing_note": "Sum of recorded candidate runtimes plus selection; not a fresh latency measurement",
                  "returncode": 0, "candidate_models": args.models, "costs": costs,
                  "selected_model": args.models[chosen], "response": {"text": transcripts[chosen]}}
        (args.output / f"consensus-select.{stem}.plain.json").write_text(json.dumps(record, indent=2)+"\n")
        print(stem, "selected", args.models[chosen], "costs", costs)


if __name__ == "__main__":
    main()

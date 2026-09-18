"""Agreement with saved references, not a claim of independently measured WER."""
import argparse
import collections
import json
import pathlib
import re


def words(text):
    return re.sub(r"[^\w' ]", " ", text.lower()).split()


def distance(reference, hypothesis):
    row = list(range(len(hypothesis) + 1))
    for i, expected in enumerate(reference, 1):
        nxt = [i]
        for j, actual in enumerate(hypothesis, 1):
            nxt.append(min(nxt[-1] + 1, row[j] + 1, row[j - 1] + (expected != actual)))
        row = nxt
    return row[-1]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--results", type=pathlib.Path, required=True)
    p.add_argument("--references", type=pathlib.Path, required=True)
    args = p.parse_args()
    totals = collections.defaultdict(lambda: [0, 0, 0, 0, 0])
    for path in sorted(args.results.glob("*.json")):
        data = json.loads(path.read_text())
        if data.get("input_limit_exceeded"):
            print("Excluded input beyond model's supported window:", path.name)
            continue
        ref = args.references / (pathlib.Path(data["clip"]).stem + ".ref.txt")
        text = data.get("response", {}).get("text")
        if not ref.exists() or not isinstance(text, str) or data["returncode"] != 0:
            print("Excluded failed or unreferenced run:", path.name)
            continue
        text = text.split("<asr_text>")[-1]
        r, h = words(ref.read_text()), words(text)
        t = totals[(data["model"], data["arm"])]
        t[0] += distance(r, h)
        t[1] += len(r)
        t[2] += data["elapsed_seconds"]
        t[3] += data["audio_seconds"]
        t[4] += 1
    print("Model | Arm | Clips | Word disagreement with reference | Audio s | Inference s")
    for (model, arm), (errors, count, elapsed, audio, clips) in sorted(totals.items()):
        print(f"{model} | {arm} | {clips} | {errors}/{count} ({100*errors/max(1,count):.2f}%) | {audio:.1f} | {elapsed:.2f}")


if __name__ == "__main__":
    main()

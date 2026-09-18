"""Concrete checks against saved Codex wording, including punctuation ignored by WER.

These are reference-agreement checks, not listening-verified accuracy labels.
They are evaluated after generation and are never supplied to recognizers.
"""
import argparse
import json
import pathlib
import re


CHECKS = {
    "f30ba90b": {
        "standalone_why_question": r"\bwhy\s*\?",
        "why_then_statement": r"\bwhy\s*\?\s*there",
        "three_always_with_commas": r"\balways,\s*always,\s*always\b",
        "i_told_you": r"\bi told you\b",
        "and_test_it": r"\band test it\b",
        "contains_untested": r"\buntested\b",
        "contains_wait_instead": r"\bwait\b",
    },
    "1152f7da": {
        "right_question": r"\bright\s*\?",
        "final_works_question": r"\brepo works\s*\?",
        "subagent_spelling": r"\bsubagent\b",
    },
}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--results", type=pathlib.Path, required=True)
    p.add_argument("--references", type=pathlib.Path, required=True)
    p.add_argument("--output", type=pathlib.Path, required=True)
    args = p.parse_args()
    rows = []
    for path in sorted(args.results.glob("*.json")):
        d = json.loads(path.read_text())
        if not isinstance(d, dict):
            continue
        if d.get("returncode") != 0 or d.get("input_limit_exceeded"):
            continue
        text = d.get("response", {}).get("text")
        clip = pathlib.Path(d.get("clip", "")).stem
        if clip not in CHECKS or not isinstance(text, str):
            continue
        text = text.split("<asr_text>")[-1]
        reference = (args.references / f"{clip}.ref.txt").read_text()
        checks = {name: {"reference": bool(re.search(pattern, reference, re.I)),
                         "output": bool(re.search(pattern, text, re.I))}
                  for name, pattern in CHECKS[clip].items()}
        rows.append({"model": d["model"], "arm": d["arm"], "clip": clip,
                     "checks": checks, "text": text, "reference": reference.strip()})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"status": "machine-reference agreement only", "rows": rows}, indent=2)+"\n")


if __name__ == "__main__":
    main()

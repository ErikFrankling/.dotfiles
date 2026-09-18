"""Experimental vocabulary selector using TypeSafe's documented System One API.

Reads explicitly supplied text context only. Without --send it writes the exact
request for inspection and makes no network call. Never accepts an audio file.
"""
import argparse
import json
import os
import pathlib
import urllib.request


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--context", type=pathlib.Path, required=True)
    p.add_argument("--vocabulary", type=pathlib.Path, required=True)
    p.add_argument("--output", type=pathlib.Path, required=True)
    p.add_argument("--provider", choices=["typesafe", "openrouter"], default="openrouter")
    p.add_argument("--model")
    p.add_argument("--send", action="store_true")
    args = p.parse_args()
    terms = list(dict.fromkeys(t.strip() for t in args.vocabulary.read_text().replace("\n", ",").split(",") if t.strip()))
    if not terms:
        raise SystemExit("Vocabulary is empty")
    model = args.model or ("typesafe/jev-1.13" if args.provider == "openrouter" else "jev-1.13.0")
    body = {"model": model, "state": {"context": args.context.read_text()}, "questions": {
        str(i): {"type": "noul", "instructions": (
            f"Is the term {term!r} plausibly relevant to this dictation's project and topic? "
            "The context may contain a faulty preliminary speech transcript. Consider similar "
            "sounds and project context; absence of exact spelling is not evidence of irrelevance. "
            "Judge relevance only, not whether the speaker actually said it."
        )} for i, term in enumerate(terms)}}
    result = {"terms": terms, "request": body, "status": "prepared-not-sent"}
    if args.send:
        key_name = "OPENROUTER_API_KEY" if args.provider == "openrouter" else "TYPESAFE_API_KEY"
        key = os.environ.get(key_name)
        if not key:
            raise SystemExit(f"{key_name} is required; no request sent")
        endpoint = ("https://openrouter.ai/api/alpha/decisions" if args.provider == "openrouter"
                    else "https://api.typesafe.ai/v1/systemone")
        request = urllib.request.Request(
            endpoint, data=json.dumps(body).encode(),
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=60) as response:
            result["response"] = json.load(response)
        answers = result["response"]["answers"]
        result["ranked_terms"] = sorted([
            {"term": term, "relevance_probability": float(answers[str(i)]["noul"])}
            for i, term in enumerate(terms)], key=lambda x: -x["relevance_probability"])
        result["status"] = "completed"
    args.output.write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()

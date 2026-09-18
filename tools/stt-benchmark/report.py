"""Create a private, local HTML comparison with original audio and word diffs."""
import argparse
import difflib
import html
import json
import os
import pathlib
from score import distance, words


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--results", type=pathlib.Path, required=True)
    p.add_argument("--audio-dir", type=pathlib.Path, required=True)
    args = p.parse_args()
    out = args.results / "comparison.html"
    sections = []
    for clip in sorted(args.audio_dir.glob("*.wav")):
        refpath = clip.with_suffix(".ref.txt")
        ref = refpath.read_text() if refpath.exists() else ""
        audio = html.escape(os.path.relpath(clip.resolve(), out.parent.resolve()), quote=True)
        sections.append(f'<section><h2>{html.escape(clip.name)}</h2><audio controls src="{audio}"></audio>')
        if ref:
            sections.append('<h3>Saved machine reference — verify against audio</h3><p>' + html.escape(ref) + '</p>')
        for path in sorted(args.results.glob(f"*.{clip.stem}.*.json")):
            data = json.loads(path.read_text())
            text = data.get("response", {}).get("text")
            label = html.escape(data["model"] + " / " + data["arm"])
            if data["returncode"] or not isinstance(text, str):
                sections.append(f'<details><summary>{label}: failed</summary></details>')
                continue
            text = text.split("<asr_text>")[-1]
            r, h = words(ref), words(text)
            metric = f"{distance(r,h)}/{len(r)} word edits vs machine reference" if r else "Unscored"
            diff = []
            for tag, a, b, c, d in difflib.SequenceMatcher(None, r, h, autojunk=False).get_opcodes():
                if tag in ("delete", "replace"):
                    diff.append('<del>' + html.escape(' '.join(r[a:b])) + '</del>')
                if tag in ("insert", "replace"):
                    diff.append('<ins>' + html.escape(' '.join(h[c:d])) + '</ins>')
                if tag == "equal":
                    diff.append(html.escape(' '.join(h[c:d])))
            sections.append(f'<details><summary>{label} — {metric}</summary><p>{html.escape(text)}</p>'
                            f'<p class="diff">{" ".join(diff)}</p></details>')
        sections.append('</section>')
    out.write_text('''<!doctype html><meta charset="utf-8"><title>Dictation model comparison</title>
<style>body{font:17px/1.6 system-ui;max-width:1100px;margin:40px auto;padding:0 20px;background:#fafafa;color:#222}
section{margin:35px 0;padding:24px;background:white;border:1px solid #ddd}details{padding:12px 0;border-top:1px solid #ddd}
summary{cursor:pointer;font-weight:600}ins{background:#c6efce}del{background:#ffc7ce}audio{width:100%}.diff{color:#444}</style>
<h1>Dictation model comparison</h1><p>Listen to the original audio to resolve disagreements.
The saved Codex transcripts are comparison references, not human-verified ground truth.
Green/red highlights show word differences; punctuation and case are ignored in these diffs.
GLM whole-clip runs over 30 seconds exceed its reference input window and must not be used for model ranking.</p>
''' + '\n'.join(sections))
    print(out)


if __name__ == "__main__":
    main()

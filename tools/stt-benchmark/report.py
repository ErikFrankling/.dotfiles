"""Create a private, local HTML comparison with original audio and word diffs."""
import argparse
import difflib
import html
import json
import os
import pathlib
import re
from score import distance, words


def diff_markup(reference, hypothesis):
    diff = []
    for tag, a, b, c, d in difflib.SequenceMatcher(None, reference, hypothesis, autojunk=False).get_opcodes():
        if tag in ("delete", "replace"):
            diff.append('<del>' + html.escape(' '.join(reference[a:b])) + '</del>')
        if tag in ("insert", "replace"):
            diff.append('<ins>' + html.escape(' '.join(hypothesis[c:d])) + '</ins>')
        if tag == "equal":
            diff.append(html.escape(' '.join(hypothesis[c:d])))
    return ' '.join(diff)


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
            if data.get("input_limit_exceeded"):
                metric = "EXCLUDED: audio exceeds supported input window"
            punct = lambda t: re.findall(r"\w+(?:['’]\w+)*|[^\w\s]", t)
            comparison = (f'<h4>Words, punctuation, and capitalization</h4><p class="diff">{diff_markup(punct(ref), punct(text))}</p>'
                          f'<h4>Normalized words only</h4><p class="diff">{diff_markup(r, h)}</p>') if ref else ''
            sections.append(f'<details><summary>{label} — {metric}</summary><p>{html.escape(text)}</p>{comparison}</details>')
        sections.append('</section>')
    out.write_text('''<!doctype html><meta charset="utf-8"><title>Dictation model comparison</title>
<style>body{font:17px/1.6 system-ui;max-width:1100px;margin:40px auto;padding:0 20px;background:#fafafa;color:#222}
section{margin:35px 0;padding:24px;background:white;border:1px solid #ddd}details{padding:12px 0;border-top:1px solid #ddd}
summary{cursor:pointer;font-weight:600}ins{background:#c6efce}del{background:#ffc7ce}audio{width:100%}.diff{color:#444}
input{font:inherit;padding:8px;width:90%}h4{margin-bottom:4px}</style>
<h1>Dictation model comparison</h1><p>Listen to the original audio to resolve disagreements.
The saved Codex transcripts are comparison references, not human-verified ground truth.
Green/red highlights show differences, including punctuation and capitalization in the first diff.
The numerical word-edit count still ignores punctuation and case. An excluded input-window run is not a valid quality score.</p>
<label>Filter models or experiment arms <input type="search" id="filter" placeholder="For example: gemma, prosody, cohere, vibevoice"></label>
<script>document.getElementById('filter').addEventListener('input',function(){
const q=this.value.toLowerCase();document.querySelectorAll('details').forEach(d=>{
d.hidden=!d.querySelector('summary').textContent.toLowerCase().includes(q);});});</script>
''' + '\n'.join(sections))
    print(out)


if __name__ == "__main__":
    main()

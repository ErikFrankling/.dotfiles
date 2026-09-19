"""Same-recording comparison, with no machine transcript designated as truth."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
from score import distance, words
from report import technology


CASES = [
    ('opening', '0:00–0:42 — project and tool names',
     'Both blind excerpt recognizers recover naiaclaw and Claude Code with the supplied vocabulary. '
     'Codex full runs 1 and 2 miss both spellings. Known project spellings make this a concrete useful difference.'),
    ('portal', '2:24–2:54 — same as Portal',
     'Both blind recognizers say “the same as Portal”, agreeing with Codex. '
     'The local vocabulary-only run says “someone’s portal”: evidence of a local recognition error.'),
    ('tenant', '3:28–4:23 — self-correction about tenant creation',
     'The speaker changes their proposal mid-speech. Both checks retain that reversal. '
     'A cleaner rewritten plan would not be a faithful transcript. Compare repetitions and question boundaries below.'),
    ('information', '4:46–5:28 — service/server and already/only',
     'Both blind recognizers produce “service script” and “already going to give us”. '
     'Codex run 2 agrees; run 1 and the local vocabulary-only transcript say “only”. '
     'This is evidence against assuming the first Codex result is correct. The earlier blanket claim that '
     '“service script” was necessarily an error is retracted; judge each occurrence separately.'),
    ('tone', '5:43–6:18 — Correct? Right?',
     'Both blind recognizers punctuate “Correct?” as a question. They disagree on whether “Right” is also a question. '
     'Codex run 1 has “Correct. Right.” and run 2 “correct? Right.” '
     'The first question has cross-model support; the second remains unresolved. This is not a controlled paired-tone experiment.'),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).parent/'results')
    args = parser.parse_args()
    root = args.root
    out = root/'codex-long'
    audio = Path('/home/erikf/stt-tone-test.wav')
    expected = hashlib.sha256(audio.read_bytes()).hexdigest()
    records = []
    paths = list((root/'cloud').glob('*.stt-tone-test.*.json'))
    paths += list((root/'contextual-round').glob('*.stt-tone-test.*.json'))
    paths += list(out.glob('*.stt-tone-test.*.json'))
    for p in sorted(paths):
        d = json.loads(p.read_text())
        if d.get('audio_sha256') != expected:
            continue
        text = d.get('response', {}).get('text', '')
        if d.get('returncode') != 0 or not text or d.get('input_limit_exceeded'):
            continue
        arm = d['arm'].rsplit('.stt-tone-test.', 1)[-1]
        if any(x in arm for x in ('draft', 'preview', 'chunks')):
            continue
        records.append(dict(label=d['model']+' / '+arm, text=text, tech=technology(d),
            seconds=d.get('elapsed_seconds'), file=p.name,
            names=len(re.findall(r'\bnaiaclaw\b', text, re.I)),
            claude=bool(re.search(r'\bclaude\s+code\b', text, re.I))))
    records.sort(key=lambda r: (r['tech'], r['label']))
    codex = [r for r in records if r['label'].startswith('codex-desktop')]
    repeats = []
    for i, a in enumerate(codex):
        for b in codex[i+1:]:
            repeats.append({'a': a['label'], 'b': b['label'],
                'normalized_word_edits': distance(words(a['text']), words(b['text']))})
    sections = []
    for clip, title, interpretation in CASES:
        outputs = []
        for p in sorted((out/'investigation').glob(f'*.{clip}.*.json')):
            d = json.loads(p.read_text())
            if d.get('returncode') == 0:
                outputs.append('<details open><summary>'+html.escape(d['model'])+'</summary><p>'+
                               html.escape(d['response']['text'])+'</p></details>')
        sections.append('<section><h2>'+html.escape(title)+'</h2><audio controls preload="none" src="'+
                        clip+'.wav"></audio><p>'+html.escape(interpretation)+'</p>'+''.join(outputs)+'</section>')
    payload = json.dumps(records, ensure_ascii=False).replace('<', '\\u003c')
    page = '''<!doctype html><meta charset="utf-8"><title>Same-audio transcription study</title>
<style>body{font:17px/1.6 system-ui;max-width:1200px;margin:30px auto;padding:0 20px;background:#fafafa;color:#222}
section{background:white;padding:20px;margin:24px 0;border:1px solid #ddd}table{border-collapse:collapse;width:100%}
td,th{padding:8px;text-align:left;border-bottom:1px solid #ddd}select{max-width:100%;font:inherit;margin:8px}
ins{background:#cef0cf;text-decoration:none}del{background:#f7cccc}audio{width:100%}#diff{white-space:pre-wrap}
summary{cursor:pointer;font-weight:600}p{overflow-wrap:anywhere}</style>
<h1>The same 6m39s recording, including real Codex dictation</h1>
<p>Every full-recording result below has the identical WAV SHA-256. Codex is the actual desktop HTTP dictation
function, not an OpenAI API substitute. No transcript is designated ground truth. Failed runs, text-only revisions,
draft-conditioned revisions, and chunked runs are excluded from this table. Exact name counts are not verified recall.</p>
<audio controls preload="none" src="../technology-comparison/audio/stt-tone-test.wav"></audio>
<p><strong>Finding:</strong> all three Codex runs miss the exact project/tool names. Contextual Gemini keeps both
names in two runs, but changes “already” to “solely” in its repeat. Neither is an error-free reference.
The audio investigations below also identify a local error and a likely Codex error.</p>
<h2>Full-recording results</h2><p>Compare like context conditions: Codex received only audio; vocabulary/context runs
received additional information. The desktop dictionary endpoint returned 404, so a matched dictionary condition
could not be tested. Backend model identity is undisclosed. Times are observations, not controlled speed rankings.</p>
<p>Grouped by recognition mechanism; the ordering is not an accuracy ranking.</p>
<table><thead><tr><th>Technology</th><th>System / context condition</th><th>Seconds</th><th>naiaclaw spellings</th><th>Claude Code present</th></tr></thead><tbody id="rows"></tbody></table>
<h2>Compare any two full transcripts</h2><p>Red means wording in A; green means wording in B. Neither color means
correct or incorrect. This comparison includes punctuation and case. Use the recording to judge differences.</p>
<label>A <select id="a"></select></label><label>B <select id="b"></select></label><p id="diff"></p>
<h2>Audio investigation</h2><p>Five excerpts, two independently trained audio models per excerpt. Both received
the same 18-term vocabulary and original audio, but no candidate transcripts or proposed answers. Excerpt boundaries
are selected for investigation and may cut a word at an edge. These are corroborating model judgments, not human labels.</p>
''' + ''.join(sections) + r'''
<script>
const records=PAYLOAD;const A=document.getElementById('a'),B=document.getElementById('b');
for(const [i,r] of records.entries()){
 for(const s of [A,B]){const o=document.createElement('option');o.value=i;o.textContent=r.label;s.append(o)}
 const tr=document.createElement('tr');for(const x of [r.tech,r.label,r.seconds?.toFixed(1)??'—',r.names,r.claude?'Yes':'No']){
 const td=document.createElement('td');td.textContent=x;tr.append(td)}document.getElementById('rows').append(tr);
}
A.value=Math.max(0,records.findIndex(r=>r.label.includes('codex-desktop')));
B.value=Math.max(0,records.findIndex(r=>r.label.includes('gemini-3.8-flash')&&r.label.endsWith('/ vocabulary18')));
function render(){const tokenize=s=>s.match(/\w+(?:['’]\w+)*|[^\w\s]/gu)||[];
const a=tokenize(records[A.value].text),b=tokenize(records[B.value].text),m=b.length+1;
const dp=new Uint16Array((a.length+1)*m);
for(let i=a.length-1;i>=0;i--)for(let j=b.length-1;j>=0;j--)dp[i*m+j]=a[i]===b[j]?1+dp[(i+1)*m+j+1]:Math.max(dp[(i+1)*m+j],dp[i*m+j+1]);
const root=document.getElementById('diff');root.replaceChildren();let i=0,j=0;
while(i<a.length||j<b.length){let tag='span',word;
if(i<a.length&&j<b.length&&a[i]===b[j]){word=a[i++];j++}
else if(j<b.length&&(i===a.length||dp[i*m+j+1]>=dp[(i+1)*m+j])){tag='ins';word=b[j++]}
else{tag='del';word=a[i++]}
const el=document.createElement(tag);el.textContent=word+' ';root.append(el)} }
A.onchange=B.onchange=render;render();</script>'''.replace('PAYLOAD', payload)
    (out/'study.html').write_text(page)
    (out/'study-summary.json').write_text(json.dumps({'audio_sha256': expected,
        'full_recording_conditions': len(records), 'codex_repeat_disagreements': repeats,
        'records': [{k:v for k,v in r.items() if k != 'text'} for r in records]}, indent=2)+'\n')
    print(f'{out}/study.html: {len(records)} matching-hash full-recording conditions')


if __name__ == '__main__':
    main()

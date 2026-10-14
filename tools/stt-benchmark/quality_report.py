"""Reproducible ranking against an explicitly provisional, reviewed reference."""
import difflib
import hashlib
import html
import json
import re
from pathlib import Path
from score import distance
from report import technology
from feature_matrix import render as render_feature_matrix
from pairwise_view import render as render_pairwise

ROOT = Path(__file__).parent / 'results'
OUT = ROOT / 'quality-ranking'

def normalize(text):
    text = text.lower().replace('’', "'").replace('‘', "'")
    text = re.sub(r'\[(?:silence|breathing|human sounds|environmental sounds|noise|unintelligible speech)\]', ' ', text)
    for a, b in {"i'm":"i am", "we've":"we have", "don't":"do not", "doesn't":"does not", "that's":"that is", "it's":"it is", "we're":"we are", "you're":"you are", "they're":"they are", "won't":"will not", "shouldn't":"should not", "haven't":"have not", "you'll":"you will", "gonna":"going to", "wanna":"want to", "cuz":"because", 'get_token':'get token', 'gettoken':'get token', 'username':'user name', 'planet9':'planet nine', 'planet 9':'planet nine', 'portaldev':'portal dev', '100':'a hundred'}.items():
        text = re.sub(r'(?<!\w)'+re.escape(a)+r'(?!\w)', b, text)
    tokens = re.findall(r"[a-z0-9]+(?:'[a-z]+)?", text)
    tokens = [t for t in tokens if t not in ('um','uh','erm','uhm')]
    # Function-word stutters only: do not erase emphatic no/no or very/very.
    out = []
    for t in tokens:
        if out and t == out[-1] and t in {'i','you','we','the','a','to','for','of','in','is','that','or','auto','portal'}:
            continue
        out.append(t)
    for phrase in [('in','the'),('planet','nine')]:
        n=len(phrase);i=0
        while i+2*n<=len(out):
            if tuple(out[i:i+n])==phrase and out[i:i+n]==out[i+n:i+2*n]:del out[i+n:i+2*n]
            else:i+=1
    return out


def ordinary_score(ref, hyp):
    """Diagnostic: mask reference-aligned proper-name spans, retaining other edits.

    Name-associated edits are excluded, not magically corrected in the output.
    Mixed name/ordinary-word replacement blocks are ambiguous and excluded whole.
    """
    names={'naiaclaw','claude','codex','naia','planet','nine','oauth','mcp'}
    count=sum(w not in names for w in ref);errors=0
    for tag,i,j,k,l in difflib.SequenceMatcher(None,ref,hyp,autojunk=False).get_opcodes():
        if tag=='equal':continue
        if any(w in names for w in ref[i:j]):continue
        if i==j and any(w in names for w in ref[max(0,i-1):i+1]):continue
        errors+=distance(ref[i:j],hyp[k:l])
    return round(max(0,100*(1-errors/count)),2)

def records():
    sha = json.loads((OUT/'manifest.json').read_text())['audio_sha256']
    found=[]
    for folder in ['cloud','contextual-round','codex-long','tone-round/results','frontier-round']:
        for p in sorted((ROOT/folder).glob('*.stt-tone-test.*.json')):
            d=json.loads(p.read_text())
            if d.get('audio_sha256') != sha or d.get('returncode') != 0 or d.get('input_limit_exceeded') or d.get('output_validity')=='not-a-transcript':continue
            text=d.get('response',{}).get('text')
            if not isinstance(text,str) or not text.strip():continue
            d['source']=str(p.relative_to(ROOT));d['text']=text;found.append(d)
    return found

def category(d):
    n=d['model'].lower();arm=d['arm']
    if 'textdraft' in arm:return 'Text-only cleanup of an ASR draft'
    if 'audiodraft' in arm or arm=='drafts':return 'Audio + draft reconsideration'
    if n.startswith('codex'):return 'Codex dictation · backend undisclosed'
    if n.startswith('vibevoice'):return 'Whole-recording autoregressive ASR + vocabulary'
    if n.startswith('granite-nar'):return 'CTC draft + trained parallel editor'
    if n.startswith(('qwen-asr','cohere')):return 'Chunked autoregressive ASR'
    if n.startswith(('gemma','qwen3-omni')):return 'Instruction-following audio-language model'
    if d.get('technology')=='dictation-product':return 'Packaged dictation product'
    if d.get('technology')=='audio-instruction':return 'Instruction-following audio-language model'
    return 'Dedicated hosted speech recognizer'

def capabilities(d):
    n=d['model'];local='/' not in n and not n.startswith('codex')
    if d.get('technology')=='dictation-product':
        return 'Cloud', 'Public product configuration; custom vocabulary not tested', 'Provider-managed', 'See recorded demo method and limits'
    if n.startswith('vibevoice'):
        return 'Local GPU', '18 names + ~1k characters worked; 6.2k context hit GPU guard', '16.9 GiB total VRAM / 1.44 GiB anonymous RAM (compact-context run)', 'Whole recording; live preview not integrated'
    if n.startswith('gemma'):
        return 'Local GPU', '18 names tested; 30-second documented audio window', 'Per-chunk resource peaks recorded', '16 chunks here; streaming not tested'
    if n.startswith('audio-flamingo-next'):
        return 'Local GPU', 'Audio plus instructions; see tested vocabulary condition', 'ROCm; per-run GPU and host memory recorded', 'Whole-recording final output; streaming not tested'
    if n.startswith('qwen3-omni'):
        offload=any(r.get('cpu_offload_experiment') for r in [d,*d.get('chunk_results',[])])
        return ('Local GPU + CPU' if offload else 'Local GPU'), 'See vocabulary condition', 'Temporary offload experiment; unloaded after testing' if offload else 'Per-run resources recorded', ('Chunked' if d.get('chunk_results') else 'Whole-recording')+' final output; streaming not tested'
    if local:return 'Local GPU', '18 names tested for Qwen; no context condition here for Cohere/Granite', 'Fully GPU runs; comparable peak RAM/VRAM not recorded', '28-second chunks here; live preview not measured'
    if n.startswith('codex'):return 'Cloud', 'Audio only tested; dictionary endpoint returned 404', 'Remote inference', 'Whole-recording upload; preview not measured'
    if n.startswith('google/gemini'):return 'Cloud', '400 names and ~68k-character instruction tested; Jev selection also tested', 'Remote inference', 'Whole-recording upload; preview not measured'
    return 'Cloud', 'See plain / vocabulary / draft conditions below; not a vendor maximum', 'Remote inference', 'Final response tested; streaming latency not measured'

# Content checkpoints are narrow audits, not a substitute for all-word measurement.
CHECKS=[('Wants implementation',r'now i (?:do not )?want to implement it',r'now i want to implement it'),
('Automatic authentication',r'auto.{0,30}authenticat\w*',r'auto.{0,30}authenticat\w*'),
('Do not touch shared dev',r'i am not going to let you touch portal dev',r'i am not going to let you touch portal dev'),
('Tenant self-correction',r'no fuck.{0,30}redo',r'no fuck.{0,30}redo'),
('Create tenant on registration',r'tenant gets created in the database',r'tenant gets created in the database'),
('Do not duplicate state',r'do not need to duplicate that state',r'do not need to duplicate that state'),
('Already provides information',r'(?:already|only|solely) going to give us all the information',r'already going to give us all the information'),
('Not implemented yet',r'have not implemented it yet',r'have not implemented it yet')]
QUESTIONS=['enough information to set up a new tenant','as soon as you log in right','if it has instances right','as soon as a user registers right','not included in the token','correct','for now we do not have that right']

EXPLANATIONS={
 'Packaged dictation product': ('Product-level comparison', 'Includes the product’s recognition and any enabled cleanup.', 'Public demo/tool result; not necessarily identical to the paid desktop configuration.'),
 'Instruction-following audio-language model': ('Best observed quality', 'Takes audio plus vocabulary or project documents. The leading Gemini conditions preserve names and ordinary wording together.', 'More context is not automatically better: rich-context and repeated runs still change already to solely. The reference scaffold also favors the vocabulary18 run.'),
 'Audio + draft reconsideration': ('Close to the leader; extra work not justified yet', 'Receives the original sound and a first transcript, then writes a revised transcript.', 'No clear gain over direct contextual transcription; some revisions retain the draft’s only/solely error. Timings exclude the first ASR pass.'),
 'Whole-recording autoregressive ASR + vocabulary': ('Strong local dedicated-ASR option', 'Decodes the whole recording with supplied names. Vocabulary improves project spelling and long audio avoids artificial chunk boundaries.', 'Still omits Claude Code and says someone’s portal instead of the same as portal. It also changes already to only. Compact context works; larger context hit the GPU guard.'),
 'Text-only cleanup of an ASR draft': ('Better spelling is not audio verification', 'Can repair a likely project spelling using context.', 'Cannot hear whether a guessed correction is true. It retains the already/only error; first-pass latency must be added.'),
 'Dedicated hosted speech recognizer': ('Fastest strong option', 'Specialized transcription endpoint; MAI gives a complete result in about 2 seconds on this recording.', 'Names remain inconsistent even with vocabulary. Endpoint architecture is undisclosed; this result does not establish that every dedicated recognizer behaves alike.'),
 'Codex dictation · backend undisclosed': ('Fast, but misses your names', 'Actual Codex desktop dictation preserves most ordinary wording with approximately 7-second completion.', 'All three runs miss naiaclaw and Claude Code. One run gets already right; the other two say only. No matched custom-dictionary test was available.'),
 'Chunked autoregressive ASR': ('Faster local option, weaker fidelity here', 'A speech encoder and left-to-right decoder process short chunks. Qwen is faster than the whole-recording local recognizer.', 'Chunk boundaries break sentences and lose words. The vocabulary condition changes I want to implement it into I don’t want to implement it: excluded from recommendation regardless of word score.'),
 'CTC draft + trained parallel editor': ('Editing architecture did not win here', 'Builds an acoustic draft, then uses a trained editor with both left and right transcript context.', 'Misses technical words and many question boundaries on this recording. An editor’s existence does not guarantee superior training or recognition.'),
}

def question_checks(text):
    # Evaluate question mark after the target clause, permitting commas and contractions.
    bits=re.split(r'([?.!])',text);marks={};pending=[]
    for i in range(0,len(bits)-1,2):
        clause=' '.join(normalize(bits[i]));mark=bits[i+1]
        for q in QUESTIONS:
            if q in clause:marks[q]=mark=='?'
    return sum(marks.get(q,False) for q in QUESTIONS),marks

def main():
    reference=(OUT/'reference.txt').read_text();ref=normalize(reference);rs=[]
    for d in records():
        hyp=normalize(d['text']);joined=' '.join(hyp);ed=distance(ref,hyp)
        checks={name:bool(re.search(good,joined)) for name,_,good in CHECKS}
        q,qdetail=question_checks(d['text']);loc,ctx,mem,stream=capabilities(d)
        # Explicit dangerous negation reversal outranks small edit-count differences.
        reversal=bool(re.search(r'(?:but|now) i do not want to implement it',joined))
        rs.append(dict(model=d['model'],arm=d['arm'].rsplit('.stt-tone-test.',1)[-1],tech=category(d),source=d['source'],text=d['text'],score=round(max(0,100*(1-ed/len(ref))),2),ordinary_score=ordinary_score(ref,hyp),names=len(re.findall(r'\bnaiaclaw\b',d['text'],re.I)),claude=bool(re.search(r'\bclaude\s+code\b',d['text'],re.I)),edits=ed,words=len(ref),seconds=d['elapsed_seconds'],checks=checks,check_count=sum(checks.values()),questions=q,question_details=qdetail,reversal=reversal,location=loc,context=ctx,memory=mem,streaming=stream))
    rs.sort(key=lambda d:(d['reversal'],-d['score'],d['seconds']))
    groups={}
    for d in rs:groups.setdefault(d['tech'],[]).append(d)
    def representative(rows):
        # Treat half a word-agreement point as a practical tie, not statistical
        # equivalence. Prefer the explicit content/name checks, then latency.
        eligible=[d for d in rows if not d['reversal'] and d['score']>=rows[0]['score']-0.5]
        return min(eligible or rows, key=lambda d:(-d['check_count'],-int(d['claude']),-d['names'],d['seconds']))
    esc=html.escape
    cards=[]
    for rank,(tech,rows) in enumerate(groups.items(),1):
        b=representative(rows)
        verdict,why,weakness=EXPLANATIONS[tech]
        examples=''.join('<li>'+esc(name)+'</li>' for name,ok in b['checks'].items() if not ok) or '<li>All eight targeted content checks match.</li>'
        detail=''
        for d in rows:
            a=ref;z=normalize(d['text']);diff=[]
            for tag,i,j,k,l in difflib.SequenceMatcher(None,a,z,autojunk=False).get_opcodes():
                if tag=='equal':diff.append(esc(' '.join(z[k:l])))
                else:
                    if i!=j:diff.append('<del>'+esc(' '.join(a[i:j]))+'</del>')
                    if k!=l:diff.append('<ins>'+esc(' '.join(z[k:l]))+'</ins>')
            detail+=f'<details><summary>{esc(d["model"])} · {esc(d["arm"])} — {d["score"]:.1f} / 100 · {d["seconds"]:.1f}s · content {d["check_count"]}/8 · questions {d["questions"]}/7</summary><p>{"⚠ Intent reversal detected. " if d["reversal"] else ""}{esc(d["source"])}</p><p>{" ".join(diff)}</p></details>'
        cards.append(f'<section><div class="rank">{rank}</div><h2>{esc(tech)}</h2><p class="winner"><strong>{esc(verdict)}</strong> — {esc(b["model"])} · {esc(b["arm"])}</p><div class="metrics"><b>{b["score"]:.1f}<small>word agreement / 100</small></b><b>{b["check_count"]}/8<small>content checks</small></b><b>{b["questions"]}/7<small>question boundaries</small></b><b>{b["seconds"]:.1f}s<small>for 6m39s audio</small></b></div><p><strong>Why it performs this way:</strong> {esc(why)}</p><p><strong>What holds it back:</strong> {esc(weakness)}</p><p>Ordinary-word diagnostic: {b["ordinary_score"]:.1f}/100 after excluding name-associated edit spans. Exact naiaclaw: {b["names"]}/9; Claude Code: {"yes" if b["claude"] else "no"}.</p><p><strong>{esc(b["location"])}</strong> · {esc(b["context"])}</p><details><summary>Resources, remaining content checks, all {len(rows)} setups and exact transcript differences</summary><p>{esc(b["memory"])}. {esc(b["streaming"])}.</p><ul>{examples}</ul>{detail}</details></section>')
    data={'reference_sha256':hashlib.sha256(reference.encode()).hexdigest(),'reference_words':len(ref),'records':rs,'method':'Best-estimate machine-assisted reference; readable normalized word agreement, separate content and question checks. Not human WER.'}
    (OUT/'ranking.json').write_text(json.dumps(data,indent=2)+'\n')
    local_choice=representative([d for d in rs if d['location'].startswith('Local')])
    cloud_choice=representative([d for d in rs if d['location']=='Cloud'])
    overview='<section><h2>The choices that matter</h2><p><strong>Quality-first cloud: '+esc(cloud_choice['model']+' / '+cloud_choice['arm'])+'.</strong> <strong>Quality-first local: '+esc(local_choice['model']+' / '+local_choice['arm'])+'.</strong> <strong>Speed-first cloud: MAI.</strong> Adding a draft or a text editor has not demonstrated a clear quality gain.</p><div style="overflow:auto"><table><thead><tr><th>Technology</th><th>Recommended tested setup</th><th>Agreement</th><th>Seconds</th><th>Why choose it?</th></tr></thead><tbody>'
    for tech,rows in groups.items():
        b=representative(rows)
        overview+='<tr>'+''.join('<td>'+esc(str(v))+'</td>' for v in [tech,b['model']+' / '+b['arm'],f'{b["score"]:.1f}',f'{b["seconds"]:.1f}',EXPLANATIONS[tech][0]])+'</tr>'
    overview+='</tbody></table></div><p>Categories ordered by best observed word agreement. Within 0.5 points, the displayed setup favors content/name checks, then speed; this is a practical tie rule, not statistical significance. Intent reversals are disqualified. Gaps around 1 point remain inconclusive on this single recording.</p></section>'
    matrix,matrix_rows=render_feature_matrix(rs,groups,representative,ROOT,EXPLANATIONS)
    overview+=render_pairwise(rs,reference,ROOT)+matrix
    excerpt_path=ROOT/'frontier-round/excerpt350/comparison.json'
    if excerpt_path.exists():
        excerpt=json.loads(excerpt_path.read_text())
        overview+='<section><h2>Commercial demo: matched 349.952-second excerpt</h2><p>These unhinted runs use the same shorter audio. They are separate from the full-recording ranking. Word agreement also penalizes some harmless cleanup; it is not a complete readability or meaning score.</p><div style="overflow:auto"><table><tr><th>Technology / implementation</th><th>Word agreement</th><th>Opening intent reversed?</th><th>Observed seconds</th></tr>'
        for r in excerpt['records']:
            kind='Packaged dictation' if 'demo' in r['model'] else 'Whole-recording ASR' if r['model'].startswith('vibevoice') else 'Audio-language model'
            overview+='<tr>'+''.join('<td>'+esc(str(v))+'</td>' for v in [kind+' / '+r['model'],r['word_agreement'],'YES' if r['opening_intent_reversed'] else 'No',round(r['seconds'],1)])+'</tr>'
        overview+='</table></div><p>Wispr’s demo changed “now I want to implement it” to “I don’t want to implement it.” Gemini and VibeVoice preserved this instruction. Demo results do not establish paid-desktop parity. VibeVoice timing includes cold loading; buffered Wispr timing excludes live playback. <a href="../frontier-round/excerpt350/comparison.json">Methods and source records</a>.</p></section>'
    (OUT/'features.json').write_text(json.dumps(matrix_rows,indent=2)+'\n')
    (OUT/'ranking.html').write_text('''<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Which transcription technology wins?</title><style>body{font:17px/1.55 system-ui;background:#f2f5fa;color:#162238;max-width:1100px;margin:35px auto;padding:0 20px}h1{font-size:36px}section{position:relative;background:white;border:1px solid #d5deea;border-radius:14px;padding:25px;margin:22px 0}h2{margin:0 0 5px;padding-right:40px}.rank{position:absolute;right:24px;font-size:32px;color:#4868ba}.winner{color:#4868ba}.metrics{display:flex;gap:35px;flex-wrap:wrap}.metrics b{font-size:29px}.metrics small{display:block;font-size:13px;font-weight:400}details{margin-top:16px}summary{cursor:pointer;font-weight:600}del{background:#fbd6d6}ins{background:#d2f3da;text-decoration:none}audio{width:100%}.note{background:#fff0cd;padding:18px;border-radius:10px}pre{white-space:pre-wrap}p{overflow-wrap:anywhere}</style><h1>Which transcription technology wins?</h1><p>Quality first. The best tested setup is shown inside each technology category, with its remaining mistakes and practical tradeoffs.</p><p class="note"><strong>Baseline established:</strong> a reviewed, corrected best-estimate transcript of your long naiaclaw recording. Scores measure agreement with that provisional reference—not human-verified accuracy. Small differences (about 1 point) are practically inconclusive on this one recording. Names count as words; meaning checks and punctuation remain visible separately so a dangerous one-word change cannot hide behind a high score.</p><audio controls preload="none" src="../../../../../stt-tone-test.wav"></audio><p>Removing um/uh and function-word stutters is free. Contractions, gonna/going to, Planet9/Planet Nine and common number formatting are normalized. Other wording differences still count, even when some are harmless. The automated bulk judge scores were discarded.</p>'''+''.join(cards)+'<section><h2>The baseline</h2><p>Red in comparisons = reference words missing/changed; green = candidate additions/replacements. Colors describe differences, not certainty.</p><details><summary>Read the full corrected reference</summary><pre>'+esc(reference)+'</pre></details><p><a href="reference-decisions.json">Reference decisions and unresolved alternatives</a> · <a href="ranking.json">All scores and source files</a> · <a href="../codex-long/study.html">Original audio investigations</a></p></section>')
    page=OUT/'ranking.html'
    rendered=page.read_text().replace('<style>','<style>td,th{text-align:left;padding:10px;border-bottom:1px solid #d5deea;font-size:14px}table{border-collapse:collapse;width:100%}')
    rendered=rendered.replace('<audio controls',overview+'<audio controls',1)
    rendered=re.sub(r'<p class="note">.*?</p>', f'<p class="note">Scores compare all {len(rs)} outputs with our corrected best-estimate reference. They are not human-verified accuracy; small gaps are inconclusive. <a href="reference-decisions.json">How the baseline was chosen</a>.</p>', rendered, count=1, flags=re.S)
    rendered=rendered.replace('</body>','')
    rendered+='<p>Ordinary-word diagnostic excludes edit blocks touching known names and may also exclude nearby ordinary words. Content checks are eight explicit phrase checks, not a full semantic metric. Question checks require the expected clause and a question mark; they do not measure tone understanding in isolation. Jev and draft timings exclude preparation; all times are observed samples, not controlled latency distributions.</p>'
    page.write_text(rendered)
    for d in rs:print(f'{d["score"]:5.1f} ordinary {d["ordinary_score"]:5.1f} {d["check_count"]}/8 {d["questions"]}/7 {d["seconds"]:6.1f}s {d["model"]} {d["arm"]}')

if __name__=='__main__':main()

"""Visible, evidence-labelled comparison columns for the long-audio report."""
import html
import json
from pathlib import Path

# Keep measured and unmeasured features in the same table; do not imply absence
# of capability merely because this experiment did not exercise it.
COLUMNS = [
 ('Identity','Technology','tech'),('Identity','Setup / condition','setup'),
 ('Quality','Word agreement /100','score'),('Quality','Ordinary words /100 (approx.)','ordinary'),
 ('Quality','Word edits','edits'),('Quality','Content checks','content'),
 ('Quality','Intent reversal','reversal'),('Quality','Question checks','questions'),
 ('Quality','naiaclaw exact','names'),('Quality','Claude Code','claude'),
 ('Quality','Fillers / repeats','fillers'),('Quality','Tone / sarcasm','tone'),
 ('Quality','General punctuation / casing','punctuation'),('Quality','Numbers / code syntax','numbers'),
 ('Context','Audio available to this pass','audio'),('Context','Audio segmentation','segments'),
 ('Context','Names supplied in this run','vocab'),('Context','Project documents','docs'),
 ('Context','Vocabulary/context benefit','benefit'),('Context','Largest tested name list','max_vocab'),
 ('Context','Largest tested document context','max_docs'),('Context','Vocabulary selector','selector'),
 ('Context','Receives earlier transcript','draft'),('Context','Native context maximum','native_context'),
 ('Speed','Completion seconds','seconds'),('Speed','Audio / processing speed','speed'),
 ('Speed','Timing includes model load','load'),('Speed','Upstream latency included','upstream'),
 ('Speed','Audio-prefix cache reuse','cache'),
 ('Speed','Matched-repeat variation','repeat'),('Speed','Streaming tested','stream'),
 ('Speed','First partial latency','partial'),('Speed','Finalization latency','finalization'),
 ('Hardware','Runs where / privacy','location'),('Hardware','Weights accessible','weights'),
 ('Hardware','Quantization used','quant'),('Hardware','Peak total GPU GiB','vram'),
 ('Hardware','Peak anonymous RAM GiB','ram'),('Hardware','Peak RSS GiB','rss'),
 ('Hardware','Peak process swap MiB','swap'),('Hardware','Large CPU offload','offload'),
 ('Hardware','Residency after run','residency'),('Hardware','API cost for run','cost'),
 ('Extras','Speaker diarization','speakers'),('Extras','Word timestamps','timestamps'),
 ('Extras','Languages / code-switching','languages'),('Extras','Noise / overlap','noise'),
 ('Decision','Why choose this technology','why'),('Decision','Remaining limitation','weakness'),
 ('Decision','Result evidence','source'),
]

def enrich(d, root, explanations):
    raw=json.loads((root/d['source']).read_text());n=d['model'];arm=d['arm']
    local=d['location'].startswith('Local');gemini=n.startswith('google/gemini')
    vibe=n.startswith('vibevoice');qwen=n.startswith('qwen-asr')
    draft='draft' in arm;textonly='textdraft' in arm;selector='jev' in arm
    vocabulary='vocabulary' in arm or 'prompt18' in arm or 'overview18' in arm
    rich='rich-context' in arm or 'overview18' in arm
    vocab=('400' if '400' in arm else 'Jev-selected (see request)' if selector else
           '1' if 'name-only' in n else '18' if vocabulary or rich or draft else 'None / not recorded')
    chunks=raw.get('chunk_results',[])
    samples=list(raw.get('resources',{}).get('samples',[]))
    for result in [raw, *chunks]:
        resources=result.get('resources',{})
        samples.append(resources.get('peak',{}))
        if result is not raw:
            samples.extend(resources.get('samples',[]))
    cpu_offload=any('-ngl' in r.get('command',[]) and
        r['command'][r['command'].index('-ngl')+1] != '999' for r in [raw,*chunks])
    def peak(key,denom=2**30):
        values=[s[key] for s in samples if isinstance(s.get(key),(int,float))]
        return f'{max(values)/denom:.2f}' if values else 'Not measured' if local else 'Remote'
    def cost(r):
        c=r.get('provider_response',{}).get('usage',{}).get('cost')
        if isinstance(c,(int,float)):return c
        children=[cost(x) for x in r.get('chunk_results',[])]
        return sum(children) if children and all(v is not None for v in children) else None
    usd=cost(raw)
    if vibe:benefit='Plain 95.9 → names 97.8–98.1; Claude Code still missing'
    elif qwen:benefit='Plain 95.7 → name-only 95.9; 18 names reverse intent'
    elif gemini and '3.8' in n:benefit='Plain 97.0 → 18 names 97.7–99.1; rich docs 98.2'
    elif gemini:benefit='Plain 95.9 → 18 names 97.8; rich docs 97.2'
    elif n=='openai/gpt-transcribe':benefit='Plain 95.9 → 18 names 96.7'
    elif n=='openai/gpt-audio':benefit='Plain 96.1 → 18 names 97.6'
    elif 'mai-transcribe' in n:benefit='Plain 96.8 → 18 names 97.0'
    elif n.startswith('gemma4'):benefit='Maker prompt 89.2 → vocabulary 71.1; stricter prompt added translations'
    elif n.startswith('qwen3-omni'):benefit='Plain 95.4 → 18 names 97.7; Claude Code still missing'
    elif n.startswith('audio-flamingo-next'):benefit='Simple prompt 89.4; faithful prompt + 18 names 88.9 (two variables changed)'
    elif n=='aqua/avalon-v1.5':benefit='Plain 95.3 → 18 names 96.6; project overview 68.5 twice, with intent reversal'
    else:benefit='No matched context comparison'
    why,_,weakness=explanations[d['tech']]
    if n.startswith('gemma4'):
        why='No quality advantage in these configurations'
        weakness='Vocabulary leakage / omissions with maker prompt; unwanted translations with stricter prompt. Capability ceiling not established.'
    elif n.startswith('audio-flamingo-next'):
        why='Full-GPU audio-language model tested; no observed quality advantage'
        weakness='Sparse punctuation; Nyakla instead of Naiaclaw; misses Claude Code despite vocabulary.'
    elif n.startswith('qwen3-omni'):
        why='Audio-language model supports audio plus a draft; see condition results'
        weakness='Standalone run misses Claude Code and three question checks; temporary CPU offload required on this GPU.'
    elif n=='aqua/avalon-v1.5':
        why='Fast hosted ASR; recognizes Claude Code in this recording'
        weakness='Misspells Naiaclaw despite hints; project-context condition reverses intent. Batch API, not desktop workflow.'
    if d['reversal']:
        why='Excluded from recommendation: changes intent'
        weakness='Changes the opening implementation request into its opposite.'
    repeat=('3 repeats: 95.6–96.6; 7.3–7.5s' if n.startswith('codex') else
            '18-name repeats: 97.7–99.1; 11.7–22.8s' if n=='google/gemini-3.8-flash' else 'No matched repeats')
    return dict(tech=d['tech'],setup=n+' / '+arm,score=f'{d["score"]:.1f}',ordinary=f'{d["ordinary_score"]:.1f}',
        edits=str(d['edits']),content=f'{d["check_count"]}/8',reversal='YES — disqualified' if d['reversal'] else 'Not detected by targeted check',
        questions=f'{d["questions"]}/7',names=f'{d["names"]}/9',claude='Yes' if d['claude'] else 'No',
        fillers='um/uh + function-word stutters ignored',tone='Not isolated / paired-tone test missing',
        punctuation='Only 7 question clauses scored',numbers='Not separately scored',
        audio='No — text draft only' if textonly else 'Yes',
        segments=f'{len(chunks)} chunks' if chunks else 'Whole 398.7-second recording',
        vocab=vocab,docs='~1k characters' if 'overview18' in arm else '~68k-character total instruction' if rich else 'No project-document condition',
        benefit=benefit,max_vocab='400 (Flash); not a vendor limit' if gemini else '18' if vocabulary or vibe or qwen or n.startswith(('gemma4','qwen3-omni','audio-flamingo-next')) else 'Not established',
        max_docs='~68k-character instruction' if gemini else '~1k works; 6.2k hit GPU guard' if vibe else 'Not established',
        selector='Jev' if selector else 'None',draft='Yes' if draft or 'preview' in arm else 'No',
        native_context='30 seconds audio per request (model card)' if n.startswith('gemma4') else 'Audio processor configured for 1800s; 398.7s tested' if n.startswith('audio-flamingo-next') else 'Not established here; text-token limit ≠ audio duration',
        seconds=f'{d["seconds"]:.1f}',speed=f'{raw.get("audio_seconds",398.739625)/d["seconds"]:.1f}× realtime',
        load='Yes' if raw.get('timing_includes_model_load') else 'No' if raw.get('timing_includes_model_load') is False else 'Not recorded' if local else 'Provider-internal / unknown',
        cache='Reused audio prefix' if raw.get('prompt_cache_reused') else 'No prior request' if raw.get('prompt_cache_reused') is False else 'Disabled by request' if raw.get('prompt_cache_requested') is False else 'Not recorded',
        upstream='NO — add draft/selector time' if draft or selector or 'preview' in arm else 'No upstream pass',repeat=repeat,
        stream='No live benchmark',partial='Not measured',finalization='Not measured separately',
        location='Local; audio stays on machine' if local else 'Cloud; audio/text sent off-device',
        weights='Yes, locally available' if local else 'Closed / backend undisclosed',
        quant='BF16' if qwen or n.endswith('-bf16') else 'Q4_K_M; Q8 projector' if n.startswith('qwen3-omni') else 'Int8 weights / BF16 activations' if n.endswith('-int8') else 'Q8' if local else 'Undisclosed',vram=peak('vram_bytes'),ram=peak('anonymous_bytes'),rss=peak('rss_bytes'),swap=peak('swap_bytes',2**20),
        offload=('Temporary CPU offload experiment' if cpu_offload else 'All model parameters verified on GPU' if n.startswith('audio-flamingo-next') else 'Full GPU offload requested') if local else 'N/A',residency='Unloaded; process-lifetime runner' if vibe or n.startswith(('gemma4','qwen3-omni','audio-flamingo-next')) else 'No persistent deployment tested' if local else 'Provider-managed',
        cost=f'${usd:.4f}' if usd is not None else 'No API fee; electricity unmeasured' if local else 'Not reported',
        speakers='Speaker turns returned; accuracy untested' if raw.get('response',{}).get('speaker_turns') else 'Not tested',
        timestamps='Not evaluated',languages='English tested; multilingual/code-switching untested',noise='Not separately tested',
        why=why,weakness=weakness,source=d['source'])

def render(records, groups, representative, root, explanations):
    enriched={d['source']:enrich(d,root,explanations) for d in records}
    selected={representative(rows)['source'] for rows in groups.values()}
    esc=html.escape
    heads=''.join(f'<th data-group="{g}">{esc(title)}</th>' for g,title,_ in COLUMNS)
    rows=[]
    for tech,items in groups.items():
        ordered=sorted(items,key=lambda d:d['source'] not in selected)
        for d in ordered:
            e=enriched[d['source']];is_selected=d['source'] in selected
            cells=''.join('<td>'+esc(e[key])+'</td>' for _,_,key in COLUMNS)
            rows.append(f'<tr data-recommended="{str(is_selected).lower()}">'+cells+'</tr>')
    controls=''.join(f'<button type="button" data-jump="{g}">{g}</button>' for g in dict.fromkeys(g for g,_,_ in COLUMNS) if g!='Identity')
    return '''<section id="feature-matrix"><h2>All comparison columns</h2>
<p>One row per tested model and context condition. Uncheck “Show all” to keep one recommended setup per technology. Every column stays in the table; scroll sideways or jump to a column group. “Not measured” is a gap in this study, not a claim that a model lacks the feature.</p>
<label><input type="checkbox" id="all-runs" checked> Show all '''+str(len(records))+''' tested runs</label><div class="matrix-jumps">'''+controls+'''</div>
<div class="matrix-scroll" tabindex="0" aria-label="All transcription features; scroll horizontally"><table id="all-features"><thead><tr>'''+heads+'</tr></thead><tbody>'+''.join(rows)+'''</tbody></table></div>
<p>Word scores use the provisional reference. The ordinary-word diagnostic is approximate. Context benefits are same-family observed comparisons, not causal proof. Peaks are sampled per run; total GPU memory includes the desktop. RSS and anonymous RAM differ. Streaming, tone, overlap and multilingual quality remain unmeasured.</p></section>
<style>
#feature-matrix{max-width:none}.matrix-scroll{max-height:72vh;overflow:auto;border:1px solid #d5deea;isolation:isolate}
#all-features{width:max-content;table-layout:fixed}#all-features td,#all-features th{min-width:155px;max-width:250px;width:175px;vertical-align:top;white-space:normal;overflow-wrap:anywhere;background:white;font-size:13px}
#all-features th{position:sticky;top:0;z-index:3;background:#e6edf9}#all-features td:first-child,#all-features th:first-child{position:sticky;left:0;width:220px;min-width:220px;max-width:220px;z-index:2;background:#f1f5fc}
#all-features th:first-child{z-index:4}#all-features tr[data-recommended="true"] td{border-top:2px solid #7996c7}
#all-features td:nth-child(2),#all-features th:nth-child(2){position:sticky;left:var(--identity-width,240px);z-index:2;background:#f1f5fc}
#all-features th:nth-child(2){z-index:4}
.matrix-jumps{display:flex;flex-wrap:wrap;gap:8px;margin:12px 0}.matrix-jumps button{font:inherit;border:1px solid #a9b9d1;border-radius:6px;background:#edf2fa;padding:6px 12px;cursor:pointer}
</style><script>
document.getElementById('all-runs').addEventListener('change',e=>{document.querySelectorAll('#all-features tbody tr').forEach(r=>r.hidden=!e.target.checked&&r.dataset.recommended!=='true')});
const identity=document.querySelector('#all-features th:first-child');document.getElementById('all-features').style.setProperty('--identity-width',identity.offsetWidth+'px');
document.querySelectorAll('[data-jump]').forEach(b=>b.addEventListener('click',()=>{const t=document.querySelector('#all-features th[data-group="'+b.dataset.jump+'"]');const box=document.querySelector('.matrix-scroll');const pinned=identity.offsetWidth+document.querySelector('#all-features th:nth-child(2)').offsetWidth;box.scrollTo({left:t.offsetLeft-pinned,behavior:'smooth'})}));
</script>''',list(enriched.values())

"""Build the side-by-side taste-test page from results/llm.json and results/tts.json.

usage: python make_page.py STUDY_DIR
Audio is read from STUDY_DIR/private/audio/<engine>.opus (not committed).
"""

import html
import json
import sys
from pathlib import Path

study = Path(sys.argv[1])
llm = json.loads((study / "results/llm.json").read_text())
tts = json.loads((study / "results/tts.json").read_text())
inputs = {p.stem: p.read_text() for p in sorted((study / "inputs").glob("*.md"))}
tts_text = (study / "inputs/tts-text.txt").read_text().strip()
asr = json.loads((study / "results/asr-check.json").read_text()) if (study / "results/asr-check.json").exists() else {}
e = html.escape

# Room left on the PC GPU for read-aloud while dictation is resident:
# 20 GB - ~15.3 GB dictation peak incl. desktop - ~1 GB safety = ~3.7 GB.
BUDGET = 3.7

INPUT_NAMES = {"options": "Message 1: the options answer", "vram-plan": "Message 2: the VRAM plan answer"}


def llm_card(key, m, run_key):
    if "error" in m:
        return ""
    r = m["runs"][run_key]
    vram = m.get("vram_loaded_gib")
    fits = vram is not None and vram <= BUDGET
    badge = (f'<span class="b ok">fits next to dictation · {vram} GB</span>' if fits else
             f'<span class="b warn">too big to stay loaded · {vram} GB</span>' if vram else
             '<span class="b warn">reference only · ~16 GB</span>')
    think = '<span class="b info">thinks first</span>' if r.get("output_tokens", 0) > 400 else ""
    words = len(r["text"].split())
    return f"""
<article class="card" data-key="{e(key)}">
  <header><h3>{e(m['label'])}</h3><button class="star" data-kind="llm" data-key="{e(key)}" aria-label="favourite">☆</button></header>
  <div class="meta">{badge}{think}<span class="b">{e(m['released'])}</span></div>
  <p class="summary">{e(r['text']) or '<em>(empty output)</em>'}</p>
  <dl class="nums">
    <div><dt>time to full summary</dt><dd>{r.get('wall_s') or round(r['prefill_ms'] / 1000 + r['output_tokens'] / r['decode_tps'], 1)} s</dd></div>
    <div><dt>speed</dt><dd>{r['decode_tps']} tok/s</dd></div>
    <div><dt>load from disk</dt><dd>{m['load_s'] if m.get('load_s') is not None else '—'} s</dd></div>
    <div><dt>length</dt><dd>{words} words</dd></div>
  </dl>
</article>"""


def where(t):
    if t["vram_added_gib"] < 0.3:
        return '<span class="b ok">CPU · no GPU memory</span>'
    # The ~3.7 GB of spare room is shared with the summary model (1.5-3.3 GB).
    if t["vram_added_gib"] <= BUDGET - 1.5:
        return f'<span class="b ok">GPU · {t["vram_added_gib"]} GB, fits beside dictation + a 2B summary model</span>'
    if t["vram_added_gib"] <= BUDGET:
        return f'<span class="b warn">GPU · {t["vram_added_gib"]} GB, fits beside dictation only with no GPU summary model</span>'
    return f'<span class="b warn">GPU · {t["vram_added_gib"]} GB, unloads dictation</span>'


def tts_card(key, t):
    if "error" in t:
        return f"""
<article class="card dim"><header><h3>{e(t['label'])}</h3></header>
<div class="meta"><span class="b warn">did not run here</span><span class="b">{e(t['released'])}</span></div>
<p class="summary">{e(t.get('why', 'failed on this machine'))}</p></article>"""
    return f"""
<article class="card" data-key="{e(key)}">
  <header><h3>{e(t['label'])}</h3><button class="star" data-kind="tts" data-key="{e(key)}" aria-label="favourite">☆</button></header>
  <div class="meta">{where(t)}<span class="b">{e(t['params'])}</span><span class="b">{e(t['released'])}</span><span class="b">{e(t['license'])}</span></div>
  <audio controls preload="none" src="private/audio/{e(key)}.opus"></audio>{f'<p class="note">{e(t["note"])}</p>' if t.get('note') else ''}
  <dl class="nums">
    <div><dt>first sentence ready</dt><dd>{t['first_sentence_s']} s</dd></div>
    <div><dt>speed vs real time</dt><dd>{round(1 / t['rtf'], 1)}×</dd></div>
    <div><dt>voice</dt><dd>{e(t['voice'])}</dd></div>
    <div><dt>audio length</dt><dd>{t["audio_s"]} s</dd></div>
    <div><dt>words heard (Whisper)</dt><dd>{round(asr[key]["recall"] * 100) if key in asr else "—"}%</dd></div>
  </dl>
</article>"""


order = sorted(llm, key=lambda k: (llm[k].get("vram_loaded_gib") or 99))
llm_sections = "".join(
    f"""<section class="tab" data-tab="{k}" {'hidden' if i else ''}>
<details><summary>Show the original message ({len(v.split())} words)</summary><pre>{e(v)}</pre></details>
<div class="grid">{''.join(llm_card(key, llm[key], k) for key in order)}</div></section>"""
    for i, (k, v) in enumerate(inputs.items()))
tabs = "".join(f'<button class="tabbtn{" on" if i == 0 else ""}" data-tab="{k}">{e(INPUT_NAMES.get(k, k))}</button>'
               for i, k in enumerate(inputs))
tts_order = sorted(tts, key=lambda k: ("error" in tts[k], tts[k].get("vram_added_gib", 99)))
tts_cards = "".join(tts_card(k, tts[k]) for k in tts_order)

page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="icon" href="data:,"><title>Read-aloud taste test · 2026-10-18</title>
<style>
:root{{--bg:#101114;--fg:#e8e8ea;--mut:#9a9ca3;--card:#1a1b20;--line:#2a2c33;--ok:#3fb27f;--warn:#d9a43a;--info:#5b8def;--acc:#f0c040}}
@media (prefers-color-scheme: light){{:root{{--bg:#f6f6f4;--fg:#1c1d20;--mut:#62646b;--card:#fff;--line:#e2e2de}}}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}}
main{{max-width:1500px;margin:auto;padding:20px 16px 80px}}
h1{{font-size:22px;margin:0 0 4px}}h2{{font-size:18px;margin:34px 0 8px}}p.lead{{color:var(--mut);margin:0 0 6px;max-width:80ch}}
.tabs{{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}}
.tabbtn{{background:var(--card);color:var(--fg);border:1px solid var(--line);border-radius:999px;padding:7px 14px;cursor:pointer;font:inherit}}
.tabbtn.on{{border-color:var(--acc);color:var(--acc)}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(330px,1fr));gap:12px;margin-top:12px}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 16px;display:flex;flex-direction:column;gap:8px}}
.card.dim{{opacity:.6}}.card.fav{{border-color:var(--acc);box-shadow:0 0 0 1px var(--acc)}}
.card header{{display:flex;justify-content:space-between;align-items:center}}h3{{margin:0;font-size:16px}}
.star{{background:none;border:0;color:var(--acc);font-size:22px;cursor:pointer;line-height:1}}
.meta{{display:flex;flex-wrap:wrap;gap:6px}}
.b{{font-size:12px;padding:2px 8px;border-radius:999px;border:1px solid var(--line);color:var(--mut)}}
.b.ok{{color:var(--ok);border-color:color-mix(in srgb,var(--ok) 45%,transparent)}}
.b.warn{{color:var(--warn);border-color:color-mix(in srgb,var(--warn) 45%,transparent)}}
.b.info{{color:var(--info);border-color:color-mix(in srgb,var(--info) 45%,transparent)}}
.summary{{margin:0;white-space:pre-wrap;flex:1}}
.nums{{display:grid;grid-template-columns:1fr 1fr;gap:4px 12px;margin:0;font-size:13px}}
.nums div{{display:flex;justify-content:space-between;border-top:1px solid var(--line);padding-top:4px}}dt{{color:var(--mut)}}dd{{margin:0 0 0 8px;font-variant-numeric:tabular-nums;white-space:nowrap}}
audio{{width:100%}}.note{{margin:0;font-size:13px;color:var(--mut)}}details{{margin:8px 0}}summary{{cursor:pointer;color:var(--mut)}}
pre{{white-space:pre-wrap;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px;font-size:13px;max-height:420px;overflow:auto}}
blockquote{{margin:10px 0;padding:10px 14px;border-left:3px solid var(--acc);background:var(--card);border-radius:0 10px 10px 0}}
#picks{{position:fixed;left:0;right:0;bottom:0;background:var(--card);border-top:1px solid var(--line);padding:10px 16px;font-size:14px;display:flex;gap:12px;align-items:center;flex-wrap:wrap}}
#picks button{{font:inherit;padding:5px 12px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--fg);cursor:pointer}}
</style></head><body><main>
<h1>Read-aloud taste test</h1>
<p class="lead">Every model got the same prompt and the same assistant messages from this thread. All ran locally on the RX 7900 XT, one at a time, Q4_K_M, thinking off.
Badges show whether a model can stay loaded next to dictation (about {BUDGET} GB of room). Tap ☆ on the ones you like; your picks show at the bottom.</p>
<details><summary>The prompt every summary model got</summary><pre>{e((Path(__file__).parent / 'prompt.md').read_text() if (Path(__file__).parent / 'prompt.md').exists() else '')}</pre></details>

<h2>1 · Summary models</h2>
<div class="tabs">{tabs}</div>
{llm_sections}

<h2>2 · Voices</h2>
<p class="lead">Every voice reads the same summary (Qwen3.5-4B's version of message 1), sentence by sentence, the way read-aloud will stream it.
"First sentence ready" is how long you would wait after the summary starts arriving.</p>
<blockquote>{e(tts_text)}</blockquote>
<div class="grid">{tts_cards}</div>
</main>
<div id="picks"><strong>Your picks:</strong><span id="pickl">none yet</span><button id="copy">Copy</button></div>
<script>
const KEY='read-aloud-picks';const picks=new Set(JSON.parse(localStorage.getItem(KEY)||'[]'));
function render(){{document.querySelectorAll('.star').forEach(b=>{{const id=b.dataset.kind+':'+b.dataset.key;const on=picks.has(id);b.textContent=on?'★':'☆';b.closest('.card').classList.toggle('fav',on)}});
const names=[...picks].map(id=>{{const [k,key]=id.split(':');const c=document.querySelector(`.star[data-kind="${{k}}"][data-key="${{key}}"]`);return (k==='llm'?'summary: ':'voice: ')+(c?c.closest('.card').querySelector('h3').textContent:key)}});
document.getElementById('pickl').textContent=names.length?[...new Set(names)].join(' · '):'none yet';localStorage.setItem(KEY,JSON.stringify([...picks]))}}
document.querySelectorAll('.star').forEach(b=>b.onclick=()=>{{const id=b.dataset.kind+':'+b.dataset.key;picks.has(id)?picks.delete(id):picks.add(id);render()}});
document.querySelectorAll('.tabbtn').forEach(b=>b.onclick=()=>{{document.querySelectorAll('.tabbtn').forEach(x=>x.classList.toggle('on',x===b));document.querySelectorAll('.tab').forEach(s=>s.hidden=s.dataset.tab!==b.dataset.tab)}});
document.getElementById('copy').onclick=()=>navigator.clipboard.writeText(document.getElementById('pickl').textContent);
document.addEventListener('play',ev=>document.querySelectorAll('audio').forEach(a=>{{if(a!==ev.target)a.pause()}}),true);
render();
</script></body></html>"""
(study / "compare.html").write_text(page)
print(study / "compare.html")

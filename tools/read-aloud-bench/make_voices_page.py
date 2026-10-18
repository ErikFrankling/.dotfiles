"""Gallery of every small voice (Kokoro, Supertonic 3, Pocket TTS) at 1.2x.

usage: python make_voices_page.py STUDY_DIR GRADES_JSON
Audio: STUDY_DIR/private/audio/voices/<engine>-<voice>.opus (not committed).
"""

import html
import json
import sys
from pathlib import Path

study = Path(sys.argv[1])
grades = json.loads(Path(sys.argv[2]).read_text())
clips = sorted(p.stem for p in (study / "private/audio/voices").glob("*.opus"))
text = (study / "inputs/small-voices-text.txt").read_text().strip()
e = html.escape

KOKORO_GROUPS = {"af": "American female", "am": "American male", "bf": "British female", "bm": "British male"}


def card(stem, title, badges):
    tags = "".join(f'<span class="b">{e(b)}</span>' for b in badges if b)
    return f"""<article class="card"><header><h3>{e(title)}</h3>
<button class="star" data-key="{e(stem)}" aria-label="favourite">☆</button></header>
<div class="meta">{tags}</div><audio controls preload="none" src="private/audio/voices/{e(stem)}.opus"></audio></article>"""


sections = []
higgs = [c for c in clips if c.startswith("higgs-erik")]
sections.append(("Your big voice (Higgs, for reference)", "".join(
    card(c, f"Higgs · erik · {c.rsplit('-', 1)[1]}×", ["PC GPU, when dictation is idle"]) for c in higgs)))
kokoro = [c for c in clips if c.startswith("kokoro-")]
for prefix, name in KOKORO_GROUPS.items():
    voices = [c for c in kokoro if c.rsplit("-", 1)[1].startswith(prefix + "_")]
    voices.sort(key=lambda c: ("ABCDF".find((grades.get(c.rsplit("-", 1)[1]) or "Z")[0]) % 9, c))
    sections.append((f"Kokoro · {name}", "".join(
        card(c, c.rsplit("-", 1)[1], [f"grade {grades.get(c.rsplit("-", 1)[1])}" if grades.get(c.rsplit("-", 1)[1]) else "community voice"])
        for c in voices)))
sections.append(("Supertonic 3", "".join(card(c, c.split("-", 1)[1], ["F = female, M = male"]) for c in clips if c.startswith("supertonic-"))))
sections.append(("Pocket TTS", "".join(card(c, c.split("-", 1)[1], ["sped up afterwards (no native speed)"]) for c in clips if c.startswith("pocket-"))))

body = "".join(f"<h2>{e(t)}</h2><div class=\"grid\">{cards}</div>" for t, cards in sections)
page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="icon" href="data:,"><title>Small voices at 1.2×</title><style>
:root{{--bg:#101114;--fg:#e8e8ea;--mut:#9a9ca3;--card:#1a1b20;--line:#2a2c33;--acc:#f0c040}}
@media (prefers-color-scheme: light){{:root{{--bg:#f6f6f4;--fg:#1c1d20;--mut:#62646b;--card:#fff;--line:#e2e2de}}}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}}
main{{max-width:1500px;margin:auto;padding:20px 16px 90px}}h1{{font-size:22px;margin:0 0 4px}}h2{{font-size:17px;margin:28px 0 8px}}
p.lead{{color:var(--mut);max-width:80ch}}blockquote{{margin:10px 0;padding:10px 14px;border-left:3px solid var(--acc);background:var(--card);border-radius:0 10px 10px 0}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:10px}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:12px 14px;display:flex;flex-direction:column;gap:6px}}
.card.fav{{border-color:var(--acc);box-shadow:0 0 0 1px var(--acc)}}.card header{{display:flex;justify-content:space-between;align-items:center}}
h3{{margin:0;font-size:15px}}.star{{background:none;border:0;color:var(--acc);font-size:22px;cursor:pointer;line-height:1}}
.meta{{display:flex;flex-wrap:wrap;gap:6px}}.b{{font-size:12px;padding:2px 8px;border-radius:999px;border:1px solid var(--line);color:var(--mut)}}audio{{width:100%}}
#picks{{position:fixed;left:0;right:0;bottom:0;background:var(--card);border-top:1px solid var(--line);padding:10px 16px;font-size:14px;display:flex;gap:12px;align-items:center;flex-wrap:wrap}}
#picks button{{font:inherit;padding:5px 12px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--fg)}}
</style></head><body><main><h1>Small voices at 1.2×</h1>
<p class="lead">Every voice of the TTS models small enough for the homelab GTX 1060, all reading Gemma 4 E4B's summary at 1.2× speed, sentence by sentence.
This voice reads aloud while you have dictated in the last 30 minutes. Kokoro voices can also be blended, for example two parts of one voice and one part of another. Grades are Kokoro's own quality ratings.</p>
<blockquote>{e(text)}</blockquote>{body}</main>
<div id="picks"><strong>Your picks:</strong><span id="pickl">none yet</span><button id="copy">Copy</button></div>
<script>
const KEY='read-aloud-voice-picks';const picks=new Set(JSON.parse(localStorage.getItem(KEY)||'[]'));
function render(){{document.querySelectorAll('.star').forEach(b=>{{const on=picks.has(b.dataset.key);b.textContent=on?'★':'☆';b.closest('.card').classList.toggle('fav',on)}});
document.getElementById('pickl').textContent=picks.size?[...picks].join(' · '):'none yet';localStorage.setItem(KEY,JSON.stringify([...picks]))}}
document.querySelectorAll('.star').forEach(b=>b.onclick=()=>{{picks.has(b.dataset.key)?picks.delete(b.dataset.key):picks.add(b.dataset.key);render()}});
document.getElementById('copy').onclick=()=>navigator.clipboard.writeText(document.getElementById('pickl').textContent);
document.addEventListener('play',ev=>document.querySelectorAll('audio').forEach(a=>{{if(a!==ev.target)a.pause()}}),true);render();
</script></body></html>"""
(study / "voices.html").write_text(page)
print(study / "voices.html", len(clips), "clips")

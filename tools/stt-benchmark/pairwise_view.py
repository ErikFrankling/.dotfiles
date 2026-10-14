"""Offline comparison of any two outputs, preserving case and punctuation."""
import json


def render(records, reference, root):
    full = [dict(label='Provisional reference (not human ground truth)', text=reference)]
    full += [dict(label=f"{r['model']} / {r['arm']} · {r['tech']}", text=r['text']) for r in records]
    corpora = {'Full recording · 398.7 seconds': full}
    excerpt = root/'frontier-round/excerpt350/comparison.json'
    if excerpt.exists():
        rows = []
        for r in json.loads(excerpt.read_text())['records']:
            raw = json.loads((root/r['source']).read_text())
            rows.append(dict(label=r['model']+' / unhinted excerpt', text=raw['response']['text']))
        corpora['Matched consumer-demo excerpt · 349.952 seconds'] = rows
    payload = json.dumps(corpora).replace('<', '\\u003c')
    return r'''<section id="compare-runs"><h2>Compare any two runs</h2>
<p>Choose two outputs from the same audio. Red marks words unique to A; green marks words unique to B.
Colors show differences, not which version is correct. Punctuation and case are included.</p>
<label>Recording <select id="pair-corpus"></select></label>
<div class="pair-controls"><label>A <select id="pair-a"></select></label>
<label>B <select id="pair-b"></select></label><button id="pair-swap">Swap A/B</button></div>
<div class="pair-panels"><div><h3>A</h3><p id="pair-label-a"></p><div id="pair-left"></div></div>
<div><h3>B</h3><p id="pair-label-b"></p><div id="pair-right"></div></div></div>
<details><summary>Combined word diff</summary><div id="pair-combined"></div></details>
</section><style>
#compare-runs select{font:inherit;max-width:100%;width:100%}.pair-controls{display:grid;grid-template-columns:1fr 1fr auto;gap:12px;margin:15px 0}
.pair-panels{display:grid;grid-template-columns:1fr 1fr;gap:20px}.pair-panels>div{min-width:0;padding:12px;border:1px solid #d5deea;max-height:65vh;overflow:auto}
#pair-left,#pair-right{white-space:pre-wrap;overflow-wrap:anywhere}#pair-combined{line-height:1.9}.pair-panels del{text-decoration:none}
@media(max-width:700px){.pair-controls,.pair-panels{grid-template-columns:1fr}}
</style><script>(()=>{
const corpora=PAYLOAD, corpus=document.getElementById('pair-corpus'),A=document.getElementById('pair-a'),B=document.getElementById('pair-b');
for(const name of Object.keys(corpora))corpus.add(new Option(name,name));
const tokens=s=>s.match(/[\p{L}\p{N}_]+(?:['’][\p{L}\p{N}_]+)*|[^\s]/gu)||[];
function render(){const rows=corpora[corpus.value],ta=rows[A.value].text,tb=rows[B.value].text;
document.getElementById('pair-label-a').textContent=rows[A.value].label;document.getElementById('pair-label-b').textContent=rows[B.value].label;
const a=tokens(ta),b=tokens(tb),m=b.length+1,dp=new Uint16Array((a.length+1)*m);
for(let i=a.length-1;i>=0;i--)for(let j=b.length-1;j>=0;j--)dp[i*m+j]=a[i]===b[j]?1+dp[(i+1)*m+j+1]:Math.max(dp[(i+1)*m+j],dp[i*m+j+1]);
const left=document.getElementById('pair-left'),right=document.getElementById('pair-right'),combined=document.getElementById('pair-combined');
left.replaceChildren();right.replaceChildren();combined.replaceChildren();let i=0,j=0,pa=0,pb=0;
function side(root,text,word,pos,tag){const next=text.indexOf(word,pos);root.append(document.createTextNode(text.slice(pos,next)));const el=document.createElement(tag);el.textContent=word;root.append(el);return next+word.length;}
while(i<a.length||j<b.length){let tag='span',word;
if(i<a.length&&j<b.length&&a[i]===b[j]){word=a[i++];j++;pa=side(left,ta,word,pa,tag);pb=side(right,tb,word,pb,tag)}
else if(j<b.length&&(i===a.length||dp[i*m+j+1]>=dp[(i+1)*m+j])){tag='ins';word=b[j++];pb=side(right,tb,word,pb,tag)}
else{tag='del';word=a[i++];pa=side(left,ta,word,pa,tag)}
const el=document.createElement(tag);el.textContent=word+' ';combined.append(el)}
left.append(document.createTextNode(ta.slice(pa)));right.append(document.createTextNode(tb.slice(pb)));}
function populate(){A.replaceChildren();B.replaceChildren();const rows=corpora[corpus.value];for(const [i,r]of rows.entries()){A.add(new Option(r.label,i));B.add(new Option(r.label,i))}
A.value=Math.max(0,rows.findIndex(r=>r.label.includes('vibevoice')&&r.label.includes('project-overview18')));
B.value=Math.max(0,rows.findIndex(r=>r.label.includes('aqua/avalon')&&r.label.includes('vocabulary18')));
if(A.value===B.value&&rows.length>1)B.value=1;render();}
corpus.onchange=populate;A.onchange=B.onchange=render;document.getElementById('pair-swap').onclick=()=>{const v=A.value;A.value=B.value;B.value=v;render()};populate();
})();</script>'''.replace('PAYLOAD', payload)

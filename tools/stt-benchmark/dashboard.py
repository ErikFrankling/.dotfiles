"""Build an offline dashboard from saved benchmark runs; never embeds API requests."""
import argparse
import json
import pathlib
import re
from report import technology, diff_markup
from score import words, distance


def cost(record):
    value = record.get('provider_response', {}).get('usage', {}).get('cost')
    if isinstance(value, (int, float)):
        return value
    values = [cost(x) for x in record.get('chunk_results', []) if isinstance(x, dict)]
    return sum(values) if values and all(x is not None for x in values) else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results', required=True, type=pathlib.Path)
    args = parser.parse_args()
    root = args.results
    references = {p.stem.removesuffix('.ref'): p.read_text() for p in (root / 'audio').glob('*.ref.txt')}
    records = []
    for path in sorted(root.glob('*.json')):
        d = json.loads(path.read_text())
        if not all(k in d for k in ('clip', 'model', 'arm', 'returncode')):
            continue
        clip = pathlib.Path(d['clip']).stem
        transcript = d.get('response', {}).get('text', '') or ''
        transcript = transcript.split('<asr_text>')[-1]
        ref = references.get(clip, '')
        valid = d['returncode'] == 0 and bool(transcript.strip()) and not d.get('input_limit_exceeded')
        failure = ('input window exceeded' if d.get('input_limit_exceeded') else
                   d.get('failure_kind') or ('output limit' if d.get('finish_reason') == 'length' else 'request / incomplete output'))
        r, h = words(ref), words(transcript)
        # This deliberately measures punctuation *and* wording/case, not isolated prosody.
        tokens = lambda s: re.findall(r"\w+(?:['’]\w+)*|[^\w\s]", s)
        rt, ht = tokens(ref), tokens(transcript)
        records.append(dict(id=len(records), model=d['model'], arm=d['arm'], clip=clip,
            tech=int(technology(d)[0]), cloud=('endpoint' in d or 'provider_response' in d),
            valid=valid, failure='' if valid else failure, text=transcript,
            edits=distance(r,h) if valid and r else None, n=len(r),
            exact=distance(rt,ht) if valid and rt else None, nt=len(rt),
            seconds=d.get('elapsed_seconds'), audio=d.get('audio_seconds'), cost=cost(d),
            names=len(re.findall(r'\bnaiaclaw\b', transcript, re.I)),
            claude=bool(re.search(r'\bclaude\s+code\b', transcript, re.I)),
            diff=diff_markup(rt,ht) if valid and ref else '',
            historical='omni' in d['model'].lower() and '30b' in d['model'].lower()))
    payload = json.dumps(dict(records=records, references=references), ensure_ascii=False).replace('<','\\u003c')
    template = pathlib.Path(__file__).with_name('dashboard.html').read_text()
    output = root / 'dashboard.html'
    output.write_text(template.replace('/*BENCHMARK_DATA*/', payload))
    print(f'{output}: {len(records)} records, {len(references)} references')


if __name__ == '__main__':
    main()

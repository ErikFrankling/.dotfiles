"""Official Avalon batch API, with private credentials and bounded requests."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import time
import urllib.error
import urllib.request
import uuid
import wave


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--audio', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--arm', default='plain')
    p.add_argument('--vocabulary', type=Path)
    p.add_argument('--context', type=Path)
    p.add_argument('--key-file', type=Path, default=Path.home()/'.config/stt-benchmark/aqua.key')
    args = p.parse_args()
    os.umask(0o077)
    if args.output.exists():
        p.error('Preserve previous evidence: output already exists')
    audio = args.audio.read_bytes()
    with wave.open(str(args.audio)) as w:
        duration = w.getnframes()/w.getframerate()
    if len(audio) > 25*1024**2 or not 0 < duration <= 3600:
        p.error('Audio exceeds the documented API limits')
    prompt = ''
    if args.vocabulary:
        prompt = 'Possible spellings, only when spoken: '+args.vocabulary.read_text().strip()
    if args.context:
        prompt += '\nProject background, not words to insert into the transcript:\n'+args.context.read_text()
    fields = {'model':'avalon-v1.5', 'language':'en', 'response_format':'json'}
    if prompt:
        fields['prompt'] = prompt
    boundary = 'stt-'+uuid.uuid4().hex
    parts = []
    for k, v in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="audio.wav"\r\nContent-Type: audio/wav\r\n\r\n'.encode()+audio+b'\r\n')
    parts.append(f'--{boundary}--\r\n'.encode())
    request = urllib.request.Request('https://api.aquavoice.com/v1/audio/transcriptions',
        data=b''.join(parts), headers={
            'Authorization':'Bearer '+args.key_file.read_text().strip(),
            'Content-Type':'multipart/form-data; boundary='+boundary,
            'Idempotency-Key':uuid.uuid4().hex})
    started = time.monotonic()
    status, response, error = None, {}, None
    def deadline(*_):
        raise TimeoutError('240-second total request deadline')
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(240)
    try:
        with urllib.request.urlopen(request, timeout=220) as r:
            status, response = r.status, json.load(r)
    except urllib.error.HTTPError as e:
        status = e.code
        error = e.read().decode(errors='replace')
    except (OSError, ValueError) as e:
        error = str(e)
    finally:
        signal.alarm(0)
    success = status == 200 and bool(response.get('text'))
    record = dict(model='aqua/avalon-v1.5', technology='dedicated-asr', arm=args.arm,
        clip=args.audio.name, audio_sha256=hashlib.sha256(audio).hexdigest(),
        audio_seconds=duration, elapsed_seconds=time.monotonic()-started,
        prompt=prompt, http_status=status, response=response, error=error,
        returncode=0 if success else 1, product_parity='Official batch API; desktop dictation workflow not tested')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record,indent=2)+'\n')
    print(f'{args.arm}: HTTP {status}, transcript returned: {success}',flush=True)
    raise SystemExit(record['returncode'])


if __name__ == '__main__':
    main()

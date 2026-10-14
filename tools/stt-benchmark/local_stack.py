"""Local GPU transcription with contextual decoding and bounded resource use."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import wave

GIB = 1024**3


def memory(pid=None):
    info = {}
    for line in Path('/proc/meminfo').read_text().splitlines():
        k, value = line.split(':', 1)
        info[k] = int(value.strip().split()[0]) * 1024
    out = {'available_ram_bytes': info['MemAvailable'], 'vram_bytes': 0,
           'rss_bytes': 0, 'anonymous_bytes': 0, 'swap_bytes': 0}
    for p in Path('/sys/class/drm').glob('card*/device/mem_info_vram_used'):
        out['vram_bytes'] = max(out['vram_bytes'], int(p.read_text()))
    if pid:
        try:
            values = dict(line.split(':', 1) for line in Path(f'/proc/{pid}/status').read_text().splitlines() if ':' in line)
            for source, target in [('VmRSS', 'rss_bytes'), ('RssAnon', 'anonymous_bytes'), ('VmSwap', 'swap_bytes')]:
                out[target] = int(values.get(source, '0').strip().split()[0]) * 1024
        except FileNotFoundError:
            pass
    return out


def stop(proc):
    if proc.poll() is None:
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=5)


def vocabulary(path):
    if not path:
        return []
    terms, seen = [], set()
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#') or line.casefold() in seen:
            continue
        if len(line.encode()) > 256 or any(c in line for c in '\\"{}[]'):
            raise ValueError('Vocabulary must contain plain names, one per line, at most 256 bytes each')
        seen.add(line.casefold())
        terms.append(line)
    if len(terms) > 400:
        raise ValueError('Maximum vocabulary size is 400 unique names')
    return terms


def transcribe(args):
    model = args.model_dir / 'model.gguf'
    if not model.is_file() or model.stat().st_size > 16_000_000_000:
        raise ValueError('A complete model under the full-GPU weight budget is required')
    if args.output.exists():
        raise ValueError('Output already exists; use a new path to preserve provenance')
    terms = vocabulary(args.vocabulary)
    context = args.context.read_text().strip() if args.context else ''
    if len(context) > 16000:
        raise ValueError('Context exceeds this runner’s 16,000-character GPU budget; supply a shorter context file')
    if args.strategy == 'bias' and not terms:
        raise ValueError('Contextual decoding requires a vocabulary')
    if args.strategy == 'bias' and not 0 <= args.bias_weight <= 3:
        raise ValueError('Bias weight must be finite and between 0 and 3')
    if args.strategy == 'plain' and (terms or context):
        raise ValueError('Plain control must not receive vocabulary or context')
    with wave.open(str(args.audio)) as audio:
        if audio.getcomptype() != 'NONE' or audio.getsampwidth() != 2 or audio.getnchannels() != 1:
            raise ValueError('Use mono 16-bit PCM WAV input')
        duration = audio.getnframes() / audio.getframerate()
    if not 0 < duration <= 1800:
        raise ValueError('Recording must be between 0 and 1800 seconds')
    args.output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    run_dir = args.output.parent / (args.output.stem + '.artifacts')
    run_dir.mkdir(mode=0o700)  # refuse stale partial runs as well
    transcript, turns = run_dir / 'transcript.txt', run_dir / 'turns.json'
    prompt = context
    if args.strategy == 'prompt' and terms:
        prompt += '\nRelevant spellings, only when actually spoken:\n' + '\n'.join(terms)
    cmd = [args.binary, '--task', 'asr', '--family', 'vibevoice_asr', '--model', str(model),
           '--backend', 'vulkan', '--threads', '4', '--audio', str(args.audio),
           '--text-out', str(transcript), '--turns-out', str(turns), '--metrics',
           '--temperature', '0', '--max-tokens', str(args.max_tokens), '--num-beams', str(args.beams),
           '--audio-chunk-mode', 'none', '--language', 'en']
    if prompt:
        cmd += ['--text', prompt]
    if args.strategy == 'bias':
        cmd += ['--request-option', 'bias_phrases=' + '\n'.join(terms),
                '--request-option', f'bias_weight={args.bias_weight}']
    lockpath = Path(os.environ.get('XDG_RUNTIME_DIR', str(run_dir))) / 'local-stt-gpu.lock'
    with lockpath.open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        initial = memory()
        if initial['vram_bytes'] > 8*GIB or initial['available_ram_bytes'] < 8*GIB:
            raise RuntimeError('GPU or host memory is busy; defer transcription')
        started = time.monotonic()
        samples = []
        failure = None
        with (run_dir/'stdout.log').open('w') as stdout, (run_dir/'stderr.log').open('w') as stderr:
            proc = subprocess.Popen(cmd, stdout=stdout, stderr=stderr, start_new_session=True)
            try:
                while proc.poll() is None:
                    sample = {'elapsed': time.monotonic()-started, **memory(proc.pid)}
                    samples.append(sample)
                    if sample['vram_bytes'] > 17*GIB:
                        failure = 'GPU headroom limit exceeded'
                    elif sample['available_ram_bytes'] < 5*GIB or sample['anonymous_bytes'] > 8*GIB or sample['swap_bytes'] > 256*1024**2:
                        failure = 'Host RAM or swapping limit exceeded'
                    elif sample['elapsed'] > args.timeout:
                        failure = 'Inference timeout'
                    if failure:
                        stop(proc)
                        break
                    time.sleep(.25)
            except BaseException:
                stop(proc)
                raise
            finally:
                stop(proc)
        elapsed = time.monotonic()-started
    raw = transcript.read_text().strip() if transcript.exists() else ''
    segments = []
    if turns.exists():
        try:
            segments = json.loads(turns.read_text())
        except (ValueError, TypeError):
            failure = failure or 'Malformed turn output'
    text = ' '.join(t['text'].strip() for t in segments) if isinstance(segments,list) and segments else raw
    if proc.returncode != 0 or not text:
        failure = failure or f'Runtime failed with exit {proc.returncode}'
    # Valid text is not proof of completeness; retain all raw artifacts for review.
    record = {'model':'vibevoice-asr-q8-contextual', 'arm':args.arm or f'{args.strategy}-beam{args.beams}',
              'technology':'autoregressive-speech-llm', 'clip':str(args.audio.resolve()),
              'audio_sha256':hashlib.sha256(args.audio.read_bytes()).hexdigest(), 'audio_seconds':duration,
              'elapsed_seconds':elapsed, 'timing_includes_model_load':True,
              'returncode':1 if failure else 0, 'failure_kind':failure,
              'response':{'text':text, 'speaker_turns':segments},
              'settings':{'strategy':args.strategy,'beams':args.beams,'bias_weight':args.bias_weight if args.strategy=='bias' else 0,
                          'vocabulary':terms,'context':context,'max_tokens':args.max_tokens},
              'binary':str(Path(args.binary).resolve()), 'model_path':str(model.resolve()),
              'resources':{'samples':samples,'after':memory(),'model_residency':'process lifetime; no resident service'},
              'completion_verified':False, 'reference_used':False}
    args.output.write_text(json.dumps(record,indent=2)+'\n')
    print(text)
    print(f'Saved {args.output}; {elapsed:.1f}s; '+(failure or 'output returned'),file=sys.stderr)
    return 1 if failure else 0


def main():
    os.umask(0o077)
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('audio',type=Path)
    p.add_argument('--binary',default=os.environ.get('LOCAL_STT_BINARY'),required=not os.environ.get('LOCAL_STT_BINARY'))
    p.add_argument('--model-dir',type=Path,default=os.environ.get('LOCAL_STT_MODEL'),required=not os.environ.get('LOCAL_STT_MODEL'))
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--vocabulary',type=Path)
    p.add_argument('--context',type=Path)
    p.add_argument('--strategy',choices=['plain','prompt','bias'],default='prompt')
    p.add_argument('--beams',type=int,choices=[1,2,4],default=1)
    p.add_argument('--bias-weight',type=float,default=.5)
    p.add_argument('--max-tokens',type=int,default=4096)
    p.add_argument('--timeout',type=float,default=600)
    p.add_argument('--arm')
    args=p.parse_args()
    if not 0 < args.max_tokens <= 4096 or not 0 < args.timeout <= 1800:
        p.error('max-tokens must be 1..4096 and timeout 0..1800 seconds')
    try:
        return transcribe(args)
    except (ValueError,RuntimeError,OSError) as exc:
        print(f'local-stt: {exc}',file=sys.stderr)
        return 1

if __name__=='__main__':
    raise SystemExit(main())

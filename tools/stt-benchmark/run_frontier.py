"""Bounded GPU-only Hugging Face audio-language-model experiments."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import wave

from local_stack import GIB, memory, stop


def worker(args):
    # AMD documents this opt-in for AOTriton kernels on Radeon.
    os.environ.setdefault('TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL', '1')
    os.environ.setdefault('HF_DEACTIVATE_ASYNC_LOAD', '1')
    import torch
    from torch.nn.attention import SDPBackend, sdpa_kernel
    from transformers import AutoModel, AutoProcessor, TorchAoConfig
    from torchao.quantization import Int8WeightOnlyConfig

    torch.set_num_threads(4)
    # On ROCm this selects ATen's GPU convolution instead of MIOpen. The Nix
    # MIOpen/HIPRTC path failed to discover an architecture; native BF16 GPU
    # convolution was verified separately and keeps the audio encoder on GPU.
    torch.backends.cudnn.enabled = False
    if not torch.version.hip or not torch.cuda.is_available():
        raise RuntimeError('ROCm GPU unavailable; no automatic CPU fallback')
    device = next((i for i in range(torch.cuda.device_count())
                   if '7900 XT' in torch.cuda.get_device_name(i)), None)
    if device is None:
        raise RuntimeError('RX 7900 XT not found; refusing another device')
    target = f'cuda:{device}'  # PyTorch retains this API name for AMD ROCm.
    efficient_backends = [SDPBackend.FLASH_ATTENTION, SDPBackend.EFFICIENT_ATTENTION]
    with torch.inference_mode(), sdpa_kernel(efficient_backends):
        probe = torch.ones((1, 4, 64, 128), device=target, dtype=torch.bfloat16)
        torch.nn.functional.scaled_dot_product_attention(probe, probe, probe, is_causal=True)
    del probe
    started = time.monotonic()
    options = {}
    if args.quant == 'int8':
        options['quantization_config'] = TorchAoConfig(Int8WeightOnlyConfig(version=1))
    processor = AutoProcessor.from_pretrained(args.model_dir, local_files_only=True)
    model, loading_info = AutoModel.from_pretrained(
        args.model_dir, dtype=torch.bfloat16, device_map={'': target},
        local_files_only=True, attn_implementation='sdpa',
        output_loading_info=True, **options)
    if loading_info.get('missing_keys') or loading_info.get('mismatched_keys'):
        raise RuntimeError('Checkpoint/runtime mismatch: ' + str(loading_info))
    loading_info = {key: sorted(value) if isinstance(value, set) else value
                    for key, value in loading_info.items()}
    model.eval()
    if any(p.device.type != 'cuda' for p in model.parameters()):
        raise RuntimeError('Model contains non-GPU parameters; refusing silent offload')
    loaded = time.monotonic()
    prompt = 'Transcribe the input speech. Return only the English transcript.'
    if args.faithful_prompt:
        from run_cloud import INSTRUCTION
        prompt = INSTRUCTION
    if args.vocabulary:
        prompt += '\nPossible spellings, only when spoken: ' + args.vocabulary.read_text()
    conversation = [[{'role': 'user', 'content': [
        {'type': 'text', 'text': prompt},
        {'type': 'audio', 'path': str(args.audio.resolve())},
    ]}]]
    batch = processor.apply_chat_template(
        conversation, tokenize=True, add_generation_prompt=True,
        return_dict=True, return_tensors='pt').to(target)
    if 'input_features' in batch:
        batch['input_features'] = batch['input_features'].to(model.dtype)
    # Avoid silently materializing quadratic attention for the 10k-token audio
    # sequence. An unsupported fused kernel is a runtime issue to fix explicitly.
    with torch.inference_mode(), sdpa_kernel(efficient_backends):
        generated = model.generate(**batch, max_new_tokens=args.max_tokens,
                                   do_sample=False, repetition_penalty=1.2, use_cache=True)
    torch.cuda.synchronize(device)
    completion = generated[:, batch['input_ids'].shape[1]:]
    text = processor.batch_decode(completion, skip_special_tokens=True,
                                  clean_up_tokenization_spaces=False)[0]
    args.output.write_text(json.dumps({
        'response': {'text': text}, 'prompt': prompt,
        'load_seconds': loaded-started,
        'inference_seconds': time.monotonic()-loaded,
        'device': target, 'gpu': torch.cuda.get_device_name(device),
        'cpu_offload_experiment': False,
        'checkpoint_loading_info': loading_info,
        'attention_backends': ['FLASH_ATTENTION', 'EFFICIENT_ATTENTION'],
        'convolution_backend': 'ATen GPU; MIOpen disabled',
        'kv_cache_enabled': True,
        'completion_tokens': completion.shape[1],
        'token_limit_reached': completion.shape[1] >= args.max_tokens,
    }, indent=2) + '\n')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--model-dir', type=Path, required=True)
    p.add_argument('--audio', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--vocabulary', type=Path)
    p.add_argument('--faithful-prompt', action='store_true')
    p.add_argument('--quant', choices=['int8', 'bf16'], default='int8')
    p.add_argument('--max-tokens', type=int, default=4096)
    p.add_argument('--timeout', type=float, default=900)
    p.add_argument('--worker', action='store_true', help=argparse.SUPPRESS)
    args = p.parse_args()
    os.umask(0o077)
    if args.worker:
        worker(args)
        return
    if args.output.exists():
        p.error('Output already exists; preserve previous evidence')
    with wave.open(str(args.audio)) as w:
        duration = w.getnframes()/w.getframerate()
        if (w.getnchannels(), w.getframerate(), w.getsampwidth()) != (1,16000,2):
            p.error('Expected mono 16 kHz 16-bit WAV')
    if not 0 < duration <= 1800 or args.timeout <= 0:
        p.error('Audio must be at most 30 minutes; timeout must be positive')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    lockpath = Path(os.environ.get('XDG_RUNTIME_DIR', str(args.output.parent))) / 'local-stt-gpu.lock'
    samples, failure = [], None
    started = time.monotonic()
    with lockpath.open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        initial = memory()
        if initial['vram_bytes'] > 8*GIB or initial['available_ram_bytes'] < 8*GIB:
            raise RuntimeError('GPU or RAM busy; defer experiment')
        with args.output.with_suffix('.log').open('w') as log:
            proc = subprocess.Popen([sys.executable, __file__, *sys.argv[1:], '--worker'],
                                    stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                while proc.poll() is None:
                    sample = memory(proc.pid)
                    samples.append(sample)
                    if sample['vram_bytes'] > 17*GIB or sample['available_ram_bytes'] < 2*GIB:
                        failure = 'GPU or available-RAM guard exceeded'
                    elif time.monotonic()-started > args.timeout:
                        failure = 'Experiment timeout'
                    if failure:
                        break
                    time.sleep(.25)
            finally:
                stop(proc)
    result = json.loads(args.output.read_text()) if args.output.exists() else {}
    if proc.returncode or not result.get('response',{}).get('text'):
        failure = failure or f'Runtime failure (exit {proc.returncode}); inspect adjacent log'
    if result.get('token_limit_reached'):
        failure = failure or 'Output token limit reached; completeness unverified'
    result.update(model='audio-flamingo-next-'+args.quant,
                  technology='audio-instruction',
                  arm=('vocabulary' if args.vocabulary else 'plain')+('-faithful' if args.faithful_prompt else ''),
                  clip=str(args.audio.resolve()), audio_seconds=duration,
                  audio_sha256=hashlib.sha256(args.audio.read_bytes()).hexdigest(),
                  elapsed_seconds=time.monotonic()-started, timing_includes_model_load=True,
                  prompt_cache_reused=False,
                  model_path=str(args.model_dir.resolve()),
                  runtime_python=sys.executable,
                  returncode=1 if failure else 0, failure_kind=failure,
                  resources={'samples':samples, 'after':memory(),
                             'residency':'unloaded; process lifetime'})
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print(f'Saved {args.output}; {failure or "transcript returned"}', flush=True)
    raise SystemExit(result['returncode'])


if __name__ == '__main__':
    main()

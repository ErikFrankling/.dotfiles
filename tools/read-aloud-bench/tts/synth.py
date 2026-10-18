"""Speak one text file with one TTS engine, sentence by sentence.

Sentence by sentence because that is how read-aloud will stream: the first
sentence plays while the rest is still being written. Prints one JSON line:
load time, time to the first sentence's audio, total synthesis time and the
audio length.

usage: python synth.py ENGINE[:VOICE] TEXT_FILE OUT_WAV
"""

import json
import re
import sys
import time

import os

import numpy as np
import soundfile as sf


# Engines with a native speed setting use it; others are sped up afterwards.
SPEED = float(os.environ.get("TTS_SPEED", "1.0"))


def sentences(text):
    parts = re.split(r"(?<=[.!?])\s+", " ".join(text.split()))
    return [p for p in parts if p.strip()]


def engine_qwen3tts(path, voice):
    import torch
    from qwen_tts import Qwen3TTSModel

    m = Qwen3TTSModel.from_pretrained(path, device_map="cuda:0", dtype=torch.bfloat16)

    def say(s):
        wavs, sr = m.generate_custom_voice(text=s, speaker=voice or "Ryan", language="English")
        return wavs[0], sr

    return say


def engine_kokoro(_, voice):
    from kokoro import KPipeline

    pipe = KPipeline(lang_code="a", repo_id="hexgrad/Kokoro-82M", device="cuda")

    def say(s):
        chunks = [a.cpu().numpy() if hasattr(a, "cpu") else a for _, _, a in pipe(s, voice=voice or "af_heart", speed=SPEED)]
        return np.concatenate(chunks), 24000

    return say


def engine_kokoro_cpu(_, voice, lang="a"):
    from kokoro import KPipeline

    pipe = KPipeline(lang_code=lang, repo_id="hexgrad/Kokoro-82M", device="cpu")

    def say(s):
        chunks = [a.numpy() for _, _, a in pipe(s, voice=voice or "af_heart", speed=SPEED)]
        return np.concatenate(chunks), 24000

    return say


def engine_supertonic(_, voice):
    from supertonic import TTS

    tts = TTS()
    style = tts.get_voice_style(voice or "M1")

    def say(s):
        wav, _ = tts.synthesize(s, voice_style=style, lang="en", speed=1.05 * SPEED)
        return np.asarray(wav).reshape(-1), tts.sample_rate

    return say


def engine_pocket(_, voice):
    from pocket_tts import TTSModel

    m = TTSModel.load_model()
    state = m.get_state_for_audio_prompt(voice or "alba")

    def say(s):
        return m.generate_audio(state, s, max_tokens=1000).numpy(), m.sample_rate

    return say


def engine_chatterbox(_, voice):
    import perth
    from chatterbox.tts_turbo import ChatterboxTurboTTS

    # Perth's neural watermarker fails to import on ROCm; it is inaudible anyway.
    if perth.PerthImplicitWatermarker is None:
        perth.PerthImplicitWatermarker = perth.DummyWatermarker
    m =ChatterboxTurboTTS.from_pretrained(device="cuda")

    def say(s):
        wav = m.generate(s, audio_prompt_path=voice) if voice else m.generate(s)
        return wav.squeeze().cpu().numpy(), m.sr

    return say


def engine_vibevoice(_, voice):
    import copy

    import torch
    from transformers.cache_utils import DynamicCache
    from transformers.modeling_outputs import BaseModelOutputWithPast
    from vibevoice.modular.modeling_vibevoice_streaming_inference import (
        VibeVoiceStreamingForConditionalGenerationInference,
    )
    from vibevoice.processor.vibevoice_streaming_processor import VibeVoiceStreamingProcessor

    repo = "microsoft/VibeVoice-Realtime-0.5B"
    proc = VibeVoiceStreamingProcessor.from_pretrained(repo)
    # No flash-attn on ROCm here; upstream calls SDPA "not fully tested".
    m = VibeVoiceStreamingForConditionalGenerationInference.from_pretrained(
        repo, torch_dtype=torch.bfloat16, device_map="cuda", attn_implementation="sdpa")
    m.eval()
    m.set_ddpm_inference_steps(num_steps=5)
    with torch.serialization.safe_globals([BaseModelOutputWithPast, DynamicCache]):
        prompt = torch.load(f"/opt/vibevoice/demo/voices/streaming_model/{voice or 'en-Carter_man'}.pt",
                            map_location="cuda", weights_only=True)

    def say(s):
        inputs = proc.process_input_with_cached_prompt(
            text=s, cached_prompt=prompt, padding=True, return_tensors="pt", return_attention_mask=True)
        inputs = {k: v.to("cuda") if torch.is_tensor(v) else v for k, v in inputs.items()}
        out = m.generate(**inputs, max_new_tokens=None, cfg_scale=1.5, tokenizer=proc.tokenizer,
                         generation_config={"do_sample": False}, verbose=False,
                         all_prefilled_outputs=copy.deepcopy(prompt))
        return out.speech_outputs[0].float().cpu().numpy(), 24000

    return say


ENGINES = {
    "vibevoice": engine_vibevoice,
    "qwen3tts": engine_qwen3tts,
    "kokoro": engine_kokoro,
    "kokoro-cpu": engine_kokoro_cpu,
    "kokoro-cpu-gb": lambda path, voice: engine_kokoro_cpu(path, voice, lang="b"),  # British voices
    "supertonic": engine_supertonic,
    "pocket": engine_pocket,
    "chatterbox": engine_chatterbox,
}


def main():
    spec, text_file, out = sys.argv[1:4]
    engine, _, rest = spec.partition(":")
    path, _, voice = rest.rpartition("@") if "@" in rest else ("", "", rest)
    text = open(text_file).read()
    t0 = time.time()
    say = ENGINES[engine](path, voice)
    load_s = time.time() - t0
    say("Warm up.")  # first call compiles kernels; a resident server pays this once
    out_chunks, sr, first_s = [], None, None
    t1 = time.time()
    for i, s in enumerate(sentences(text)):
        wav, sr = say(s)
        out_chunks.append(np.asarray(wav, dtype=np.float32).reshape(-1))
        out_chunks.append(np.zeros(int(sr * 0.25), dtype=np.float32))
        if i == 0:
            first_s = time.time() - t1
    synth_s = time.time() - t1
    audio = np.concatenate(out_chunks)
    sf.write(out, audio, sr)
    print("RESULT " + json.dumps({
        "load_s": round(load_s, 1), "first_sentence_s": round(first_s, 2),
        "synth_s": round(synth_s, 2), "audio_s": round(len(audio) / sr, 2), "sr": sr,
    }), flush=True)


if __name__ == "__main__":
    main()

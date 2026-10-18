"""Transcribe every clip with Whisper and score how much of the text it says.

usage: python check_audio.py TEXT_FILE WAV_DIR OUT_JSON
Prints word recall against the text (missing words = dropped or garbled speech).
"""

import difflib
import json
import re
import sys
from pathlib import Path

import librosa
import soundfile as sf
from faster_whisper import WhisperModel


def words(s):
    return re.findall(r"[a-z0-9]+", s.lower().replace("'", ""))


text, wav_dir, out = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
ref = words(Path(text).read_text())
model = WhisperModel("small.en", device="cpu", compute_type="int8")
results = {}
for wav in sorted(wav_dir.glob("*.wav")):
    audio, sr = sf.read(str(wav), dtype="float32", always_2d=True)
    audio = librosa.resample(audio.mean(axis=1), orig_sr=sr, target_sr=16000)
    segs, _ = model.transcribe(audio, beam_size=5)
    hyp_text = " ".join(s.text.strip() for s in segs)
    hyp = words(hyp_text)
    sm = difflib.SequenceMatcher(a=ref, b=hyp, autojunk=False)
    matched = sum(b.size for b in sm.get_matching_blocks())
    results[wav.stem] = {"recall": round(matched / len(ref), 3), "extra_words": len(hyp) - matched,
                         "transcript": hyp_text}
    print(f"{wav.stem:22s} recall={results[wav.stem]['recall']:.3f} extra={len(hyp) - matched}", flush=True)
out.write_text(json.dumps(results, indent=2))

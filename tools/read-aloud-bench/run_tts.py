"""Speak the same summary with every candidate TTS engine, one at a time.

Container engines run through tts/run.sh (tts/synth.py inside); server engines
must already be up and run through tts/http_client.py. Peak total VRAM is
sampled from sysfs while each engine runs.

usage: python run_tts.py TEXT_FILE OUT_DIR OUT_JSON [engine-key ...]
"""

import json
import subprocess
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
VRAM = "/sys/class/drm/card1/device/mem_info_vram_used"
M = "/mnt/data/read-aloud-bench/tts-models"

# key: label, released, params, license, how to run, voice
ENGINES = {
    "kokoro-cpu": ("Kokoro 82M (CPU)", "2025-01", "82M", "Apache-2.0", ("docker", "rab-kokoro", "kokoro-cpu:@af_heart"), "af_heart"),
    "kokoro-gpu": ("Kokoro 82M (GPU)", "2025-01", "82M", "Apache-2.0", ("docker", "rab-kokoro", "kokoro:@af_heart"), "af_heart"),
    "kokoro-cpu-michael": ("Kokoro 82M (CPU, male)", "2025-01", "82M", "Apache-2.0", ("docker", "rab-kokoro", "kokoro-cpu:@am_michael"), "am_michael"),
    "supertonic3": ("Supertonic 3 (CPU)", "2026-04", "99M", "OpenRAIL-M", ("docker", "rab-supertonic", "supertonic:@M1"), "M1"),
    "pocket": ("Pocket TTS (CPU)", "2025-12", "100M", "CC-BY-4.0", ("docker", "rab-pocket", "pocket:@alba"), "alba"),
    "chatterbox-turbo": ("Chatterbox Turbo", "2025-12", "350M", "MIT", ("docker", "rab-chatterbox", "chatterbox:"), "default"),
    "vibevoice-rt": ("VibeVoice Realtime 0.5B", "2025-12", "0.5B", "MIT", ("docker", "rab-vibevoice", "vibevoice:@en-Carter_man"), "Carter"),
    "qwen3tts-0.6b": ("Qwen3-TTS 0.6B", "2026-01", "0.6B", "Apache-2.0", ("docker", "breeze-tts:42aa40215419", f"qwen3tts:{M}/Qwen3-TTS-12Hz-0.6B-CustomVoice@Ryan"), "Ryan"),
    "qwen3tts-1.7b": ("Qwen3-TTS 1.7B", "2026-01", "1.7B", "Apache-2.0", ("docker", "breeze-tts:42aa40215419", f"qwen3tts:{M}/Qwen3-TTS-12Hz-1.7B-CustomVoice@Ryan"), "Ryan"),
    "breeze2": ("Breeze TTS 2", "2026-08", "3B", "research/non-commercial", ("http", "breeze", "http://127.0.0.1:8000/upstream/breeze-tts-2/v1/audio/speech"), "narrator clone"),
    "fish-s2-pro": ("Fish Audio S2 Pro", "2026-03", "5B", "research/non-commercial", ("http", "fish", "http://127.0.0.1:5978/v1/tts"), "narrator clone"),
    "voxtral-4b": ("Voxtral 4B TTS", "2026-03", "4B", "CC-BY-NC-4.0", ("http", "openai", "http://127.0.0.1:5979/v1/audio/speech", "casual_male"), "casual_male"),
    "higgs3-4b": ("Higgs TTS 3 4B", "2026-06", "4B", "research/non-commercial", ("http", "openai", "http://127.0.0.1:5980/v1/audio/speech", "ref"), "narrator clone"),
}


def vram():
    return int(Path(VRAM).read_text())


def main():
    text, out_dir, out_json = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    only = sys.argv[4:]
    results = json.loads(out_json.read_text()) if out_json.exists() else {}
    for key in only or ENGINES:
        label, released, params, lic, how, voice = ENGINES[key]
        wav = out_dir / f"{key}.wav"
        if how[0] == "docker":
            cmd = [str(HERE / "tts/run.sh"), how[1], how[2], text, str(wav)]
        else:
            cmd = ["python3", str(HERE / "tts/http_client.py"), how[1], how[2], text, str(wav), *how[3:]]
        base = vram()
        peak = [base]
        stop = threading.Event()

        def sample():
            while not stop.is_set():
                peak[0] = max(peak[0], vram())
                time.sleep(0.05)

        threading.Thread(target=sample, daemon=True).start()
        p = subprocess.run(cmd, capture_output=True, text=True)
        stop.set()
        line = next((l for l in p.stdout.splitlines() if l.startswith("RESULT ")), None)
        entry = {"label": label, "released": released, "params": params, "license": lic, "voice": voice}
        if line:
            r = json.loads(line[7:])
            entry |= r | {"rtf": round(r["synth_s"] / r["audio_s"], 2), "wav": wav.name,
                          "vram_peak_total_gib": round(peak[0] / 2**30, 2),
                          "vram_added_gib": round((peak[0] - base) / 2**30, 2)}
            print(f"{key}: {r}", flush=True)
        else:
            entry["error"] = (p.stderr or p.stdout)[-1500:]
            print(f"FAIL {key}: {entry['error'][-400:]}", flush=True)
        results[key] = entry
        out_json.write_text(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()

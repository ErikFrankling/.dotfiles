"""Same sentence-by-sentence measurement as synth.py, for TTS engines that run
as HTTP servers (Breeze via llama-swap, Fish S2 Pro, vLLM-Omni). Stdlib only,
so it runs on the host.

usage: python http_client.py KIND URL TEXT_FILE OUT_WAV [VOICE]
KIND: breeze | fish | openai
"""

import base64
import io
import json
import re
import sys
import time
import urllib.request
import uuid
import wave
from pathlib import Path

REF_WAV = Path("/mnt/data/read-aloud-bench/ref-narrator.wav")
REF_TEXT = Path("/mnt/data/read-aloud-bench/ref-narrator.txt").read_text().strip()


def sentences(text):
    return [p for p in re.split(r"(?<=[.!?])\s+", " ".join(text.split())) if p.strip()]


def multipart(fields, files):
    b = uuid.uuid4().hex
    out = io.BytesIO()
    for k, v in fields.items():
        out.write(f'--{b}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    for k, (name, data, ctype) in files.items():
        out.write(f'--{b}\r\nContent-Disposition: form-data; name="{k}"; filename="{name}"\r\n'
                  f"Content-Type: {ctype}\r\n\r\n".encode() + data + b"\r\n")
    out.write(f"--{b}--\r\n".encode())
    return out.getvalue(), f"multipart/form-data; boundary={b}"


def post(url, body, ctype, timeout=900):
    for _ in range(360):
        try:
            req = urllib.request.Request(url, data=body, headers={"Content-Type": ctype})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read(), dict(r.headers)
        except urllib.error.HTTPError as e:
            if e.code not in (409, 502, 503):
                raise RuntimeError(f"{e.code}: {e.read()[:500]!r}")
        except (urllib.error.URLError, ConnectionError):
            pass
        time.sleep(2)
    raise RuntimeError("server never became ready")


def wav_pcm(data):
    with wave.open(io.BytesIO(data)) as w:
        assert w.getsampwidth() == 2 and w.getnchannels() == 1, (w.getsampwidth(), w.getnchannels())
        return w.readframes(w.getnframes()), w.getframerate()


def say(kind, url, s, voice):
    if kind == "breeze":
        body, ctype = multipart({"text": s, "seed": 7, "ref_text": REF_TEXT},
                                {"ref_audio": ("ref.wav", REF_WAV.read_bytes(), "audio/wav")})
        data, headers = post(url, body, ctype)
        return data, int(headers.get("X-Sample-Rate", "24000"))
    if kind == "fish":
        body = json.dumps({
            "text": s, "format": "wav", "seed": 7, "streaming": False,
            "references": [{"audio": base64.b64encode(REF_WAV.read_bytes()).decode(), "text": REF_TEXT}],
        }).encode()
        return wav_pcm(post(url, body, "application/json")[0])
    if kind == "openai":
        req = {"input": s, "response_format": "wav"}
        if voice == "ref":
            req["ref_audio"] = "data:audio/wav;base64," + base64.b64encode(REF_WAV.read_bytes()).decode()
            req["ref_text"] = REF_TEXT
        else:
            req["voice"] = voice
        return wav_pcm(post(url, json.dumps(req).encode(), "application/json")[0])
    raise SystemExit(f"unknown kind {kind}")


def main():
    kind, url, text_file, out = sys.argv[1:5]
    voice = sys.argv[5] if len(sys.argv) > 5 else ""
    t0 = time.time()
    say(kind, url, "Warm up.", voice)  # also waits for the server to load
    load_s = time.time() - t0
    pcm, sr, first_s = bytearray(), None, None
    t1 = time.time()
    for i, s in enumerate(sentences(Path(text_file).read_text())):
        data, sr = say(kind, url, s, voice)
        pcm += data + b"\0\0" * int(sr * 0.25)
        if i == 0:
            first_s = time.time() - t1
    synth_s = time.time() - t1
    with wave.open(out, "wb") as w:
        w.setnchannels(1), w.setsampwidth(2), w.setframerate(sr)
        w.writeframes(bytes(pcm))
    print("RESULT " + json.dumps({
        "load_s": round(load_s, 1), "first_sentence_s": round(first_s, 2),
        "synth_s": round(synth_s, 2), "audio_s": round(len(pcm) / 2 / sr, 2), "sr": sr,
    }), flush=True)


if __name__ == "__main__":
    main()

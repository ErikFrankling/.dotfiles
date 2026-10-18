"""Run every candidate summary model over the same inputs with the same prompt.

One llama-server at a time, fully on the GPU. Records load time, peak total
VRAM, prefill and decode speed, and the spoken summary for each input.

usage: python3 run_llm.py MODELS_DIR OUT_JSON [model-key ...]
"""

import json
import os
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
STUDY = HERE.parent.parent / "research/read-aloud/2026-10-18"
LLAMA_SERVER = "/nix/store/r5qgjy94bia5w0c87zxhz10yf8q3s7yz-llama-cpp-0.6.0/bin/llama-server"
VRAM = "/sys/class/drm/card1/device/mem_info_vram_used"
PORT = 5977
# The dictation guard stops local-stt above 19.5 GiB; stay clear of it.
VRAM_ABORT = 19.2 * 2**30
# Liquid LFM2.5 only exists as a reasoning model; "--reasoning off" is ignored
# and it spends any small budget thinking, so it gets room to think.
THINKING_ONLY = {"lfm2.5-2.6b", "lfm2.5-8b-a1b"}

# key, label, file relative to MODELS_DIR, release, fits the ~3.7 GB budget
MODELS = [
    ("qwen3.5-2b", "Qwen3.5-2B", "unsloth/Qwen3.5-2B-Q4_K_M.gguf", "2026-03", True),
    ("qwen3.5-4b", "Qwen3.5-4B", "unsloth/Qwen3.5-4B-Q4_K_M.gguf", "2026-03", True),
    ("gemma4-e2b", "Gemma 4 E2B", "unsloth/gemma-4-E2B-it-Q4_K_M.gguf", "2026-04", True),
    ("gemma4-e4b", "Gemma 4 E4B", "unsloth/gemma-4-E4B-it-Q4_K_M.gguf", "2026-04", False),
    ("lfm2.5-2.6b", "LFM2.5-2.6B", "LiquidAI/LFM2.5-2.6B-Q4_K_M.gguf", "2026-08", True),
    ("granite4.2-3b", "Granite 4.2 3B", "ibm-granite/granite-4.2-3b-Q4_K_M.gguf", "2026-08", True),
    ("ministral3-3b", "Ministral 3 3B", "mistralai/Ministral-3-3B-Instruct-2512-Q4_K_M.gguf", "2025-12", True),
    ("lfm2.5-8b-a1b", "LFM2.5-8B-A1B (MoE)", "LiquidAI/LFM2.5-8B-A1B-Q4_K_M.gguf", "2026-05", False),
    ("qwen3.5-9b", "Qwen3.5-9B", "unsloth/Qwen3.5-9B-Q4_K_M.gguf", "2026-03", False),
    ("gemma4-12b", "Gemma 4 12B", "unsloth/gemma-4-12b-it-Q4_K_M.gguf", "2026-05", False),
]


def vram():
    return int(Path(VRAM).read_text())


def get(url, data=None, timeout=600):
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def main():
    models_dir = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    only = set(sys.argv[3:])
    prompt = (HERE / "prompt.md").read_text()
    inputs = {p.stem: p.read_text() for p in sorted((STUDY / "inputs").glob("*.md"))}
    results = json.loads(out_path.read_text()) if out_path.exists() else {}

    for key, label, rel, released, fits in MODELS:
        if only and key not in only:
            continue
        path = models_dir / rel
        if not path.exists():
            print(f"skip {key}: {path} missing", flush=True)
            continue
        base = vram()
        t0 = time.time()
        proc = subprocess.Popen(
            [LLAMA_SERVER, "--model", str(path), "--port", str(PORT), "--host", "127.0.0.1",
             "-ngl", "999", "-c", "16384", "--flash-attn", "on", "--jinja",
             "--reasoning", "on" if key in THINKING_ONLY else "off",
             "--parallel", "1", "--cache-ram", "0", "--no-ui"],
            stdout=subprocess.DEVNULL, stderr=open(out_path.with_suffix(f".{key}.log"), "w"),
        )
        peak = [base]
        stop = threading.Event()

        def sample():
            while not stop.is_set():
                v = vram()
                peak[0] = max(peak[0], v)
                if v > VRAM_ABORT:
                    print(f"ABORT {key}: VRAM {v / 2**30:.2f} GiB", flush=True)
                    proc.kill()
                    return
                time.sleep(0.05)

        threading.Thread(target=sample, daemon=True).start()
        try:
            while True:
                if proc.poll() is not None:
                    raise RuntimeError(f"llama-server exited {proc.returncode}")
                try:
                    if get(f"http://127.0.0.1:{PORT}/health", timeout=2).get("status") == "ok":
                        break
                except Exception:
                    pass
                time.sleep(0.2)
            load_s = time.time() - t0
            loaded = vram()
            runs = {}
            for name, text in inputs.items():
                body = json.dumps({
                    "messages": [{"role": "system", "content": prompt},
                                 {"role": "user", "content": text}],
                    "temperature": 0.3, "top_p": 0.95,
                    "max_tokens": 4000 if key in THINKING_ONLY else 600,
                    "chat_template_kwargs": {"enable_thinking": False},
                }).encode()
                t1 = time.time()
                r = get(f"http://127.0.0.1:{PORT}/v1/chat/completions", body)
                wall = time.time() - t1
                tm = r.get("timings", {})
                runs[name] = {
                    "text": r["choices"][0]["message"]["content"].strip(),
                    "wall_s": round(wall, 2),
                    "prompt_tokens": tm.get("prompt_n"),
                    "prefill_ms": round(tm.get("prompt_ms", 0)),
                    "prefill_tps": round(tm.get("prompt_per_second", 0)),
                    "decode_tps": round(tm.get("predicted_per_second", 0), 1),
                    "output_tokens": tm.get("predicted_n"),
                }
                print(f"{key} {name}: {wall:.1f}s {runs[name]['decode_tps']} tok/s", flush=True)
            results[key] = {
                "label": label, "file": rel, "released": released, "fits_budget": fits,
                "file_gb": round(path.stat().st_size / 1e9, 2),
                "load_s": round(load_s, 1),
                "vram_loaded_gib": round((loaded - base) / 2**30, 2),
                "vram_peak_total_gib": round(peak[0] / 2**30, 2),
                "vram_baseline_gib": round(base / 2**30, 2),
                "runs": runs,
            }
        except Exception as e:
            print(f"FAIL {key}: {e}", flush=True)
            results[key] = {"label": label, "file": rel, "released": released,
                            "fits_budget": fits, "error": str(e)}
        finally:
            stop.set()
            proc.terminate()
            try:
                proc.wait(15)
            except subprocess.TimeoutExpired:
                proc.kill()
            out_path.write_text(json.dumps(results, indent=2))
            time.sleep(2)


if __name__ == "__main__":
    main()

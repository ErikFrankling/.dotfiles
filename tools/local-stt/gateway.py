"""Loopback-only recording coordinator; T3 authenticates every forwarded request."""
import asyncio
import base64
import hashlib
import json
import os
import re
import time
import uuid
import wave
from pathlib import Path

from aiohttp import ClientSession, ClientTimeout, WSMsgType, web

ROOT = Path(os.environ.get("STT_RECORDINGS", "/var/lib/local-stt"))
NEMO = os.environ.get("STT_STREAM_URL", "http://127.0.0.1:8782")
VIBE = os.environ.get("STT_FINAL_URL", "http://127.0.0.1:8783")
MAX_BYTES = 16000 * 2 * 30 * 60
sessions = {}
final_lock = asyncio.Lock()
workers = {}


async def stop_worker(name):
    process = workers.pop(name, None)
    if process and process.returncode is None:
        process.terminate()
        try:
            await asyncio.wait_for(process.wait(), 5)
        except asyncio.TimeoutError:
            process.kill()
            await process.wait()


async def start_worker(name, client):
    process = workers.get(name)
    if process and process.returncode is None:
        return
    if name == "preview":
        command = [os.environ["STT_NEMO_BINARY"], "serve", "--asr-model", os.environ["STT_NEMO_MODEL"],
                   "--host", "127.0.0.1", "--port", "8782", "--backend", "vulkan",
                   "--threads", "4", "--no-ui", "--read-timeout", "1900"]
        url = NEMO + "/v1/models"
    else:
        command = [os.environ["STT_VIBE_BINARY"], "--config", os.environ["STT_VIBE_CONFIG"]]
        url = VIBE + "/v1/models"
    workers[name] = await asyncio.create_subprocess_exec(*command)
    for _ in range(600):
        if workers[name].returncode is not None:
            raise RuntimeError(f"{name} worker exited during startup")
        try:
            async with client.get(url, timeout=ClientTimeout(total=1)) as response:
                if response.status == 200:
                    return
        except (OSError, asyncio.TimeoutError):
            pass
        await asyncio.sleep(0.2)
    await stop_worker(name)
    raise TimeoutError(f"{name} worker did not become ready")


async def monitor():
    # Observe total device memory, including the compositor and other workloads.
    # These bounds are a guard, not a GPU reservation.
    while True:
        await asyncio.sleep(0.2)
        vram = max((int(p.read_text()) for p in Path("/sys/class/drm").glob("card*/device/mem_info_vram_used")), default=0)
        memory = dict(line.split(":", 1) for line in Path("/proc/meminfo").read_text().splitlines())
        available = int(memory["MemAvailable"].split()[0]) * 1024
        for name, process in list(workers.items()):
            if process.returncode is not None:
                continue
            try:
                status = dict(line.split(":", 1) for line in Path(f"/proc/{process.pid}/status").read_text().splitlines() if ":" in line)
            except FileNotFoundError:
                continue
            anonymous = int(status.get("RssAnon", "0").split()[0]) * 1024
            swap = int(status.get("VmSwap", "0").split()[0]) * 1024
            for state in sessions.values():
                if state["status"] in {"recording", "finalizing"}:
                    peaks = state.setdefault("resources", {})
                    for key, value in {"total_vram_bytes": vram, "anonymous_ram_bytes": anonymous, "swap_bytes": swap}.items():
                        peaks[key] = max(peaks.get(key, 0), value)
            if vram > 17 * 1024**3 or available < 3 * 1024**3 or anonymous > 6 * 1024**3 or swap > 256 * 1024**2:
                print(f"Stopping {name}: GPU/host memory headroom guard", flush=True)
                await stop_worker(name)


def project_context(directory, draft):
    """Bounded local tracked-file vocabulary; never read ignored files or secrets."""
    # Called off the event loop; git commands have strict deadlines.
    import subprocess
    root = Path(directory).resolve()
    if not root.is_dir() or root == Path("/") or root == Path.home():
        return "", []
    try:
        files = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z"], capture_output=True,
            timeout=5, check=True,
        ).stdout.decode("utf-8", errors="replace").split("\0")
    except (OSError, subprocess.SubprocessError):
        return root.name, [root.name]
    blocked = re.compile(r"(^|/)(node_modules|vendor|dist|build|\.git)(/|$)|secret|credential|\.env|\.key|lock", re.I)
    names = {root.name: 100, "Claude Code": 80, "Codex": 80}
    overview = ""
    deadline = time.monotonic() + 4
    read_bytes = 0
    # Documents first: project concepts should not be crowded out by generic
    # local variables. The draft only boosts relevant candidates, never removes
    # project names that the preview may have misheard.
    files.sort(key=lambda name: (name.lower() != "readme.md", not name.endswith(".md"), name))
    generic = {"value", "name", "code", "client", "next", "entry", "files", "columns", "record", "data", "result", "error", "props", "state", "index", "args", "options"}
    for filename in files[:4000]:
        if time.monotonic() > deadline or read_bytes > 2_000_000:
            break
        if not filename or blocked.search(filename):
            continue
        path = root / filename
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root):
            continue
        stem = path.stem
        if len(stem) > 3 and stem.lower() not in generic:
            names[stem] = names.get(stem, 0) + 1
        if path.stat().st_size > 64000:
            continue
        if path.suffix not in {".ts", ".tsx", ".py", ".rs", ".go", ".json", ".md", ".nix"}:
            continue
        text = path.read_text(errors="replace")[:16000]
        read_bytes += len(text)
        if filename.lower() == "readme.md":
            overview = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", re.sub(r"```.*?```", "", text, flags=re.S))[:700]
            for name in re.findall(r"\b[A-Z][a-z]+(?:[A-Z0-9][A-Za-z0-9]*)+\b", text):
                names[name] = names.get(name, 0) + 15
        for name in re.findall(r"\b(?:function|class|def|fn|interface|type|const)\s+([A-Za-z][A-Za-z0-9_]{3,60})", text):
            if name.lower() not in generic:
                names[name] = names.get(name, 0) + 1
    words = set(re.findall(r"[a-z0-9]+", draft.lower()))
    def rank(name):
        parts = re.findall(r"[A-Z]?[a-z]+|[A-Z]+(?=[A-Z]|$)", name)
        overlap = sum(part.lower() in words for part in parts)
        return (-(names[name] >= 80), -overlap, -names[name], name)
    selected = sorted(names, key=rank)[:32]
    vocabulary = ", ".join(selected)[:700]
    return f"{overview}\nRelevant spellings: {vocabulary}", selected


def save(state):
    public = {k: state[k] for k in (
        "id", "owner", "project", "status", "draft", "final", "error", "bytes", "created", "vocabulary", "sequence"
    )}
    public.update({key: state[key] for key in ("context", "resources", "audio_sha256", "runtime") if key in state})
    path = ROOT / state["id"] / "state.json"
    temporary = path.with_suffix(".new")
    temporary.write_text(json.dumps(public))
    temporary.replace(path)


def result(state):
    return {k: state[k] for k in ("id", "status", "draft", "final", "error", "bytes")}


async def receive(state):
    partial = ""
    completed = []
    try:
        async for message in state["ws"]:
            if message.type != WSMsgType.TEXT:
                continue
            event = json.loads(message.data)
            kind = event.get("type", "")
            if kind.endswith(".delta"):
                partial += event.get("delta", "")
            elif kind.endswith(".completed"):
                completed.append(event.get("transcript", ""))
                partial = ""
            elif kind == "error":
                state["error"] = "Streaming preview unavailable; original audio is retained."
            state["draft"] = " ".join(completed + [partial]).strip()
    except (OSError, ValueError):
        state["error"] = "Streaming connection interrupted; final transcription remains available."


async def finalize(state, client):
    state["status"] = "finalizing"
    state["error"] = ""
    save(state)
    try:
        async with final_lock:
            if state.get("ws") is not None:
                await state["ws"].close()
            await stop_worker("preview")
            await start_worker("final", client)
            pcm = ROOT / state["id"] / "audio.pcm"
            wav = pcm.with_suffix(".wav")
            with wave.open(str(wav), "wb") as output:
                output.setnchannels(1)
                output.setsampwidth(2)
                output.setframerate(16000)
                output.writeframes(pcm.read_bytes())
            context, state["vocabulary"] = await asyncio.to_thread(
                project_context, state["project"], state["draft"]
            )
            state["context"] = context
            state["audio_sha256"] = hashlib.sha256(wav.read_bytes()).hexdigest()
            state["runtime"] = {key: os.environ.get(key) for key in (
                "STT_NEMO_BINARY", "STT_NEMO_MODEL", "STT_VIBE_BINARY", "STT_VIBE_CONFIG"
            )}
            save(state)
            async with client.post(VIBE + "/v1/audio/transcriptions", json={
                "model": "vibevoice", "audio": str(wav), "language": "en", "text": context,
                "options": {"temperature": 0, "max_tokens": 4096 if state["bytes"] < 16000 * 2 * 480 else 8192,
                            "num_beams": 1, "audio_chunk_mode": "none"},
            }, timeout=ClientTimeout(total=1200)) as response:
                response.raise_for_status()
                data = await response.json()
            text = data.get("text", "").strip()
            # VibeVoice may annotate non-speech events. They are not dictation;
            # remove only known event labels, never arbitrary bracketed text.
            text = re.sub(r"\[(?:breathing|silence|noise|environmental sounds|music|laughter)\]\s*", "", text, flags=re.I).strip()
            if not text:
                raise ValueError("The final recognizer returned an empty transcript.")
            state["final"] = text
            state["status"] = "complete"
    except asyncio.CancelledError:
        state["status"] = "cancelled"
        raise
    except Exception as error:
        state["status"] = "error"
        state["error"] = f"Final transcription failed ({type(error).__name__}); recording saved for retry."
    finally:
        save(state)


async def action(request):
    data = await request.json()
    owner = request.headers.get("X-STT-Owner", "")
    if not owner:
        raise web.HTTPUnauthorized()
    kind = data.get("action")
    if kind == "start":
        if final_lock.locked() or any(s["status"] in {"recording", "finalizing"} for s in sessions.values()):
            raise web.HTTPConflict(text="The speech service is busy with another recording.")
        identifier = str(uuid.uuid4())
        (ROOT / identifier).mkdir(mode=0o700, parents=True)
        (ROOT / identifier / "audio.pcm").touch(mode=0o600)
        state = dict(id=identifier, owner=owner, project=str(data.get("project", "")),
                     status="recording", draft="", final="", error="", bytes=0,
                     created=time.time(), vocabulary=[], sequence=0)
        sessions[identifier] = state
        try:
            # Do not overlap large final-pass weights with preview startup.
            await stop_worker("final")
            await start_worker("preview", request.app["client"])
            state["ws"] = await request.app["client"].ws_connect(
                NEMO + "/v1/audio/transcriptions/realtime", timeout=10
            )
            await state["ws"].send_json({"type": "session.update", "session": {
                "sample_rate": 16000, "language": "en", "automatic_punctuation": True,
            }})
            state["reader"] = asyncio.create_task(receive(state))
        except Exception:
            state["error"] = "Streaming preview unavailable; you can still record for VibeVoice."
        save(state)
        return web.json_response(result(state))
    state = sessions.get(data.get("id"))
    if state is None or state["owner"] != owner:
        raise web.HTTPNotFound()
    if kind == "append":
        if state["status"] != "recording":
            raise web.HTTPConflict(text="Recording is already closed.")
        sequence = data.get("sequence")
        if sequence == state["sequence"] - 1:
            return web.json_response(result(state))  # retry after response loss
        if sequence != state["sequence"]:
            raise web.HTTPConflict(text="Unexpected audio chunk sequence.")
        try:
            pcm = base64.b64decode(data["audio"], validate=True)
        except (KeyError, ValueError):
            raise web.HTTPBadRequest(text="Invalid PCM chunk.")
        if len(pcm) % 2 or len(pcm) > 320000 or state["bytes"] + len(pcm) > MAX_BYTES:
            raise web.HTTPRequestEntityTooLarge(max_size=MAX_BYTES, actual_size=state["bytes"] + len(pcm))
        with (ROOT / state["id"] / "audio.pcm").open("ab") as output:
            output.write(pcm)
        state["bytes"] += len(pcm)
        state["sequence"] += 1
        try:
            if state.get("ws") is not None:
                await state["ws"].send_bytes(pcm)
        except Exception:
            state["error"] = "Preview disconnected; original audio is retained."
        save(state)
    elif kind in {"finish", "retry"}:
        if state["status"] not in {"finalizing", "complete"}:
            if not state["bytes"]:
                raise web.HTTPBadRequest(text="No audio was recorded.")
            state["status"] = "finalizing"
            state["task"] = asyncio.create_task(finalize(state, request.app["client"]))
    elif kind == "cancel":
        if state["status"] == "finalizing":
            await stop_worker("final")
            if task := state.get("task"):
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)
        if state.get("ws") is not None:
            await state["ws"].close()
        await stop_worker("preview")
        state["status"] = "cancelled"
        save(state)
    elif kind != "status":
        raise web.HTTPBadRequest(text="Unknown recording action.")
    return web.json_response(result(state))


async def lifecycle(app):
    ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    for path in ROOT.glob("*/state.json"):
        try:
            state = json.loads(path.read_text())
            if state["status"] in {"recording", "finalizing"}:
                state["status"] = "error"
                state["error"] = "Service restarted; saved audio is available for retry."
            sessions[state["id"]] = state
        except (ValueError, KeyError):
            continue
    async with ClientSession(timeout=ClientTimeout(total=30)) as client:
        app["client"] = client
        watcher = asyncio.create_task(monitor())
        yield
        watcher.cancel()
        tasks = []
        for state in sessions.values():
            for key in ("reader", "task"):
                if task := state.get(key):
                    task.cancel()
                    tasks.append(task)
            if state.get("ws") is not None:
                await state["ws"].close()
        await asyncio.gather(*tasks, return_exceptions=True)
        await asyncio.gather(watcher, return_exceptions=True)
        for name in list(workers):
            await stop_worker(name)


if __name__ == "__main__":
    os.umask(0o077)
    app = web.Application(client_max_size=512000)
    app.cleanup_ctx.append(lifecycle)
    app.router.add_post("/dictation", action)
    app.router.add_get("/health", lambda _: web.json_response({"ok": True}))
    web.run_app(app, host="127.0.0.1", port=int(os.environ.get("STT_PORT", "8781")), access_log=None)

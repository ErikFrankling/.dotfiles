"""Loopback-only recording coordinator; T3 authenticates every forwarded request."""
import array
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

from aiohttp import ClientSession, ClientTimeout, ClientWSTimeout, WSMsgType, web

ROOT = Path(os.environ.get("STT_RECORDINGS", "/var/lib/local-stt"))
NEMO = os.environ.get("STT_STREAM_URL", "http://127.0.0.1:8782")
VIBE = os.environ.get("STT_FINAL_URL", "http://127.0.0.1:8783")
# The final recogniser shares the GPU with llama-swap (LLMs, TTS): it unloads
# after this much idle time, on request from llama-swap, and asks llama-swap
# to unload its idle model before loading itself.
FINAL_IDLE_SECONDS = float(os.environ.get("STT_FINAL_IDLE_SECONDS", "18000"))
LLAMA_SWAP = os.environ.get("STT_LLAMA_SWAP_URL", "")
FINAL_VRAM_BYTES = 11 * 1024**3
# The loaded recogniser holds ~9.2 GiB. Below this much free GPU memory a load
# cannot succeed and would only push the desktop into its crash band.
FINAL_LOAD_BYTES = 9.5 * 1024**3
last_used = {}
MAX_BYTES = 16000 * 2 * 30 * 60
sessions = {}
final_lock = asyncio.Lock()
workers = {}
worker_locks = {name: asyncio.Lock() for name in ("preview", "final")}
SAMPLE_BYTES = 32000
CHUNK_SECONDS = 30
QUALITY_SECONDS = 420
# Final-pass window per attempt. Shorter windows need less GPU scratch memory,
# so a recording that cannot be transcribed in one piece still completes.
RETRY_WINDOWS = (QUALITY_SECONDS, QUALITY_SECONDS, 120, 120, CHUNK_SECONDS)
ACTIVE_SECONDS = 120
background = set()


class EmptyTranscript(ValueError):
    pass


def spawn(coroutine):
    task = asyncio.create_task(coroutine)
    background.add(task)
    task.add_done_callback(background.discard)
    return task


def log(event, state=None, **fields):
    print(json.dumps({"time": time.time(), "event": event,
                      **({"recording_id": state["id"]} if state else {}), **fields}), flush=True)



async def stop_worker(name):
    process = workers.pop(name, None)
    if process and process.returncode is None:
        try:
            process.terminate()
        except ProcessLookupError:
            return
        try:
            await asyncio.wait_for(process.wait(), 5)
        except asyncio.TimeoutError:
            process.kill()
            await process.wait()


async def start_worker(name, client):
    last_used[name] = time.monotonic()
    async with worker_locks[name]:
        await _start_worker(name, client)


def vram_free():
    free = []
    for used in Path("/sys/class/drm").glob("card*/device/mem_info_vram_used"):
        total = int((used.parent / "mem_info_vram_total").read_text())
        if total > 4 * 1024**3:
            free.append(total - int(used.read_text()))
    return max(free, default=0)


async def make_room(client):
    """Ask llama-swap to unload its (idle) model when the final recogniser won't fit."""
    if LLAMA_SWAP and vram_free() < FINAL_VRAM_BYTES:
        try:
            async with client.get(LLAMA_SWAP + "/unload", timeout=ClientTimeout(total=30)) as response:
                status = response.status
            # llama-swap answers before its model process has released the GPU.
            for _ in range(25):
                if vram_free() >= FINAL_VRAM_BYTES:
                    break
                await asyncio.sleep(0.2)
            log("worker.make_room", status=status, free_vram=vram_free())
        except (OSError, asyncio.TimeoutError) as error:
            log("worker.make_room_failed", error=str(error))
    if vram_free() < FINAL_LOAD_BYTES:
        raise RuntimeError(f"not enough free GPU memory for the final recogniser ({vram_free() / 1024**3:.1f} GiB)")


def active(state):
    """A recording whose browser went away must not hold the GPU forever."""
    return state["status"] == "finalizing" or (
        state["status"] == "recording" and time.time() - state.get("touched", 0) < ACTIVE_SECONDS)


def busy():
    return any(active(s) for s in sessions.values())


async def release_gpu(_request):
    """Called by llama-swap before it loads a model: unload the idle final recogniser."""
    process = workers.get("final")
    if busy() or not process or process.returncode is not None:
        return web.json_response({"released": False, "busy": busy()})
    await stop_worker("final")
    log("worker.released", worker="final")
    return web.json_response({"released": True})


async def _start_worker(name, client):
    process = workers.get(name)
    if process and process.returncode is None:
        return
    if name == "preview":
        command = [os.environ["STT_NEMO_BINARY"], "serve", "--asr-model", os.environ["STT_NEMO_MODEL"],
                   "--host", "127.0.0.1", "--port", NEMO.rsplit(":", 1)[1], "--backend", "vulkan",
                   "--threads", "4", "--no-ui", "--read-timeout", "1900"]
        url = NEMO + "/v1/models"
    else:
        await make_room(client)
        command = [os.environ["STT_VIBE_BINARY"], "--config", os.environ["STT_VIBE_CONFIG"]]
        url = VIBE + "/v1/models"
    workers[name] = await asyncio.create_subprocess_exec(*command)
    log("worker.start", worker=name, pid=workers[name].pid)
    for _ in range(600):
        if name not in workers or workers[name].returncode is not None:
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
        final = workers.get("final")
        if (final and final.returncode is None and not busy()
                and time.monotonic() - last_used.get("final", 0) > FINAL_IDLE_SECONDS):
            log("worker.idle_unload", worker="final")
            await stop_worker("final")
        vram = max((int(p.read_text()) for p in Path("/sys/class/drm").glob("card*/device/mem_info_vram_used")), default=0)
        memory = dict(line.split(":", 1) for line in Path("/proc/meminfo").read_text().splitlines())
        available = int(memory["MemAvailable"].split()[0]) * 1024
        for name, process in sorted(list(workers.items()), key=lambda item: item[0] != "final"):
            if process.returncode is not None:
                continue
            try:
                status = dict(line.split(":", 1) for line in Path(f"/proc/{process.pid}/status").read_text().splitlines() if ":" in line)
            except FileNotFoundError:
                continue
            anonymous = int(status.get("RssAnon", "0").split()[0]) * 1024
            swap = int(status.get("VmSwap", "0").split()[0]) * 1024
            for state in sessions.values():
                if active(state):
                    peaks = state.setdefault("resources", {})
                    for key, value in {"total_vram_bytes": vram, "anonymous_ram_bytes": anonymous, "swap_bytes": swap}.items():
                        peaks[key] = max(peaks.get(key, 0), value)
            # Low host RAM only counts against a worker that is itself holding
            # RAM: the models live on the GPU, so stopping a ~100 MiB process
            # frees nothing and costs a minute-long reload on the next recording.
            hungry = available < 3 * 1024**3 and anonymous + swap > 1024**3
            if vram > 19.5 * 1024**3 or hungry or anonymous > 6 * 1024**3 or swap > 256 * 1024**2:
                log("worker.memory_guard", worker=name, pid=process.pid, total_vram=vram,
                    available_ram=available, anonymous_ram=anonymous, swap=swap,
                    recordings=[s["id"] for s in sessions.values() if active(s)])
                await stop_worker(name)
                break


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
    public.update({key: state[key] for key in ("context", "resources", "audio_sha256", "runtime", "segments", "refined_bytes", "quality_bytes", "quality_text", "quality_segments", "background_error", "refine_after") if key in state})
    path = ROOT / state["id"] / "state.json"
    temporary = path.with_suffix(".new")
    temporary.write_text(json.dumps(public))
    temporary.replace(path)


def result(state):
    return {k: state[k] for k in ("id", "status", "draft", "final", "error", "bytes")}


async def receive(state, ws, base):
    partial = ""
    completed = [base] if base else []
    try:
        async for message in ws:
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
                log("preview.error", state, detail=str(event)[:300])
            state["draft"] = " ".join(completed + [partial]).strip()
    except (OSError, ValueError):
        pass


async def preview(state, client):
    """Feed the retained audio to the streaming recogniser.

    The draft is a convenience, never a precondition for recording: this reads
    from the audio file, so it starts late, catches up, and reconnects after a
    worker restart without the browser noticing.
    """
    path = ROOT / state["id"] / "audio.pcm"
    sent = failures = 0
    base = ""  # everything is replayed from the file, including after a restart
    while state["status"] == "recording" or (state["status"] == "finalizing" and sent < state["bytes"]):
        ws = reader = None
        try:
            await start_worker("preview", client)
            ws = await client.ws_connect(
                NEMO + "/v1/audio/transcriptions/realtime", timeout=ClientWSTimeout(ws_close=10)
            )
            await ws.send_json({"type": "session.update", "session": {
                "sample_rate": 16000, "language": "en", "automatic_punctuation": True,
            }})
            reader = asyncio.create_task(receive(state, ws, base))
            while not reader.done():
                with path.open("rb") as audio:
                    audio.seek(sent)
                    pcm = audio.read(SAMPLE_BYTES)
                pcm = pcm[:len(pcm) // 2 * 2]
                if pcm:
                    await ws.send_bytes(pcm)
                    sent += len(pcm)
                    failures = 0
                elif state["status"] != "recording":
                    await asyncio.sleep(0.4)  # let the last words arrive
                    return
                else:
                    await asyncio.sleep(0.1)
        except asyncio.CancelledError:
            raise
        except Exception as error:
            log("preview.interrupted", state, error_type=type(error).__name__, error=str(error))
        finally:
            if ws is not None:
                await ws.close()
            if reader is not None:
                reader.cancel()
                await asyncio.gather(reader, return_exceptions=True)
        base = state["draft"]
        failures += 1
        await asyncio.sleep(min(10, failures))


def chunk_end(pcm, start, finishing=False, seconds=CHUNK_SECONDS):
    """Prefer a pause near the end of a bounded transcription window."""
    limit = min(len(pcm), start + seconds * SAMPLE_BYTES)
    if not finishing and len(pcm) - start < (seconds + 1) * SAMPLE_BYTES:
        return None
    if limit == len(pcm) and finishing:
        return limit
    # Find the quietest 300 ms window, splitting at its midpoint. A short
    # acoustic overlap on the following request protects continuous speech.
    # A confirmed quiet boundary needs no overlap (which can duplicate words).
    best = (float("inf"), limit)
    for end in range(start + int(seconds * .75) * SAMPLE_BYTES, limit + 1, 3200):
        samples = array.array("h", pcm[end - 9600:end])
        energy = sum(x * x for x in samples) / max(1, len(samples))
        if energy < best[0]:
            best = (energy, end - 4800)
    return best[1]


def chunk_start(pcm, offset, end):
    if not offset:
        return 0
    # Microphones differ: the long reference recording has a ~700 PCM noise
    # floor, whereas the newer microphone is ~10. Estimate background locally
    # rather than treating every pause in the noisier recording as speech.
    samples = array.array("h", pcm[max(0, offset - 10 * SAMPLE_BYTES):end])
    energies = sorted(sum(x * x for x in samples[i:i + 1600]) / len(samples[i:i + 1600])
                      for i in range(0, len(samples), 1600))
    noise = energies[len(energies) // 10] if energies else 0
    pause = array.array("h", pcm[max(0, offset - 4800):offset + 4800])
    quiet = pause and sum(x * x for x in pause) / len(pause) <= max(100**2, noise * 2)
    return offset if quiet else max(0, offset - 2 * SAMPLE_BYTES)


def merge_transcripts(previous, current):
    """Remove only a shared word sequence from the two-second acoustic overlap."""
    if not previous:
        return current
    left = list(re.finditer(r"[\w]+", previous.lower()))
    right = list(re.finditer(r"[\w]+", current.lower()))
    for count in range(min(24, len(left), len(right)), 1, -1):
        if [m.group() for m in left[-count:]] == [m.group() for m in right[:count]]:
            current = current[right[count - 1].end():].lstrip(" ,.;:!?—-\n")
            break
    return " ".join(part for part in (previous, current) if part)


async def refine_available(state, client, finishing=False, quality=False, seconds=None):
    # The short background sections are progress, not the final quality result.
    # Keep separate checkpoints so retries never mistake them for the long-context pass.
    offset_key = "quality_bytes" if quality else "refined_bytes"
    text_key = "quality_text" if quality else "final"
    segments_key = "quality_segments" if quality else "segments"
    seconds = seconds or (QUALITY_SECONDS if quality else CHUNK_SECONDS)
    async with final_lock:
        pcm_path = ROOT / state["id"] / "audio.pcm"
        pcm = pcm_path.read_bytes()
        while (end := chunk_end(pcm, state.get(offset_key, 0), finishing, seconds)) is not None:
            offset = state.get(offset_key, 0)
            if end <= offset:
                break
            start = chunk_start(pcm, offset, end)
            quiet_boundary = start == offset
            wav = pcm_path.parent / f"chunk-{offset}-{end}.wav"
            with wave.open(str(wav), "wb") as output:
                output.setnchannels(1)
                output.setsampwidth(2)
                output.setframerate(16000)
                output.writeframes(pcm[start:end])
            began = time.monotonic()
            log("refinement.start", state, quality=quality, start=start, end=end)
            await start_worker("final", client)
            context, state["vocabulary"] = await asyncio.to_thread(project_context, state["project"], state["draft"])
            state["context"] = context
            async with client.post(VIBE + "/v1/audio/transcriptions", json={
                "model": "vibevoice", "audio": str(wav), "language": "en", "text": context,
                "options": {"temperature": 0, "max_tokens": 4096 if quality else 1024,
                            "num_beams": 1, "audio_chunk_mode": "none"},
            }, timeout=ClientTimeout(total=300)) as response:
                response.raise_for_status()
                data = await response.json()
            text = data.get("text", "").strip()
            text = re.sub(r"\[(?:breathing|silence|noise|environmental sounds|music|laughter)\]\s*", "", text, flags=re.I).strip()
            if not text:
                log("refinement.no_speech", state, start=start, end=end)
            state.pop("background_error", None)
            log("refinement.complete", state, quality=quality, start=start, end=end,
                seconds=round(time.monotonic() - began, 3), characters=len(text))
            previous = state.get(text_key, "")
            state[text_key] = (" ".join(filter(None, (previous, text))) if quiet_boundary
                               else merge_transcripts(previous, text))
            state.setdefault(segments_key, []).append(dict(start=start, end=end, text=text))
            state[offset_key] = end
            if quality and end == len(pcm):
                if not state[text_key]:
                    raise EmptyTranscript("The recognizer returned an empty transcript.")
                state["final"] = state[text_key]
            save(state)
            if end == len(pcm):
                break


async def refine_background(state, client):
    try:
        await refine_available(state, client)
    except Exception as error:
        # A failed progress pass is recoverable; do not turn it into a persistent
        # red UI error while the microphone and draft are still working.
        state["background_error"] = type(error).__name__
        state["refine_after"] = time.time() + 15
        log("refinement.background_failed", state, error_type=type(error).__name__, error=str(error))
        save(state)


def restart_quality(state):
    for key in ("quality_bytes", "quality_text", "quality_segments"):
        state.pop(key, None)


def truncated(state):
    """The streaming draft hears every word; a much shorter final lost speech."""
    draft, final = len(state["draft"].split()), len(state["final"].split())
    return draft >= 30 and final < draft * 0.5


async def finalize(state, client):
    """Transcribe the whole recording at full quality, however long that takes.

    Resource failures (GPU taken by another workload, a crashed or guarded
    worker) are waited out and retried with progressively smaller windows. The
    recording only ever leaves "finalizing" with a transcript, or because the
    recogniser twice heard no speech at all.
    """
    state["status"] = "finalizing"
    state["error"] = ""
    began = time.monotonic()
    log("recording.finalizing", state, bytes=state["bytes"])
    save(state)
    try:
        if task := state.get("preview"):
            try:
                await asyncio.wait_for(task, 3)
            except (asyncio.TimeoutError, Exception):
                pass
        if task := state.get("refiner"):
            await asyncio.gather(task, return_exceptions=True)
        pcm = ROOT / state["id"] / "audio.pcm"
        wav = pcm.with_suffix(".wav")
        with wave.open(str(wav), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(16000)
            output.writeframes(pcm.read_bytes())
        state["audio_sha256"] = hashlib.sha256(wav.read_bytes()).hexdigest()
        state["runtime"] = {key: os.environ.get(key) for key in (
            "STT_NEMO_BINARY", "STT_NEMO_MODEL", "STT_VIBE_BINARY", "STT_VIBE_CONFIG"
        )}
        attempt = empties = 0
        candidate = None
        while True:
            seconds = RETRY_WINDOWS[min(attempt, len(RETRY_WINDOWS) - 1)]
            try:
                await refine_available(state, client, finishing=True, quality=True, seconds=seconds)
                if candidate is None and truncated(state) and state["bytes"] > 120 * SAMPLE_BYTES:
                    # One long window dropped speech; redo in shorter windows
                    # and keep whichever transcript is more complete.
                    log("recording.truncated", state, characters=len(state["final"]))
                    candidate = state["final"]
                    restart_quality(state)
                    attempt = max(attempt, 2)
                    continue
                if candidate and len(candidate.split()) > len(state["final"].split()):
                    state["final"] = candidate
                break
            except asyncio.CancelledError:
                raise
            except EmptyTranscript:
                empties += 1
                restart_quality(state)
                if empties >= 2:
                    state["final"] = candidate or ""
                    break
            except Exception as error:
                log("recording.retry", state, attempt=attempt, error_type=type(error).__name__,
                    error=str(error), resources=state.get("resources"))
                # A worker that answered with an error may be wedged; a fresh
                # one is cheap next to a transcript that never arrives.
                if attempt % 2:
                    await stop_worker("final")
                save(state)
                await asyncio.sleep(min(60, 2 * 2 ** min(attempt, 5)))
            attempt += 1
        state["status"] = "complete"
        log("recording.complete", state, seconds=round(time.monotonic() - began, 3),
            characters=len(state["final"]), attempts=attempt + 1)
    finally:
        # Interrupted by shutdown: stays "finalizing" on disk and resumes at start.
        save(state)


def ensure_preview(state, client):
    task = state.get("preview")
    if task is None or task.done():
        state["preview"] = asyncio.create_task(preview(state, client))


async def warm(name, client):
    try:
        await start_worker(name, client)
    except Exception as error:
        log("worker.warm_failed", worker=name, error=str(error))


async def action(request):
    data = await request.json()
    owner = request.headers.get("X-STT-Owner", "")
    if not owner:
        raise web.HTTPUnauthorized()
    kind = data.get("action")
    if kind == "start":
        # Never make the microphone wait: accept at once, load models behind it.
        # The browser names the recording, which makes a retried start harmless.
        identifier = str(data.get("id") or uuid.uuid4())
        if not re.fullmatch(r"[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}", identifier):
            raise web.HTTPBadRequest(text="Invalid recording identifier.")
        if existing := sessions.get(identifier):
            if existing["owner"] != owner:
                raise web.HTTPConflict(text="Recording identifier is already in use.")
            return web.json_response(result(existing))
        log("recording.start", recording_id=identifier)
        (ROOT / identifier).mkdir(mode=0o700, parents=True)
        (ROOT / identifier / "audio.pcm").touch(mode=0o600)
        state = dict(id=identifier, owner=owner, project=str(data.get("project", "")),
                     status="recording", draft="", final="", error="", bytes=0,
                     created=time.time(), vocabulary=[], sequence=0, touched=time.time())
        sessions[identifier] = state
        save(state)
        ensure_preview(state, request.app["client"])
        spawn(warm("final", request.app["client"]))
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
        state["touched"] = time.time()
        save(state)
        ensure_preview(state, request.app["client"])
        if (state["bytes"] - state.get("refined_bytes", 0) >= (CHUNK_SECONDS + 1) * SAMPLE_BYTES
                and time.time() >= state.get("refine_after", 0)):
            task = state.get("refiner")
            if task is None or task.done():
                state["refiner"] = asyncio.create_task(refine_background(state, request.app["client"]))
    elif kind in {"finish", "retry"}:
        if state["status"] not in {"finalizing", "complete"}:
            if not state["bytes"]:
                raise web.HTTPBadRequest(text="No audio was recorded.")
            state["status"] = "finalizing"
            state["task"] = asyncio.create_task(finalize(state, request.app["client"]))
    elif kind == "cancel":
        for key in ("task", "preview", "refiner"):
            if task := state.get(key):
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)
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
            # Unfinished work survives a restart: a recording keeps accepting
            # audio where it stopped, and a transcription resumes below.
            sessions[state["id"]] = state
        except (ValueError, KeyError):
            continue
    async with ClientSession(timeout=ClientTimeout(total=30)) as client:
        app["client"] = client
        watcher = asyncio.create_task(monitor())
        async def warm_all():
            for name in ("preview", "final"):
                await warm(name, client)
        warmer = asyncio.create_task(warm_all())
        for state in sessions.values():
            if state["status"] == "finalizing":
                state["task"] = asyncio.create_task(finalize(state, client))
        yield
        warmer.cancel()
        await asyncio.gather(warmer, return_exceptions=True)
        watcher.cancel()
        tasks = []
        for state in sessions.values():
            for key in ("preview", "task", "refiner"):
                if task := state.get(key):
                    task.cancel()
                    tasks.append(task)
        tasks.extend(background)
        for task in background:
            task.cancel()
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
    app.router.add_post("/release-gpu", release_gpu)
    web.run_app(app, host="127.0.0.1", port=int(os.environ.get("STT_PORT", "8781")), access_log=None)

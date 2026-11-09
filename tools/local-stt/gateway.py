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

from aiohttp import ClientSession, ClientTimeout, ClientWSTimeout, FormData, WSMsgType, web

ROOT = Path(os.environ.get("STT_RECORDINGS", "/var/lib/local-stt"))
# llama-swap runs both recognisers, like every other model on this GPU: it
# starts them, keeps what fits loaded, queues a request until its model fits,
# and never stops a model that is still answering one (modules/nixos/local-stt.nix).
LLAMA_SWAP = os.environ.get("STT_LLAMA_SWAP_URL", "http://127.0.0.1:8000")
PREVIEW_MODEL = "dictation-preview"
FINAL_MODEL = "dictation-final"
NEMO = f"{LLAMA_SWAP}/upstream/{PREVIEW_MODEL}"
VIBE = f"{LLAMA_SWAP}/upstream/{FINAL_MODEL}"
# A final pass may wait in llama-swap's queue behind a running job (it does
# not interrupt one) and for its model to load, before transcribing.
FINAL_TIMEOUT = 600
# Once dictation has been idle this long, the GPU is lent to this llama-swap
# model (read-aloud's big voice) unless something outside LLAMA_SWAP_KEEP runs.
# Loading it makes llama-swap unload the idle final recogniser.
FINAL_IDLE_SECONDS = float(os.environ.get("STT_FINAL_IDLE_SECONDS", "1800"))
LLAMA_SWAP_KEEP = set(filter(None, os.environ.get("STT_LLAMA_SWAP_KEEP", "").split(",")))
IDLE_WARM_MODEL = os.environ.get("STT_IDLE_WARM_MODEL", "")
final_used = time.monotonic()
# Recordings are not time-limited for the user (Erik talks for half an hour
# and more); this only bounds a runaway client: four hours of 16 kHz PCM.
MAX_BYTES = 16000 * 2 * 4 * 60 * 60
sessions = {}
final_lock = asyncio.Lock()
SAMPLE_BYTES = 32000
CHUNK_SECONDS = 30
QUALITY_SECONDS = 420
# Final-pass window per attempt. Shorter windows need less GPU scratch memory,
# so a recording that cannot be transcribed in one piece still completes.
RETRY_WINDOWS = (QUALITY_SECONDS, QUALITY_SECONDS, 120, 120, CHUNK_SECONDS)
# A pass that heard nothing while the live draft heard words is redone in short
# windows: a loud burst early in a clip made the recogniser call all 15 s of
# "Tell me about the packages I need to get today" unintelligible (2026-11-02).
EMPTY_RETRY_WINDOWS = (10, 5)
ACTIVE_SECONDS = 120
background = set()
# The self-test streams this spoken clip to the live recogniser every
# SELFTEST_SECONDS; /health/deep fails while it does not come back as words.
PROBE_PCM = os.environ.get("STT_PROBE_PCM", "")
SELFTEST_SECONDS = 60
FINAL_STUCK_SECONDS = 600
selftest = {"ok": None, "error": "not run yet", "passed": 0.0}


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



async def llama_swap_running(client):
    """Model -> state ("ready", "starting", ...) of what llama-swap has loaded."""
    async with client.get(LLAMA_SWAP + "/running", timeout=ClientTimeout(total=5)) as response:
        return {entry.get("model", ""): entry.get("state", "")
                for entry in (await response.json()).get("running", [])}


async def unload(client, model):
    """Restart one of dictation's own recognisers after it stopped answering.

    Never used to make room: llama-swap does that, and only with idle models.
    Stopping a model this way fails the requests it is serving.
    """
    try:
        async with client.post(f"{LLAMA_SWAP}/api/models/unload/{model}",
                               timeout=ClientTimeout(total=30)) as response:
            log("worker.unloaded", worker=model, status=response.status)
    except (OSError, asyncio.TimeoutError) as error:
        log("worker.unload_failed", worker=model, error=str(error))


async def warm(model, client):
    """Have llama-swap load a model now (it queues until the model fits)."""
    global final_used
    if model == FINAL_MODEL:
        final_used = time.monotonic()
    try:
        async with client.get(f"{LLAMA_SWAP}/upstream/{model}/v1/models",
                              timeout=ClientTimeout(total=FINAL_TIMEOUT)) as response:
            log("worker.warm", worker=model, status=response.status)
    except (OSError, asyncio.TimeoutError) as error:
        log("worker.warm_failed", worker=model, error=str(error))


async def warm_idle_model(client):
    if not IDLE_WARM_MODEL:
        return
    try:
        running = await llama_swap_running(client)
        ours = LLAMA_SWAP_KEEP | {IDLE_WARM_MODEL, PREVIEW_MODEL, FINAL_MODEL}
        if IDLE_WARM_MODEL in running or any(model not in ours for model in running):
            log("worker.idle_warm_skipped", running=sorted(running))
            return
    except (OSError, asyncio.TimeoutError, ValueError) as error:
        log("worker.idle_warm_failed", error=str(error))
        return
    log("worker.idle_warm", model=IDLE_WARM_MODEL)
    await warm(IDLE_WARM_MODEL, client)


async def idle_lender(client):
    """Lend the GPU to IDLE_WARM_MODEL once per idle period of dictation."""
    lent_for = None
    while True:
        await asyncio.sleep(60)
        if (not busy() and lent_for != final_used
                and time.monotonic() - final_used > FINAL_IDLE_SECONDS):
            lent_for = final_used
            await warm_idle_model(client)


def active(state):
    """A recording whose browser went away must not hold the GPU forever."""
    return state["status"] == "finalizing" or (
        state["status"] == "recording" and time.time() - state.get("touched", 0) < ACTIVE_SECONDS)


def busy():
    return any(active(s) for s in sessions.values())


async def dictation_state(client):
    """Whether dictation holds the GPU: a recording in progress, or the final
    recogniser still loaded in llama-swap."""
    try:
        loaded = (await llama_swap_running(client)).get(FINAL_MODEL) == "ready"
    except (OSError, asyncio.TimeoutError, ValueError):
        loaded = False
    return {"busy": busy(), "final_loaded": loaded, "active": busy() or loaded}


async def health(request):
    # The speak daemon reads dictation.busy before talking out loud.
    return web.json_response({"ok": True, "dictation": await dictation_state(request.app["client"])})


def problems():
    found = []
    if not selftest["ok"]:
        found.append(f"live draft self-test failing: {selftest['error']}")
    elif time.time() - selftest["passed"] > 5 * SELFTEST_SECONDS:
        found.append("live draft self-test has not passed for 5 minutes")
    for state in sessions.values():
        since = state.get("finalizing_since")
        if state["status"] == "finalizing" and since and time.time() - since > FINAL_STUCK_SECONDS:
            found.append(f"final transcription of {state['id']} stuck for "
                         f"{int(time.time() - since)}s, last error: {state.get('last_error', '')}")
    return found


async def deep_health(_request):
    """What the homelab probes: 503 whenever dictation would not work end to end.
    Failing for 5 minutes fires an alert that starts a repair session."""
    found = problems()
    return web.json_response({"ok": not found, "problems": found, "selftest": selftest},
                             status=503 if found else 200)


async def run_selftest(client):
    pcm = Path(PROBE_PCM).read_bytes()
    async with client.ws_connect(NEMO + "/v1/audio/transcriptions/realtime",
                                 timeout=ClientWSTimeout(ws_close=5)) as ws:
        await ws.send_json({"type": "session.update", "session": {
            "sample_rate": 16000, "language": "en", "automatic_punctuation": True,
        }})
        state = {"id": "selftest", "draft": ""}
        reader = asyncio.create_task(receive(state, ws, ""))
        try:
            for start in range(0, len(pcm), SAMPLE_BYTES):
                await ws.send_bytes(pcm[start:start + SAMPLE_BYTES])
            for _ in range(150):
                if len(state["draft"].split()) >= 3:
                    return state["draft"]
                await asyncio.sleep(0.1)
        finally:
            reader.cancel()
            await asyncio.gather(reader, return_exceptions=True)
    raise RuntimeError(f"no words came back (draft {state['draft']!r})")


async def selftest_loop(client):
    while True:
        for attempt in range(2):
            try:
                await asyncio.wait_for(run_selftest(client), 45)
                if selftest["ok"] is False:
                    log("selftest.recovered")
                selftest.update(ok=True, error="", passed=time.time())
                break
            except asyncio.CancelledError:
                raise
            except Exception as error:
                message = f"{type(error).__name__}: {error}"[:300]
                log("selftest.failed", attempt=attempt, error=message)
                selftest.update(ok=False, error=message)
                # Alive but not answering never heals by itself: replace it.
                await unload(client, PREVIEW_MODEL)
        await asyncio.sleep(SELFTEST_SECONDS)


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


FILLER = r"(?:u+h+|u+m+|uhm|erm|er|ah|hmm+|mm+)"


def tidy(text):
    """What clients get: no hesitation fillers or stutters (Erik, 2026-10-19).

    The recogniser transcribes "uh" and "the, the, the" faithfully, and a
    decoder repetition penalty dropped real words in an A/B test, so this is
    text cleanup; the stored transcript keeps every word. Repeats separated by
    commas collapse ("the, the" -> "the"); bare repeats only from three on, so
    "had had" and "that that" survive, while the live draft's "and and and"
    loops do not.
    """
    text = re.sub(rf"(?i)(?<![\w'-])({FILLER})(?![\w'-])[,.;]?\s*", "", text)
    text = re.sub(r"(?i)\b(\w+(?:'\w+)?)(?:,\s+\1\b)+", r"\1", text)
    text = re.sub(r"(?i)\b(\w+(?:'\w+)?)(?:\s+\1\b){2,}", r"\1", text)
    text = re.sub(r"\s+([,.;:!?])", r"\1", text)
    text = re.sub(r"([,;:])(?:\s*[,;:])+", r"\1", text)
    text = re.sub(r"^[\s,;:]+|[\s,;:]+$", "", text)
    text = re.sub(r"[,;:]+([.!?])", r"\1", text)
    text = re.sub(r" {2,}", " ", text)
    # A sentence that began with a filler starts with a capital again.
    return re.sub(r"(^|[.!?]\s+)([a-z])", lambda m: m.group(1) + m.group(2).upper(), text)


def result(state):
    shown = {k: state[k] for k in ("id", "status", "draft", "final", "error", "bytes")}
    # The next append's sequence: a client (or T3's AAC uploader) that lost its
    # place after a restart continues from here instead of resending.
    shown["sequence"] = state.get("sequence", 0)
    shown["draft"], shown["final"] = tidy(shown["draft"]), tidy(shown["final"])
    return shown


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
    # A recording whose client went away stops retrying: it would otherwise keep
    # restarting the shared worker under every live recording, forever.
    while active(state) and (state["status"] == "recording" or sent < state["bytes"]):
        ws = reader = None
        try:
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
            # Reconnect: llama-swap restarts a worker that exited, and the
            # self-test replaces one that is alive but no longer answers.
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
    global final_used
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
            context, state["vocabulary"] = await asyncio.to_thread(project_context, state["project"], state["draft"])
            state["context"] = context
            # Upload the audio rather than name the file: the recogniser runs
            # as llama-swap's user and the recordings stay private to this one.
            # Decoding options are in its config (tools/local-stt/workers.nix).
            form = FormData()
            form.add_field("model", "vibevoice")
            form.add_field("language", "en")
            form.add_field("text", context)
            form.add_field("file", wav.read_bytes(), filename=wav.name, content_type="audio/wav")
            final_used = time.monotonic()
            async with client.post(VIBE + "/v1/audio/transcriptions", data=form,
                                   timeout=ClientTimeout(total=FINAL_TIMEOUT)) as response:
                response.raise_for_status()
                data = await response.json()
            text = data.get("text", "").strip()
            text = re.sub(r"\[(?:breathing|silence|noise|environmental sounds|music|laughter|unintelligible speech|human sounds|inaudible)\]\s*", "", text, flags=re.I).strip()
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


def thin(text, draft):
    """A transcript with under half the draft's words, from a draft long enough to trust."""
    return len(draft.split()) >= 6 and len(text.split()) < len(draft.split()) * 0.5


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
    state.setdefault("finalizing_since", time.time())
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
        partial = ""
        while True:
            seconds = (EMPTY_RETRY_WINDOWS[empties - 1] if empties and state["draft"].strip()
                       else RETRY_WINDOWS[min(attempt, len(RETRY_WINDOWS) - 1)])
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
                if empties and thin(state["final"], state["draft"]):
                    raise EmptyTranscript("The retry kept less than half of the live draft.")
                if candidate and len(candidate.split()) > len(state["final"].split()):
                    state["final"] = candidate
                break
            except asyncio.CancelledError:
                raise
            except EmptyTranscript:
                empties += 1
                if len(state["final"].split()) > len(partial.split()):
                    partial = state["final"]
                restart_quality(state)
                if empties >= (1 + len(EMPTY_RETRY_WINDOWS) if state["draft"].strip() else 2):
                    best = max(candidate or "", partial, key=lambda text: len(text.split()))
                    # Words from the live draft beat a transcript that lost most of them.
                    state["final"] = state["draft"].strip() if thin(best, state["draft"]) else best
                    break
            except Exception as error:
                log("recording.retry", state, attempt=attempt, error_type=type(error).__name__,
                    error=str(error))
                state["last_error"] = f"{type(error).__name__}: {error}"[:300]
                # A worker that answered with an error may be wedged; a fresh
                # one is cheap next to a transcript that never arrives.
                if attempt % 2:
                    await unload(client, FINAL_MODEL)
                save(state)
                await asyncio.sleep(min(60, 2 * 2 ** min(attempt, 5)))
            attempt += 1
        state["status"] = "complete"
        state.pop("finalizing_since", None)
        log("recording.complete", state, seconds=round(time.monotonic() - began, 3),
            characters=len(state["final"]), attempts=attempt + 1)
    finally:
        # Interrupted by shutdown: stays "finalizing" on disk and resumes at start.
        save(state)


def ensure_preview(state, client):
    task = state.get("preview")
    if task is None or task.done():
        state["preview"] = asyncio.create_task(preview(state, client))


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
        spawn(warm(FINAL_MODEL, request.app["client"]))
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
        if PROBE_PCM:
            spawn(selftest_loop(client))
        spawn(idle_lender(client))
        for state in sessions.values():
            if state["status"] == "finalizing":
                state["task"] = asyncio.create_task(finalize(state, client))
        yield
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


if __name__ == "__main__":
    os.umask(0o077)
    app = web.Application(client_max_size=512000)
    app.cleanup_ctx.append(lifecycle)
    app.router.add_post("/dictation", action)
    app.router.add_get("/health", health)
    app.router.add_get("/health/deep", deep_health)
    web.run_app(app, host="127.0.0.1", port=int(os.environ.get("STT_PORT", "8781")), access_log=None)

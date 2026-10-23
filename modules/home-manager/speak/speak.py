"""speak: lets Erik's personal agent talk to him on the PC's speakers.

`speak daemon` (user service, PC only) owns a queue. Every message is turned
into audio at once (the read-aloud voices), then waits until it may play:
never while Erik is dictating on any device (local-stt's /health says
`busy`), never over a T3 read-aloud that is playing, and not to an empty room
(swayidle marks Erik away). After playing it asks the T3 desktop app for the
"Recording now" reply window. `speak mcp` is the stdio MCP server that only
the personal agent's project loads; it hands messages to the daemon.

Every event lands in ~/.local/state/speak/utterances.jsonl and the journal.
"""
import array
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOST = "pc"
PORT = int(os.environ.get("SPEAK_PORT", "8791"))
DAEMON = f"http://127.0.0.1:{PORT}"
STATE = Path(os.environ.get("SPEAK_STATE", Path.home() / ".local/state/speak"))
AWAY_FILE = STATE / "away"
STT_HEALTH = os.environ.get("SPEAK_STT_HEALTH", "http://127.0.0.1:8781/health")
LLAMA_SWAP = os.environ.get("SPEAK_LLAMA_SWAP", "http://127.0.0.1:8000")
BIG = dict(name="big", model=os.environ.get("SPEAK_BIG_MODEL", "higgs-tts"),
           url=f"{LLAMA_SWAP}/upstream/higgs-tts/v1/audio/speech",
           voice=os.environ.get("SPEAK_BIG_VOICE", "erik"),
           speed=float(os.environ.get("SPEAK_BIG_SPEED", "1")))
SMALL = dict(name="small", model="kokoro",
             url=os.environ.get("SPEAK_SMALL_TTS_URL", "http://127.0.0.1:8880/v1/audio/speech"),
             voice=os.environ.get("SPEAK_SMALL_VOICE", "af_heart"),
             speed=float(os.environ.get("SPEAK_SMALL_SPEED", "1.2")))
SUMMARY_MODEL = os.environ.get("SPEAK_SUMMARY_MODEL", "read-aloud-summary")
CHIME = os.environ.get("SPEAK_CHIME", "")
NOTIFY_SEND = os.environ.get("SPEAK_NOTIFY_SEND", "")
HYPRCTL = os.environ.get("SPEAK_HYPRCTL", "/run/current-system/sw/bin/hyprctl")
VOXTYPE = os.environ.get("SPEAK_VOXTYPE", "")
# The reply window: `t3 app speak-reply` in the running T3 desktop app.
REPLY_COMMAND = os.environ.get("SPEAK_REPLY_COMMAND", "")
REPLY_THREAD = os.environ.get("SPEAK_REPLY_THREAD", "personal-agent")
# Erik away and not back: a notification he can answer from the phone.
AWAY_NOTIFY = os.environ.get("SPEAK_AWAY_NOTIFY", "")

PRIORITIES = ("low", "normal", "urgent")
DEFAULT_EXPIRY_MINUTES = {"low": 15, "normal": 60, "urgent": 120}
# Dictation just ended: give the transcript a moment to land as a message.
AFTER_DICTATION_SECONDS = 2.0
POLL_SECONDS = 0.5
MAX_INTERRUPTIONS = 3
ANSWER_WAIT_SECONDS = 600

# Same prompt as T3's read-aloud summary (apps/server/src/readAloud.ts).
SUMMARY_PROMPT = """You turn one message from an AI coding assistant into a short spoken briefing. Text-to-speech will read your output aloud to the person who got the message. They are listening, not reading, so they hear every word once, in order, and cannot skim or scroll back.

Say what the message says, much more simply, like explaining it to a smart friend. Re-explain only: never answer questions, add advice, or invent facts that are not in the message.

What to include, in this order:
1. The point: what happened, what was found or what was decided.
2. Only the details that change what the listener understands or does.
3. What happens next, or what the message is asking the listener to decide. If it ends with a question, end with that question.

How it must sound:
- Plain spoken English. Short sentences. Casual and direct, a light "ok so" or "basically" is fine, but no jokes or filler.
- No markdown, no headings, no bullet points, no lists, no tables, no emoji, no code.
- Never read out file paths, URLs, commands, code, IDs or version strings. Name the thing instead ("the llama-swap config", "your T3 Code fork").
- Write numbers the way you would say them: "about twenty gigabytes", "two to three seconds". Keep only the numbers that matter.
- Drop caveats, hedging and side notes unless they change the decision.
- Usually three to eight sentences. Go longer only if the message really contains more that matters, never more than about 150 words.

Output only the words to be spoken, nothing else."""


# ---------------------------------------------------------------- pure logic

def speakable(text):
    """Markdown read as prose, like T3's speakableText."""
    text = re.sub(r"```[\s\S]*?```", "", text)
    text = re.sub(r"`([^`]*)`", r"\1", text)
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"^\s{0,3}(#{1,6}|>|[-*+]|\d+\.)\s+", "", text, flags=re.M)
    text = re.sub(r"[*_~|]+", " ", text)
    lines = [re.sub(r"[ \t]+", " ", line).strip() for line in text.split("\n")]
    lines = [line if re.search(r"[.!?:;]$", line) else line + "." for line in lines
             if re.search(r"\w", line)]
    return "\n".join(lines)


def sentences(text, limit=260):
    """Sentences for the voice; run-ons are cut at a comma."""
    out = []
    for raw in re.split(r"(?<=[.!?…])[\"')\]]?\s+|\n+", text):
        sentence = re.sub(r"\s+", " ", raw).strip()
        while len(sentence) > limit:
            cut = sentence.rfind(", ", 0, limit)
            if cut < 40:
                break
            out.append(sentence[:cut + 1])
            sentence = sentence[cut + 2:]
        if re.search(r"\w", sentence):
            out.append(sentence)
    return out


def gate(item, now, dictating, dictation_ended, reading_aloud, away, answering=False):
    """What a ready message does now: ("play"|"wait"|"drop", reason)."""
    if now >= item["expires"]:
        return "drop", "expired before Erik could hear it"
    if dictating:
        return "wait", "Erik is dictating"
    if now - dictation_ended < AFTER_DICTATION_SECONDS:
        return "wait", "dictation just ended"
    # One question at a time: the next waits for his answer (or gives up waiting).
    if answering and item["priority"] != "urgent" and now - item["created"] < ANSWER_WAIT_SECONDS:
        return "wait", "Erik has not answered the last message yet"
    if reading_aloud:
        return "wait", "a read-aloud is playing"
    if away and item["priority"] != "urgent":
        if item["priority"] == "low":
            return "drop", "Erik is away from the PC (low priority messages are dropped)"
        return "wait", "Erik is away from the PC"
    return "play", ""


def next_item(items):
    """Urgent first, then oldest."""
    ready = [i for i in items if i["status"] in ("ready", "waiting")]
    rank = {p: n for n, p in enumerate(reversed(PRIORITIES))}
    return min(ready, key=lambda i: (rank[i["priority"]], i["created"]), default=None)


# ------------------------------------------------------------------- audio

def read_wav(data):
    """(sample rate, mono int16 samples) of a WAV; streamed WAVs may carry a bogus size."""
    offset, rate, channels = 12, 24000, 1
    while offset + 8 <= len(data):
        kind = data[offset:offset + 4]
        size = int.from_bytes(data[offset + 4:offset + 8], "little")
        if kind == b"fmt ":
            channels = int.from_bytes(data[offset + 10:offset + 12], "little")
            rate = int.from_bytes(data[offset + 12:offset + 16], "little")
        elif kind == b"data":
            end = offset + 8 + size if 0 < size and offset + 8 + size <= len(data) else len(data)
            body = data[offset + 8:end]
            samples = array.array("h", body[:len(body) - len(body) % 2])
            return rate, samples[::channels] if channels > 1 else samples
        offset += 8 + size + size % 2
    raise ValueError("the voice returned no audio")


def polish(samples, rate, pause_ms=280):
    """Trim the voice's uneven padding, fade the cut, end on one natural pause."""
    start, end = 0, len(samples)
    while start < end and abs(samples[start]) < 400:
        start += 1
    while end > start and abs(samples[end - 1]) < 400:
        end -= 1
    keep = rate * 30 // 1000
    speech = samples[max(0, start - keep):min(len(samples), end + keep)]
    fade = min(rate * 10 // 1000, len(speech) // 2)
    for i in range(fade):
        speech[i] = speech[i] * i // fade
        speech[-1 - i] = speech[-1 - i] * i // fade
    return speech + array.array("h", bytes(2 * (rate * pause_ms // 1000)))


def wav_bytes(samples, rate):
    data = samples.tobytes()
    header = (b"RIFF" + (36 + len(data)).to_bytes(4, "little") + b"WAVEfmt "
              + (16).to_bytes(4, "little") + (1).to_bytes(2, "little") + (1).to_bytes(2, "little")
              + rate.to_bytes(4, "little") + (rate * 2).to_bytes(4, "little")
              + (2).to_bytes(2, "little") + (16).to_bytes(2, "little")
              + b"data" + len(data).to_bytes(4, "little"))
    return header + data


# --------------------------------------------------------------- the world

def http_json(url, body=None, timeout=5):
    request = urllib.request.Request(
        url, data=None if body is None else json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read())


def dictating():
    """local-stt sees every T3 dictation (PC, laptop and phone all go through it);
    voxtype is the desktop's push-to-talk typing."""
    try:
        if http_json(STT_HEALTH, timeout=2)["dictation"]["busy"]:
            return True
    except (OSError, ValueError, KeyError):
        pass  # no gateway, no T3 dictation
    if VOXTYPE:
        try:
            state = subprocess.run([VOXTYPE, "status"], capture_output=True, text=True, timeout=2).stdout
            return state.strip() not in ("", "idle", "stopped")
        except (OSError, subprocess.TimeoutExpired):
            pass
    return False


def big_voice_ready():
    try:
        running = http_json(f"{LLAMA_SWAP}/running", timeout=2).get("running", [])
        return any(r.get("model") == BIG["model"] and r.get("state") == "ready" for r in running)
    except (OSError, ValueError):
        return False


def t3_playback_streams():
    """PipeWire output streams of T3 Code that are running."""
    try:
        nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, timeout=5).stdout)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return []
    return [n["id"] for n in nodes
            if (n.get("info") or {}).get("state") == "running"
            and ((n["info"].get("props") or {}).get("media.class") == "Stream/Output/Audio")
            and "t3" in str(n["info"]["props"].get("application.name", "")).lower()]


def stream_audible(node, seconds=0.6):
    """Electron keeps its stream running in silence, so listen to it briefly."""
    try:
        raw = subprocess.run(
            ["timeout", str(seconds), "pw-record", "--target", str(node), "--format", "s16",
             "--rate", "16000", "--channels", "1", "-"], capture_output=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return False
    samples = array.array("h", raw[:len(raw) - len(raw) % 2])
    return any(abs(s) > 300 for s in samples)


def reading_aloud():
    return any(stream_audible(node) for node in t3_playback_streams())


def away():
    return AWAY_FILE.exists()


def default_sink():
    try:
        out = subprocess.run(["wpctl", "inspect", "@DEFAULT_AUDIO_SINK@"],
                             capture_output=True, text=True, timeout=5).stdout
        match = re.search(r'node\.description = "([^"]*)"', out)
        return match.group(1) if match else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


# ------------------------------------------------------------------ daemon

items = {}
lock = threading.Lock()
wake = threading.Event()


def log(event, item=None, **fields):
    record = {"time": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "event": event}
    if item:
        record.update(id=item["id"], priority=item["priority"])
    record.update(fields)
    line = json.dumps(record, ensure_ascii=False)
    print(line, flush=True)
    with (STATE / "utterances.jsonl").open("a") as out:
        out.write(line + "\n")


def public(item):
    keys = ("id", "status", "reason", "priority", "voice", "text", "spoken_text",
            "created", "spoken_at", "seconds", "sink", "reply_window")
    return {k: item[k] for k in keys if k in item}


def summarize(text):
    answer = http_json(f"{LLAMA_SWAP}/v1/chat/completions", {
        "model": SUMMARY_MODEL, "temperature": 0.3, "top_p": 0.95, "max_tokens": 600,
        "chat_template_kwargs": {"enable_thinking": False},
        "messages": [{"role": "system", "content": SUMMARY_PROMPT},
                     {"role": "user", "content": text}]}, timeout=180)
    return answer["choices"][0]["message"]["content"].strip()


def synthesize(voice, sentence):
    request = urllib.request.Request(voice["url"], data=json.dumps({
        "model": voice["model"], "input": sentence, "voice": voice["voice"],
        "speed": voice["speed"], "response_format": "wav"}).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return read_wav(response.read())


def generate(item):
    """Audio right away, so it plays the moment Erik is free."""
    try:
        words = summarize(item["text"]) if item["summarize"] else item["text"]
        item["spoken_text"] = speakable(words)
        parts = sentences(item["spoken_text"])
        if not parts:
            raise ValueError("nothing to say")
        voices = [BIG, SMALL] if big_voice_ready() else [SMALL]
        for voice in voices:
            try:
                clips = [synthesize(voice, part) for part in parts]
                break
            except (OSError, ValueError) as error:
                # Dictation takes the GPU back by unloading the big voice.
                if voice is voices[-1]:
                    raise
                log("voice.fallback", item, voice=voice["name"], error=str(error))
        rate = clips[0][0]
        audio = array.array("h")
        for clip_rate, samples in clips:
            audio += polish(samples, clip_rate)
        path = STATE / "audio" / f"{item['id']}.wav"
        path.write_bytes(wav_bytes(audio, rate))
        with lock:
            item.update(status="ready", voice=voice["name"], audio=str(path),
                        seconds=round(len(audio) / rate, 1))
        if item["status"] == "ready" and item["summarize"]:
            notice(item, "about to speak")  # now with the spoken words
        log("generated", item, voice=voice["name"], seconds=item["seconds"],
            spoken_text=item["spoken_text"])
    except Exception as error:  # noqa: BLE001 - every failure is reported to the caller
        with lock:
            item.update(status="failed", reason=f"could not make the audio: {error}")
        log("failed", item, error=str(error))
        notice(item, "could not make the audio")
    wake.set()


def play(item):
    """Chime then speech on the default sink; stops if Erik starts dictating."""
    props = '{ application.name = "speak" media.name = "speak: personal agent" media.role = "Notification" }'
    for path in [p for p in (CHIME, item["audio"]) if p]:
        player = subprocess.Popen(["pw-play", "--properties", props, path])
        while player.poll() is None:
            if dictating():
                player.terminate()
                player.wait()
                return False
            time.sleep(0.2)
    return True


def open_reply_window(item):
    if not REPLY_COMMAND:
        return "off"
    try:
        done = subprocess.run([REPLY_COMMAND, "--thread", item.get("thread") or REPLY_THREAD,
                               "--text", item.get("spoken_text") or item["text"], "--queued-at", str(int(item["created"] * 1000))], capture_output=True, text=True, timeout=20)
        return "opened" if done.returncode == 0 else f"failed: {(done.stderr or done.stdout).strip()[:200]}"
    except (OSError, subprocess.TimeoutExpired) as error:
        return f"failed: {error}"


class Notice:
    """The words on screen too (Erik: "if you want me to hear it, I should also see
    it"). One desktop notification, top-left (erikshell's x-erikshell-corner hint,
    clear of T3's Send button), no timeout. The newest message takes it over and
    it follows that message as it waits and plays; every message is also in the
    chat, so older ones need not stay up. Clicking it brings up T3 Code."""

    id = None
    waiter = None
    owner = None  # the item it shows

    @classmethod
    def show(cls, item, status=""):
        if not NOTIFY_SEND:
            return
        with notice_lock:
            if cls.owner is not None and cls.owner is not item:
                if item["created"] < cls.owner["created"]:
                    return  # a newer message has the card
            cls.owner = item
            title = "Personal agent" + (f" · {status}" if status else "")
            body = (item.get("spoken_text") or item["text"])
            body = body.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            command = [NOTIFY_SEND, "--print-id", "--wait", "--expire-time", "0",
                       "--app-name", "Personal agent", "--icon", "audio-speakers",
                       "--hint", "string:x-erikshell-corner:top-left",
                       "--action", "default=Open T3 Code", title, body]
            if cls.id:
                command[1:1] = ["--replace-id", cls.id]
            if cls.waiter and cls.waiter.poll() is None:
                cls.waiter.terminate()  # its action would belong to the old text
            try:
                cls.waiter = subprocess.Popen(command, stdout=subprocess.PIPE, text=True)
            except OSError as error:
                log("notice.failed", item, error=str(error))
                return
            cls.id = cls.waiter.stdout.readline().strip() or cls.id
            threading.Thread(target=cls.clicked, args=(cls.waiter,), daemon=True).start()

    @staticmethod
    def clicked(waiter):
        for line in waiter.stdout:
            if line.strip() == "default":
                subprocess.run([HYPRCTL, "dispatch", "focuswindow", "class:^(com.t3tools.T3Code)$"],
                               capture_output=True, timeout=5)


notice_lock = threading.Lock()


def to_erik(reason):
    """The log speaks about Erik; the notification speaks to him."""
    return (reason.replace("Erik is", "you're").replace("Erik has not", "you haven't")
            .replace("Erik started", "you started").replace("Erik could", "you could"))


def notice(item, status=""):
    Notice.show(item, status)


def answering():
    """The reply window is still open: Erik has not sent or dismissed his answer."""
    if not REPLY_COMMAND:
        return False
    try:
        done = subprocess.run([REPLY_COMMAND, "--status"], capture_output=True, text=True, timeout=10)
        return done.returncode == 0 and bool(json.loads(done.stdout).get("open"))
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return False


def notify_away(item):
    """Held because Erik is away: tell his phone once, silently (it never speaks)."""
    if not AWAY_NOTIFY or item.get("notified"):
        return
    item["notified"] = True
    try:
        subprocess.run([AWAY_NOTIFY, "-p", "low", "-t", "Your agent wants to talk",
                        "--thread", item.get("thread") or REPLY_THREAD, "--dictate", item["spoken_text"][:300]],
                       capture_output=True, timeout=30)
        log("phone.notified", item)
    except (OSError, subprocess.TimeoutExpired) as error:
        log("phone.notify_failed", item, error=str(error))


def worker():
    dictation_ended = 0.0
    was_dictating = False
    while True:
        wake.wait(POLL_SECONDS)
        wake.clear()
        with lock:
            pending = [i for i in items.values() if i["status"] in ("ready", "waiting")]
        if not pending:
            continue
        now = time.time()
        busy = dictating()
        if was_dictating and not busy:
            dictation_ended = now
        was_dictating = busy
        item = next_item(pending)
        decision, reason = gate(item, now, busy, dictation_ended, False, away())
        # The slower checks only when everything else already allows playing.
        if decision == "play" and reading_aloud():
            decision, reason = "wait", "a read-aloud is playing"
        if decision == "play" and answering():
            decision, reason = gate(item, now, busy, dictation_ended, False, away(), True)
        if decision == "drop":
            with lock:
                item.update(status="dropped", reason=reason)
            log("dropped", item, reason=reason)
            notice(item, f"not said: {to_erik(reason)}")
            continue
        if decision == "wait":
            if item.get("reason") != reason or item["status"] != "waiting":
                with lock:
                    item.update(status="waiting", reason=reason)
                log("waiting", item, reason=reason)
                notice(item, f"waiting: {to_erik(reason)}")
            if reason == "Erik is away from the PC":
                notify_away(item)
            continue
        sink = default_sink()
        with lock:
            item.update(status="speaking", reason="", sink=sink)
        log("speaking", item, sink=sink, text=item["spoken_text"])
        notice(item, "speaking")
        if not play(item):
            item["interruptions"] = item.get("interruptions", 0) + 1
            with lock:
                item.update(status="waiting", reason="Erik started dictating; it plays again after")
            log("interrupted", item, interruptions=item["interruptions"])
            was_dictating = True
            if item["interruptions"] >= MAX_INTERRUPTIONS:
                with lock:
                    item.update(status="dropped", reason="interrupted by dictation too often")
                log("dropped", item, reason=item["reason"])
                notice(item, f"not said: {to_erik(item['reason'])}")
            continue
        with lock:
            item.update(status="spoken", spoken_at=time.strftime("%H:%M:%S"))
        log("spoken", item, sink=sink)
        notice(item, f"said at {time.strftime('%H:%M')}")
        if item.get("reply", True):
            item["reply_window"] = open_reply_window(item)
            log("reply_window", item, result=item["reply_window"])


def submit(body):
    text = str(body.get("text", "")).strip()
    if not text:
        raise ValueError("text is empty")
    priority = body.get("priority") or "normal"
    if priority not in PRIORITIES:
        raise ValueError(f"priority must be one of {', '.join(PRIORITIES)}")
    minutes = float(body.get("expires_in_minutes") or DEFAULT_EXPIRY_MINUTES[priority])
    now = time.time()
    item = dict(id=uuid.uuid4().hex[:12], text=text, summarize=bool(body.get("summarize")),
                priority=priority, created=now, expires=now + minutes * 60,
                status="generating", reason="", reply=body.get("reply", True) is not False,
                thread=str(body.get("thread") or REPLY_THREAD), source=str(body.get("source", "")))
    with lock:
        items[item["id"]] = item
    log("queued", item, text=text, summarize=item["summarize"], expires_in_minutes=minutes,
        source=item["source"])
    notice(item, "about to speak")
    threading.Thread(target=generate, args=(item,), daemon=True).start()
    return item


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):  # noqa: N802
        if self.path != "/speak":
            return self.reply(404, {"error": "unknown path"})
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
            item = submit(body)
        except (ValueError, TypeError) as error:
            return self.reply(400, {"error": str(error)})
        self.reply(200, public(item))

    def do_GET(self):  # noqa: N802
        if self.path.startswith("/status/"):
            with lock:
                item = items.get(self.path.removeprefix("/status/"))
                body = public(item) if item else None
            return self.reply(200, body) if body else self.reply(404, {"error": "unknown id"})
        if self.path == "/health":
            return self.reply(200, {"ok": True, "dictating": dictating(), "away": away(),
                                    "queue": [public(i) for i in items.values()
                                              if i["status"] in ("generating", "ready", "waiting", "speaking")]})
        self.reply(404, {"error": "unknown path"})

    def log_message(self, *_args):
        pass


def daemon():
    if socket.gethostname() != HOST:
        sys.exit(f"speak only runs on the PC ({HOST}), this is {socket.gethostname()}")
    (STATE / "audio").mkdir(parents=True, exist_ok=True)
    cutoff = time.time() - 7 * 86400
    for old in (STATE / "audio").glob("*.wav"):
        if old.stat().st_mtime < cutoff:
            old.unlink()
    threading.Thread(target=worker, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


# --------------------------------------------------------------------- MCP

TOOL = {
    "name": "speak",
    "description": (
        "Say something out loud to Erik on his PC's speakers, unprompted, to start a spoken "
        "back-and-forth: 'can you approve this', 'can you answer this question', 'take a look at "
        "these screenshots', something finished, a meeting soon, 'here's the work, try it'. "
        "Post the details (lists, screenshots, comparisons, thread links) as your chat message "
        "first, then call speak with only the short spoken call to action; his reply window shows "
        "it and opens that message. Ask one question per call: the next one waits for his answer. "
        "Write `text` for listening (short, plain spoken sentences, no paths/URLs/code) or set "
        "`summarize` to turn a long written message into a spoken briefing. The audio is made at "
        "once and plays as soon as Erik is free: never while he is dictating or a read-aloud "
        "plays, and not while he is away from the PC (low: dropped, normal: held until he is "
        "back or it expires, and his phone gets a silent notification; urgent: plays anyway). "
        "A soft chime comes first. After it speaks, a small 'Recording now' window opens on his "
        "PC so he can answer by voice; his answer arrives in this thread as his message. "
        "PC only: refused on the laptop, never on the phone. Returns the status "
        "(speaking/spoken/waiting with the reason/dropped/failed) and an id for speak_status."),
    "inputSchema": {
        "type": "object",
        "properties": {
            "text": {"type": "string", "description": "What to say, written for the ear."},
            "summarize": {"type": "boolean", "default": False,
                          "description": "Rewrite `text` as a short spoken briefing first (local model)."},
            "priority": {"type": "string", "enum": list(PRIORITIES), "default": "normal"},
            "expires_in_minutes": {"type": "number",
                                   "description": "Drop it if not heard by then (default low 15, normal 60, urgent 120)."},
            "reply": {"type": "boolean", "default": True,
                      "description": "Open the 'Recording now' reply window after speaking."},
        },
        "required": ["text"],
    },
}
STATUS_TOOL = {
    "name": "speak_status",
    "description": "Status of an earlier speak call (waiting/speaking/spoken/dropped/failed, and why).",
    "inputSchema": {"type": "object", "properties": {"id": {"type": "string"}}, "required": ["id"]},
}


def call_tool(name, args):
    """(is_error, result dict)."""
    if socket.gethostname() != HOST:
        return True, {"status": "refused", "reason": (
            f"speak only talks on the PC's speakers; this is {socket.gethostname()}. "
            "It never speaks on the laptop or the phone.")}
    try:
        if name == "speak_status":
            return False, http_json(f"{DAEMON}/status/{args.get('id', '')}")
        if name != "speak":
            return True, {"error": f"unknown tool {name}"}
        args = dict(args, source=args.get("source") or "personal-agent")
        item = http_json(f"{DAEMON}/speak", args, timeout=10)
        # Short messages are usually spoken within seconds; report that, else the wait reason.
        deadline = time.time() + 25
        while item["status"] in ("generating", "ready") or (
                item["status"] == "speaking" and time.time() < deadline):
            if time.time() >= deadline:
                break
            time.sleep(0.5)
            item = http_json(f"{DAEMON}/status/{item['id']}")
        return item["status"] == "failed", item
    except urllib.error.HTTPError as error:
        return True, {"status": "failed", "reason": error.read().decode(errors="replace")}
    except OSError as error:
        return True, {"status": "failed", "reason": f"the speak daemon is not reachable: {error}"}


def mcp():
    for line in sys.stdin:
        if not line.strip():
            continue
        message = json.loads(line)
        method, ident = message.get("method"), message.get("id")
        if ident is None:
            continue  # notifications
        if method == "initialize":
            result = {"protocolVersion": message["params"].get("protocolVersion", "2025-06-18"),
                      "capabilities": {"tools": {}},
                      "serverInfo": {"name": "speak", "version": "1.0"}}
        elif method == "tools/list":
            result = {"tools": [TOOL, STATUS_TOOL]}
        elif method == "tools/call":
            is_error, body = call_tool(message["params"]["name"], message["params"].get("arguments") or {})
            result = {"content": [{"type": "text", "text": json.dumps(body, ensure_ascii=False)}],
                      "isError": is_error}
        elif method == "ping":
            result = {}
        else:
            print(json.dumps({"jsonrpc": "2.0", "id": ident,
                              "error": {"code": -32601, "message": f"unknown method {method}"}}), flush=True)
            continue
        print(json.dumps({"jsonrpc": "2.0", "id": ident, "result": result}), flush=True)


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "daemon":
        daemon()
    elif command == "mcp":
        mcp()
    elif command == "say":  # speak say "text" [priority]: for scripts and testing
        is_error, body = call_tool("speak", {"text": sys.argv[2],
                                              "priority": sys.argv[3] if len(sys.argv) > 3 else "normal",
                                              "source": "cli"})
        print(json.dumps(body, indent=2, ensure_ascii=False))
        sys.exit(1 if is_error else 0)
    else:
        sys.exit("usage: speak daemon | speak mcp | speak say TEXT [low|normal|urgent]")

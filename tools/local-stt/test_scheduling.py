"""The production llama-swap config, run for real, with fake model servers.

Takes the settings Nix generates for the PC, swaps every model's command for a
tiny fake server, and checks how the real llama-swap binary shares the GPU
between dictation, read-aloud and the big LLMs; then runs the real gateway
through it for whole recordings. No GPU, no production service is touched.

  nix eval --json .#nixosConfigurations.pc.config.services.llama-swap.settings > settings.json
  LLAMA_SWAP_SETTINGS=settings.json LLAMA_SWAP_BINARY=$(which llama-swap) \
    python3 tools/local-stt/test_scheduling.py   # python3 with aiohttp

Files go in a temporary directory below the working directory and every child
process is stopped at the end.
"""
import asyncio
import base64
import copy
import json
import os
from pathlib import Path
import shlex
import socket
import sys
import tempfile
import time
import unittest
import uuid

from aiohttp import ClientSession, ClientTimeout, WSMsgType, web

HERE = Path(__file__).resolve().parent


def port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


async def backend():
    """One fake model server: answers like the real one, logs what it saw."""
    name, number, directory = sys.argv[2:]
    root = Path(directory)

    def event(kind, **fields):
        with (root / "events.jsonl").open("a") as f:
            f.write(json.dumps(dict(model=name, kind=kind, time=time.monotonic(), pid=os.getpid(), **fields)) + "\n")

    event("start")
    slow = root / f"{name}.slow"
    if slow.exists():  # a model that takes this many seconds to load
        await asyncio.sleep(float(slow.read_text()))

    async def realtime(request):
        # Nemotron's realtime protocol, as far as the gateway uses it.
        ws = web.WebSocketResponse()
        await ws.prepare(request)
        event("ws-start")
        async for msg in ws:
            if msg.type == WSMsgType.BINARY:
                await ws.send_json({"type": "transcription.delta", "delta": "word "})
        event("ws-end")
        return ws

    async def transcribe(request):
        # VibeVoice's multipart upload: the gateway must send bytes, not a path.
        form = await request.post()
        audio = form["file"]
        data = audio.file.read()
        event("transcribe", filename=audio.filename, size=len(data), riff=data[:4] == b"RIFF",
              fields=sorted(k for k in form.keys() if k != "file"))
        await asyncio.sleep(float(os.environ.get("FAKE_DELAY", "0")))
        return web.json_response({"text": f"final transcript of {len(data)} bytes"})

    async def handle(request):
        if request.path == "/work":
            event("work-start")
            await asyncio.sleep(float(request.query.get("delay", "0")))
            event("work-end")
        return web.json_response(dict(model=name, path=request.path))

    app = web.Application(client_max_size=64 * 1024**2)
    app.router.add_get("/v1/audio/transcriptions/realtime", realtime)
    app.router.add_post("/v1/audio/transcriptions", transcribe)
    app.router.add_route("*", "/{path:.*}", handle)
    runner = web.AppRunner(app)
    await runner.setup()
    await web.TCPSite(runner, "127.0.0.1", int(number)).start()
    await asyncio.Event().wait()


class Harness(unittest.IsolatedAsyncioTestCase):
    """A real llama-swap running the production config with fake models."""
    ttl = {}

    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix=".sched-test-", dir=Path.cwd())
        self.root = Path(self.temp.name)
        self.children = []
        self.tasks = []
        self.client = ClientSession(timeout=ClientTimeout(total=30))
        settings = json.loads(Path(os.environ["LLAMA_SWAP_SETTINGS"]).read_text())
        config = copy.deepcopy(settings)
        config.update(healthCheckTimeout=10, logLevel="debug", performance={"disabled": True})
        for name, model in config["models"].items():
            number = port()
            model.update(
                cmd=shlex.join([sys.executable, str(Path(__file__).resolve()), "--backend", name, str(number), str(self.root)]),
                proxy=f"http://127.0.0.1:{number}", checkEndpoint="/health")
            model.pop("cmdStop", None)
            model.pop("ttl", None)
            if name in self.ttl:
                model["ttl"] = self.ttl[name]
        (self.root / "config.yaml").write_text(json.dumps(config))
        self.base = f"http://127.0.0.1:{port()}"
        self.log = (self.root / "swap.log").open("w+")
        self.swap = await self.start([os.environ["LLAMA_SWAP_BINARY"], "--config", str(self.root / "config.yaml"),
                                      "--listen", self.base.removeprefix("http://")], self.log)
        await self.until(lambda: self.ok(self.base + "/health"), "llama-swap did not start")
        # The startup preload: live recogniser and summary model.
        await self.until(self.preloaded, "preload did not finish")

    async def asyncTearDown(self):
        for task in self.tasks:
            task.cancel()
        await asyncio.gather(*self.tasks, return_exceptions=True)
        await self.client.close()
        for child in reversed(self.children):
            if child.returncode is None:
                child.terminate()
                try:
                    await asyncio.wait_for(child.wait(), 10)
                except asyncio.TimeoutError:
                    child.kill()
        self.log.close()
        self.temp.cleanup()

    async def start(self, command, output, **kwargs):
        child = await asyncio.create_subprocess_exec(*command, stdout=output, stderr=output, **kwargs)
        self.children.append(child)
        return child

    async def ok(self, url):
        try:
            async with self.client.get(url) as response:
                return response.status == 200
        except OSError:
            return False

    async def until(self, check, message, seconds=15):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if await check():
                return
            await asyncio.sleep(0.05)
        self.fail(message + "\n" + (self.root / "swap.log").read_text()[-3000:])

    async def running(self, state="ready"):
        async with self.client.get(self.base + "/running") as response:
            return {m["model"] for m in (await response.json())["running"] if state is None or m["state"] == state}

    async def preloaded(self):
        return {"dictation-preview", "read-aloud-summary"} <= await self.running()

    async def request(self, model, path="/work", **query):
        async with self.client.get(f"{self.base}/upstream/{model}{path}", params=query) as response:
            return response.status

    async def load(self, model):
        """Have llama-swap load a model, without a request the fake logs as work."""
        self.assertEqual(await self.request(model, "/v1/models"), 200)

    def launch(self, model, path="/work", **query):
        task = asyncio.create_task(self.request(model, path, **query))
        self.tasks.append(task)
        return task

    def events(self, model=None, kind=None):
        file = self.root / "events.jsonl"
        values = [json.loads(line) for line in file.read_text().splitlines()] if file.exists() else []
        return [e for e in values if (model is None or e["model"] == model) and (kind is None or e["kind"] == kind)]

    async def wait_event(self, model, kind, count=1):
        async def seen():
            return len(self.events(model, kind)) >= count
        await self.until(seen, f"no {model}/{kind} event")


class SharingTests(Harness):
    async def test_dictation_loads_beside_the_live_draft_and_summary(self):
        self.assertEqual(await self.request("dictation-final"), 200)
        self.assertEqual(await self.running(), {"dictation-preview", "read-aloud-summary", "dictation-final"})

    async def test_big_voice_and_final_recogniser_take_turns_keeping_the_rest(self):
        await self.load("dictation-final")
        self.assertEqual(await self.request("higgs-tts"), 200)
        self.assertEqual(await self.running(), {"dictation-preview", "read-aloud-summary", "higgs-tts"})
        self.assertEqual(await self.request("dictation-final"), 200)
        self.assertEqual(await self.running(), {"dictation-preview", "read-aloud-summary", "dictation-final"})
        self.assertEqual(len(self.events("read-aloud-summary", "start")), 1)
        self.assertEqual(len(self.events("dictation-preview", "start")), 1)

    async def test_final_waits_for_a_sentence_being_spoken_then_takes_the_gpu(self):
        await self.load("higgs-tts")
        speaking = self.launch("higgs-tts", delay="1.5")
        await self.wait_event("higgs-tts", "work-start")
        began = time.monotonic()
        self.assertEqual(await self.request("dictation-final"), 200)
        self.assertEqual(await speaking, 200)  # not cut off
        self.assertGreater(time.monotonic() - began, 1.0)
        self.assertNotIn("higgs-tts", await self.running(None))

    async def test_voice_waits_for_a_running_transcription_which_completes(self):
        await self.load("dictation-final")
        transcribing = self.launch("dictation-final", delay="1.5")
        await self.wait_event("dictation-final", "work-start")
        voice = self.launch("higgs-tts")
        await asyncio.sleep(0.5)
        self.assertFalse(self.events("higgs-tts", "start"))
        self.assertEqual(await transcribing, 200)
        self.assertEqual(await voice, 200)
        self.assertEqual(await self.running(), {"dictation-preview", "read-aloud-summary", "higgs-tts"})

    async def test_big_llm_keeps_only_the_live_draft_and_an_open_recording_survives(self):
        await self.load("dictation-final")
        async with self.client.ws_connect(f"{self.base}/upstream/dictation-preview/v1/audio/transcriptions/realtime") as ws:
            await ws.send_bytes(b"\x00\x01" * 800)
            self.assertEqual((await ws.receive_json())["delta"], "word ")
            self.assertEqual(await self.request("qwen3.8-27b"), 200)
            self.assertEqual(await self.running(), {"dictation-preview", "qwen3.8-27b"})
            await ws.send_bytes(b"\x00\x01" * 800)
            self.assertEqual((await ws.receive_json())["delta"], "word ")
        self.assertEqual(await self.request("dictation-final"), 200)
        self.assertEqual(await self.running(), {"dictation-preview", "dictation-final"})
        self.assertEqual(len(self.events("dictation-preview", "start")), 1)

    async def test_speech_is_served_before_a_waiting_voice_and_llm(self):
        await self.load("qwen3.5-27b")
        job = self.launch("qwen3.5-27b", delay="1.5")
        await self.wait_event("qwen3.5-27b", "work-start")
        voice = self.launch("higgs-tts")
        await asyncio.sleep(0.1)
        final = self.launch("dictation-final")
        self.assertEqual(await asyncio.gather(job, final, voice), [200, 200, 200])
        starts = [e["model"] for e in self.events(kind="start") if e["model"] in {"dictation-final", "higgs-tts"}]
        self.assertEqual(starts, ["dictation-final", "higgs-tts"])

    async def test_breeze_fits_beside_summary_but_not_beside_the_final_recogniser(self):
        await self.load("dictation-final")
        self.assertEqual(await self.request("breeze-tts-2"), 200)
        self.assertEqual(await self.running(), {"dictation-preview", "read-aloud-summary", "breeze-tts-2"})

    async def test_crashed_recogniser_restarts_on_the_next_request(self):
        await self.load("dictation-final")
        pid = self.events("dictation-final", "start")[-1]["pid"]
        os.kill(pid, 9)
        await asyncio.sleep(0.5)
        self.assertEqual(await self.request("dictation-final"), 200)
        self.assertEqual(len(self.events("dictation-final", "start")), 2)


class IdleUnloadTests(Harness):
    ttl = {"dictation-final": 1}

    async def test_idle_final_recogniser_unloads_but_never_mid_transcription(self):
        await self.load("dictation-final")
        self.assertEqual(await self.request("dictation-final", delay="2.5"), 200)
        self.assertEqual(len(self.events("dictation-final", "start")), 1)

        async def gone():
            return "dictation-final" not in await self.running(None)
        await self.until(gone, "idle recogniser stayed loaded", seconds=10)
        self.assertEqual(await self.running(), {"dictation-preview", "read-aloud-summary"})


class GatewayTests(Harness):
    """The real gateway, through the real llama-swap, for whole recordings."""

    async def asyncSetUp(self):
        await super().asyncSetUp()
        self.recordings = self.root / "recordings"
        self.probe = self.root / "probe.pcm"
        self.probe.write_bytes(b"\x10\x00" * 16000 * 4)
        self.gateway_url = f"http://127.0.0.1:{port()}"
        env = dict(os.environ, STT_RECORDINGS=str(self.recordings), STT_PORT=self.gateway_url.rsplit(":", 1)[1],
                   STT_LLAMA_SWAP_URL=self.base, STT_PROBE_PCM=str(self.probe),
                   STT_LLAMA_SWAP_KEEP="read-aloud-summary", STT_IDLE_WARM_MODEL="higgs-tts")
        self.gateway_log = (self.root / "gateway.log").open("w+")
        await self.start([sys.executable, str(HERE / "gateway.py")], self.gateway_log, env=env)
        await self.until(lambda: self.ok(self.gateway_url + "/health"), "gateway did not start")

    async def asyncTearDown(self):
        await super().asyncTearDown()
        self.gateway_log.close()

    async def dictation(self, recording, owner="erik", **body):
        async with self.client.post(self.gateway_url + "/dictation", json=dict(id=recording, **body),
                                    headers={"X-STT-Owner": owner}) as response:
            self.assertEqual(response.status, 200, await response.text())
            return await response.json()

    async def record(self, seconds):
        recording = str(uuid.uuid4())
        await self.dictation(recording, action="start", project=str(HERE))
        pcm = b"\x10\x00" * 16000
        for sequence in range(seconds):
            await self.dictation(recording, action="append", sequence=sequence, audio=base64.b64encode(pcm).decode())
        return recording

    async def finish(self, recording):
        await self.dictation(recording, action="finish")
        for _ in range(300):
            state = await self.dictation(recording, action="status")
            if state["status"] == "complete":
                return state
            await asyncio.sleep(0.1)
        self.fail("not complete: " + (self.root / "gateway.log").read_text()[-3000:])

    async def test_recording_gets_a_live_draft_and_a_final_transcript_through_llama_swap(self):
        recording = await self.record(seconds=3)
        state = await self.finish(recording)
        self.assertIn("Word", state["draft"])
        self.assertEqual(state["final"], f"Final transcript of {44 + 3 * 32000} bytes")
        upload = self.events("dictation-final", "transcribe")[-1]
        self.assertTrue(upload["riff"])
        self.assertEqual(upload["size"], 44 + 3 * 32000)
        self.assertEqual(upload["fields"], ["language", "model", "text"])
        # The recording is the gateway's alone: nothing else was asked to open it.
        self.assertEqual(oct((self.recordings / recording).stat().st_mode & 0o777), "0o700")

    async def test_dictation_takes_the_gpu_back_from_the_idle_big_voice(self):
        await self.load("higgs-tts")
        self.assertIn("higgs-tts", await self.running())
        recording = await self.record(seconds=2)
        state = await self.finish(recording)
        self.assertTrue(state["final"])
        self.assertEqual(await self.running(), {"dictation-preview", "read-aloud-summary", "dictation-final"})

    async def test_recording_takes_back_the_gpu_lent_to_a_voice_still_loading(self):
        (self.root / "higgs-tts.slow").write_text("20")
        lend = self.launch("higgs-tts", "/v1/models")  # what the idle lender sends

        async def loading():
            return "higgs-tts" in await self.running("starting")
        await self.until(loading, "voice did not start loading")
        began = time.monotonic()
        recording = await self.record(seconds=2)

        async def final_ready():
            return "dictation-final" in await self.running()
        await self.until(final_ready, "final recogniser waited for the voice", seconds=8)
        self.assertLess(time.monotonic() - began, 8)
        self.assertNotIn("higgs-tts", await self.running(None))
        self.assertNotEqual(await lend, 200)  # the lender's own request, nobody else's
        self.assertTrue((await self.finish(recording))["final"])

    async def test_a_recording_that_waits_behind_a_long_llm_job_still_completes(self):
        await self.load("qwen3.8-27b")
        job = self.launch("qwen3.8-27b", delay="3")
        await self.wait_event("qwen3.8-27b", "work-start")
        recording = await self.record(seconds=2)
        state = await self.dictation(recording, action="status")
        self.assertIn(state["status"], {"recording"})
        state = await self.finish(recording)
        self.assertEqual(await job, 200)  # the LLM's job was not cut off
        self.assertTrue(state["final"])
        self.assertIn("Word", state["draft"])  # the live draft kept working meanwhile

    async def test_deep_health_passes_and_reports_the_final_recogniser(self):
        async def healthy():
            async with self.client.get(self.gateway_url + "/health/deep") as response:
                return response.status == 200
        await self.until(healthy, "self-test did not pass", seconds=20)
        async with self.client.get(self.gateway_url + "/health") as response:
            self.assertEqual((await response.json())["dictation"], {"busy": False, "final_loaded": False, "active": False})
        await self.load("dictation-final")
        async with self.client.get(self.gateway_url + "/health") as response:
            self.assertTrue((await response.json())["dictation"]["final_loaded"])


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--backend":
        asyncio.run(backend())
    else:
        unittest.main(verbosity=2)

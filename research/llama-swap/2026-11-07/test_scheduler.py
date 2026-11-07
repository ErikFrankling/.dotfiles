"""Real llama-swap integration tests; fake inference, no GPU or production calls.

Run with an aiohttp Python environment and LLAMA_SWAP_BINARY set to v268.
The same script is the tiny child backend. All files stay in a temporary
directory below cwd and all child processes are stopped on completion.
"""
import asyncio
import json
import os
from pathlib import Path
import shlex
import socket
import sys
import tempfile
import time
import unittest

from aiohttp import ClientSession, ClientTimeout, WSMsgType, web


def port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


async def backend():
    name, number, directory = sys.argv[2:]
    root = Path(directory)
    if (root / (name + '.fail')).exists():
        sys.exit(1)
    def event(kind):
        with (root / 'events.jsonl').open('a') as f:
            f.write(json.dumps(dict(model=name, kind=kind, time=time.monotonic(), pid=os.getpid())) + '\n')
    event('start')
    async def handle(request):
        if request.path == '/ws':
            ws = web.WebSocketResponse()
            await ws.prepare(request)
            event('ws-start')
            async for msg in ws:
                if msg.type == WSMsgType.TEXT:
                    await ws.send_str(msg.data)
                elif msg.type == WSMsgType.BINARY:
                    await ws.send_bytes(msg.data)
            event('ws-end')
            return ws
        if request.path == '/crash':
            os._exit(7)
        if request.path == '/work':
            event('work-start')
            await asyncio.sleep(float(request.query.get('delay', '0')))
            event('work-end')
        return web.json_response(dict(model=name, path=request.path, pid=os.getpid()))
    app = web.Application()
    app.router.add_route('*', '/{path:.*}', handle)
    runner = web.AppRunner(app)
    await runner.setup()
    await web.TCPSite(runner, '127.0.0.1', int(number)).start()
    await asyncio.Event().wait()


class SchedulerTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='.swap-test-', dir=Path.cwd())
        self.root = Path(self.temp.name)
        self.log = (self.root / 'swap.log').open('w+')
        self.tasks = []
        self.client = ClientSession(timeout=ClientTimeout(total=15))
        self.base = 'http://127.0.0.1:' + str(port())
        self.config = dict(
            healthCheckTimeout=3, logLevel='debug',
            performance={'disabled': True},
            upstream={'ignorePaths': ['^/health$']},
            routing={
                'router': {'use': 'capacity', 'settings': {'capacity': {'pools': {'vram': 15}}}},
                'scheduler': {'use': 'fifo', 'settings': {'fifo': {'priority': {'final': 100, 'preview': 100}}}},
            }, models={})
        # Abstract units, deliberately NOT measured VRAM sizes.
        for name, size, cost in [('preview', 1, 100), ('final', 10, 10),
                                  ('summary', 3, 50), ('voice', 11, 1), ('large', 14, 1), ('serial', 14, 1)]:
            number = port()
            self.config['models'][name] = dict(
                cmd=shlex.join([sys.executable, str(Path(__file__).resolve()), '--backend', name, str(number), str(self.root)]),
                proxy=f'http://127.0.0.1:{number}', checkEndpoint='/health',
                capacities={'vram': size}, evict_cost=cost, ttl=1 if name == 'voice' else 0)
        self.config['models']['serial']['concurrencyLimit'] = 1
        self.config_path = self.root / 'config.yaml'
        self.config_path.write_text(json.dumps(self.config))
        binary = os.environ['LLAMA_SWAP_BINARY']
        self.process = await asyncio.create_subprocess_exec(binary, '--config', str(self.config_path),
            '--listen', self.base.removeprefix('http://'), stdout=self.log, stderr=self.log)
        for _ in range(100):
            try:
                async with self.client.get(self.base + '/health') as response:
                    if response.status == 200:
                        return
            except OSError:
                pass
            if self.process.returncode is not None:
                break
            await asyncio.sleep(.05)
        self.fail('LlamaSwap did not start: ' + (self.root / 'swap.log').read_text()[-2000:])

    async def asyncTearDown(self):
        for task in self.tasks:
            task.cancel()
        await asyncio.gather(*self.tasks, return_exceptions=True)
        await self.client.close()
        if self.process.returncode is None:
            self.process.terminate()
            await asyncio.wait_for(self.process.wait(), 10)
        self.log.close()
        self.temp.cleanup()

    async def request(self, model, path='/work', **kwargs):
        async with self.client.get(f'{self.base}/upstream/{model}{path}', **kwargs) as response:
            return response.status, await response.text()

    def launch(self, model, path='/work'):
        task = asyncio.create_task(self.request(model, path))
        self.tasks.append(task)
        return task

    def events(self, model=None, kind=None):
        file = self.root / 'events.jsonl'
        values = [json.loads(line) for line in file.read_text().splitlines()] if file.exists() else []
        return [e for e in values if (model is None or e['model'] == model) and (kind is None or e['kind'] == kind)]

    async def wait_event(self, model, kind):
        for _ in range(100):
            if self.events(model, kind):
                return
            await asyncio.sleep(.03)
        self.fail(f'No {model}/{kind} event')

    async def running(self):
        async with self.client.get(self.base + '/running') as response:
            return {m['model'] for m in (await response.json())['running']}

    async def test_compatible_models_stay_and_large_model_evicts_only_what_it_needs(self):
        for model in ['preview', 'summary', 'final']:
            self.assertEqual((await self.request(model))[0], 200)
        self.assertEqual(await self.running(), {'preview', 'summary', 'final'})
        self.assertEqual((await self.request('large'))[0], 200)
        self.assertEqual(await self.running(), {'preview', 'large'})
        self.assertEqual(len(self.events('preview', 'start')), 1)

    async def test_active_transcription_finishes_before_voice_loads(self):
        final = self.launch('final', '/work?delay=.7')
        await self.wait_event('final', 'work-start')
        voice = self.launch('voice')
        await asyncio.sleep(.15)
        self.assertFalse(self.events('voice', 'start'))
        self.assertEqual((await final)[0], 200)
        self.assertEqual((await voice)[0], 200)
        self.assertGreater(self.events('voice', 'start')[0]['time'], self.events('final', 'work-end')[0]['time'])

    async def test_simultaneous_incompatible_cold_loads_do_not_overlap(self):
        a = self.launch('final', '/work?delay=.3')
        b = self.launch('voice', '/work?delay=.3')
        self.assertEqual([r[0] for r in await asyncio.gather(a, b)], [200, 200])
        intervals = [(self.events(m, 'work-start')[0]['time'], self.events(m, 'work-end')[0]['time']) for m in ['final', 'voice']]
        self.assertTrue(intervals[0][1] <= intervals[1][0] or intervals[1][1] <= intervals[0][0])

    async def test_same_model_cold_requests_share_one_process(self):
        results = await asyncio.gather(*(self.launch('final', '/work?delay=.1') for _ in range(5)))
        self.assertEqual([r[0] for r in results], [200] * 5)
        self.assertEqual(len(self.events('final', 'start')), 1)

    async def test_websocket_binary_audio_survives_competing_model(self):
        async with self.client.ws_connect(self.base + '/upstream/preview/ws') as ws:
            await ws.send_bytes(b'audio-pcm')
            self.assertEqual((await ws.receive()).data, b'audio-pcm')
            self.assertEqual((await self.request('large'))[0], 200)
            await ws.send_str('still listening')
            self.assertEqual((await ws.receive()).data, 'still listening')
        self.assertEqual(len(self.events('preview', 'start')), 1)

    async def test_incompatible_websocket_blocks_swap_until_closed(self):
        async with self.client.ws_connect(self.base + '/upstream/voice/ws') as ws:
            await ws.send_str('ready')
            await ws.receive()
            final = self.launch('final')
            await asyncio.sleep(.2)
            self.assertFalse(final.done())
            self.assertFalse(self.events('final', 'start'))
        self.assertEqual((await final)[0], 200)

    async def test_speech_priority_orders_waiters_but_does_not_preempt_running_work(self):
        large = self.launch('large', '/work?delay=.8')
        await self.wait_event('large', 'work-start')
        voice = self.launch('voice')
        await asyncio.sleep(.1)
        final = self.launch('final', '/work?delay=.3')
        self.assertEqual((await large)[0], 200)
        self.assertEqual((await final)[0], 200)
        self.assertEqual((await voice)[0], 200)
        self.assertGreater(self.events('final', 'start')[0]['time'], self.events('large', 'work-end')[0]['time'])
        self.assertLess(self.events('final', 'start')[0]['time'], self.events('voice', 'start')[0]['time'])

    async def test_ready_model_fast_path_can_delay_high_priority_dictation(self):
        first = self.launch('large', '/work?delay=.5')
        await self.wait_event('large', 'work-start')
        final = self.launch('final')
        await asyncio.sleep(.1)
        second = self.launch('large', '/work?delay=.8')
        await first
        self.assertFalse(final.done())
        await second
        self.assertEqual((await final)[0], 200)
        self.assertGreater(self.events('final', 'start')[0]['time'], self.events('large', 'work-end')[-1]['time'])

    async def test_cancelled_queued_request_does_not_load_later(self):
        large = self.launch('large', '/work?delay=.6')
        await self.wait_event('large', 'work-start')
        final = self.launch('final')
        await asyncio.sleep(.1)
        final.cancel()
        await asyncio.gather(final, return_exceptions=True)
        await large
        await asyncio.sleep(.15)
        self.assertFalse(self.events('final', 'start'))

    async def test_single_admission_limit_prevents_resident_model_starvation(self):
        first = self.launch('serial', '/work?delay=.6')
        await self.wait_event('serial', 'work-start')
        final = self.launch('final')
        await asyncio.sleep(.1)
        # Explicit backpressure: caller must retry the rejected background job.
        self.assertEqual((await self.request('serial'))[0], 429)
        self.assertEqual((await first)[0], 200)
        self.assertEqual((await final)[0], 200)
        self.assertEqual(len(self.events('serial', 'work-start')), 1)

    async def test_admin_unload_interrupts_busy_request_and_next_request_recovers(self):
        final = self.launch('final', '/work?delay=5')
        await self.wait_event('final', 'work-start')
        async with self.client.post(self.base + '/api/models/unload/final') as response:
            self.assertEqual(response.status, 200)
        self.assertGreaterEqual((await final)[0], 500)
        self.assertEqual((await self.request('final'))[0], 200)

    async def test_health_probe_does_not_load_an_idle_model(self):
        self.assertEqual((await self.request('final', '/health'))[0], 409)
        self.assertFalse(self.events('final', 'start'))
        self.assertEqual((await self.request('final'))[0], 200)
        self.assertEqual((await self.request('final', '/health'))[0], 200)

    async def test_crashed_backend_restarts_on_next_request(self):
        await self.request('final')
        self.assertGreaterEqual((await self.request('final', '/crash'))[0], 500)
        self.assertEqual((await self.request('final'))[0], 200)
        self.assertEqual(len(self.events('final', 'start')), 2)

    async def test_failed_start_does_not_wedge_scheduler(self):
        flag = self.root / 'final.fail'
        flag.touch()
        self.assertGreaterEqual((await self.request('final'))[0], 500)
        flag.unlink()
        self.assertEqual((await self.request('final'))[0], 200)

    async def test_ttl_does_not_kill_active_request_then_unloads_idle_model(self):
        self.assertEqual((await self.request('voice', '/work?delay=2'))[0], 200)
        for _ in range(80):
            if 'voice' not in await self.running():
                break
            await asyncio.sleep(.1)
        self.assertNotIn('voice', await self.running())


if __name__ == '__main__':
    if '--backend' in sys.argv:
        asyncio.run(backend())
    else:
        unittest.main(verbosity=2)

import base64
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

spec = importlib.util.spec_from_file_location('gateway', Path(__file__).with_name('gateway.py'))
gateway = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gateway)


class RecordingTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=Path.cwd(), prefix='.stt-test-')
        gateway.ROOT = Path(self.directory.name)
        (gateway.ROOT / 'recording').mkdir()
        (gateway.ROOT / 'recording' / 'audio.pcm').touch()
        gateway.sessions.clear()
        gateway.sessions['recording'] = dict(id='recording', owner='alice', project='', status='recording',
            draft='', final='', error='', bytes=0, created=0, vocabulary=[], sequence=0)
        app = web.Application()
        app.router.add_post('/dictation', gateway.action)
        self.client = TestClient(TestServer(app))
        await self.client.start_server()

    async def asyncTearDown(self):
        await self.client.close()
        self.directory.cleanup()

    async def post(self, owner='alice', **body):
        return await self.client.post('/dictation', json=dict(id='recording', **body), headers={'X-STT-Owner': owner})

    async def test_retry_does_not_duplicate_audio(self):
        body = dict(action='append', sequence=0, audio=base64.b64encode(b'\x01\x00' * 80).decode())
        self.assertEqual((await self.post(**body)).status, 200)
        self.assertEqual((await self.post(**body)).status, 200)
        self.assertEqual((gateway.ROOT / 'recording' / 'audio.pcm').stat().st_size, 160)
        self.assertEqual(json.loads((gateway.ROOT / 'recording' / 'state.json').read_text())['sequence'], 1)

    async def test_other_subject_cannot_read_or_cancel(self):
        self.assertEqual((await self.post(owner='bob', action='status')).status, 404)
        self.assertEqual((await self.post(owner='bob', action='cancel')).status, 404)
        self.assertEqual(gateway.sessions['recording']['status'], 'recording')

    async def test_out_of_order_and_invalid_pcm_are_rejected(self):
        self.assertEqual((await self.post(action='append', sequence=2, audio='AAAA')).status, 409)
        self.assertEqual((await self.post(action='append', sequence=0, audio='!')).status, 400)
        self.assertEqual((await self.post(action='append', sequence=0, audio='AA==')).status, 413)
        self.assertEqual((gateway.ROOT / 'recording' / 'audio.pcm').stat().st_size, 0)

    async def test_empty_recording_cannot_finalize(self):
        self.assertEqual((await self.post(action='finish')).status, 400)


if __name__ == '__main__':
    unittest.main()

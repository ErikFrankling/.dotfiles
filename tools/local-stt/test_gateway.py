import base64
import importlib.util
import json
import tempfile
import unittest
from unittest.mock import AsyncMock, MagicMock, patch
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
        app['client'] = None
        patcher = patch.object(gateway, 'ensure_preview')
        patcher.start()
        self.addCleanup(patcher.stop)
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

    async def test_background_failure_preserves_live_feedback_and_backs_off(self):
        state = gateway.sessions['recording']
        state['draft'] = 'Keep listening.'
        with patch.object(gateway, 'refine_available', AsyncMock(side_effect=RuntimeError('GPU guard'))):
            await gateway.refine_background(state, None)
        self.assertEqual(state['status'], 'recording')
        self.assertEqual(state['error'], '')
        self.assertEqual(state['draft'], 'Keep listening.')
        self.assertEqual(state['background_error'], 'RuntimeError')
        self.assertGreater(state['refine_after'], gateway.time.time())



    def transcriber(self, *texts):
        response = MagicMock()
        response.json = AsyncMock(side_effect=[{'text': text} for text in texts])
        client = MagicMock()
        client.post.return_value.__aenter__ = AsyncMock(return_value=response)
        client.post.return_value.__aexit__ = AsyncMock(return_value=False)
        return client

    def record(self, seconds=1, **fields):
        state = gateway.sessions['recording']
        pcm = b'\x01\x00' * 16000 * seconds
        (gateway.ROOT / 'recording' / 'audio.pcm').write_bytes(pcm)
        state.update(bytes=len(pcm), **fields)
        return state, pcm

    async def test_finalization_outlasts_worker_failures(self):
        state, pcm = self.record(draft='Keep my first draft.')
        failures = [RuntimeError('not enough free GPU memory'), RuntimeError('final worker exited during startup'), None]
        with patch.object(gateway, 'start_worker', AsyncMock(side_effect=failures)), \
             patch.object(gateway, 'stop_worker', AsyncMock()) as stop, \
             patch.object(gateway.asyncio, 'sleep', AsyncMock()) as sleep, \
             patch.object(gateway, 'project_context', return_value=('', [])):
            await gateway.finalize(state, self.transcriber('Full quality.'))
        self.assertEqual(state['status'], 'complete')
        self.assertEqual(state['final'], 'Full quality.')
        self.assertEqual(state['error'], '')
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [2, 4])
        stop.assert_awaited_once_with('final')
        self.assertEqual((gateway.ROOT / 'recording' / 'audio.pcm').read_bytes(), pcm)

    async def test_interrupted_finalization_resumes_after_restart(self):
        state, _ = self.record()
        with patch.object(gateway, 'start_worker', AsyncMock(side_effect=gateway.asyncio.CancelledError)):
            with self.assertRaises(gateway.asyncio.CancelledError):
                await gateway.finalize(state, None)
        saved = json.loads((gateway.ROOT / 'recording' / 'state.json').read_text())
        self.assertEqual(saved['status'], 'finalizing')

    async def test_silence_completes_without_text_instead_of_retrying_forever(self):
        state, _ = self.record()
        with patch.object(gateway, 'start_worker', AsyncMock()), \
             patch.object(gateway, 'project_context', return_value=('', [])):
            await gateway.finalize(state, self.transcriber('[silence]', ''))
        self.assertEqual(state['status'], 'complete')
        self.assertEqual(state['final'], '')

    async def test_truncated_long_transcript_is_redone_in_shorter_windows(self):
        draft = ' '.join(['word'] * 400)
        state, _ = self.record(seconds=200, draft=draft)
        with patch.object(gateway, 'start_worker', AsyncMock()), \
             patch.object(gateway, 'project_context', return_value=('', [])):
            await gateway.finalize(state, self.transcriber('Only the start.', draft[:1000], draft[1000:]))
        self.assertEqual(state['final'], draft)
        self.assertEqual(len(state['quality_segments']), 2)

    async def test_start_is_immediate_idempotent_and_allowed_during_finalization(self):
        gateway.sessions['recording']['status'] = 'finalizing'
        identifier = '11111111-2222-3333-4444-555555555555'
        with patch.object(gateway, 'ensure_preview') as preview, \
             patch.object(gateway, 'warm', AsyncMock()):
            first = await self.client.post('/dictation', json=dict(action='start', id=identifier), headers={'X-STT-Owner': 'alice'})
            again = await self.client.post('/dictation', json=dict(action='start', id=identifier), headers={'X-STT-Owner': 'alice'})
            other = await self.client.post('/dictation', json=dict(action='start', id=identifier), headers={'X-STT-Owner': 'bob'})
            bad = await self.client.post('/dictation', json=dict(action='start', id='../etc'), headers={'X-STT-Owner': 'alice'})
        self.assertEqual([first.status, again.status, other.status, bad.status], [200, 200, 409, 400])
        self.assertEqual((await first.json())['status'], 'recording')
        preview.assert_called_once()
        self.assertTrue((gateway.ROOT / identifier / 'audio.pcm').exists())

    async def test_abandoned_recording_does_not_hold_the_gpu(self):
        state = gateway.sessions['recording']
        state['touched'] = gateway.time.time()
        self.assertTrue(gateway.busy())
        state['touched'] -= gateway.ACTIVE_SECONDS + 1
        self.assertFalse(gateway.busy())

    async def test_background_completion_does_not_skip_the_quality_pass(self):
        state = gateway.sessions['recording']
        state.update(draft='Keep my first draft.', final='Provisional wording.', bytes=32000,
                     refined_bytes=32000)
        (gateway.ROOT / 'recording' / 'audio.pcm').write_bytes(b'\x01\x00' * 16000)
        response = MagicMock()
        response.json = AsyncMock(return_value={'text': 'Full-context wording.'})
        client = MagicMock()
        client.post.return_value.__aenter__ = AsyncMock(return_value=response)
        client.post.return_value.__aexit__ = AsyncMock(return_value=False)
        with patch.object(gateway, 'start_worker', AsyncMock()), \
             patch.object(gateway, 'project_context', return_value=('Project context', [])):
            await gateway.finalize(state, client)
        self.assertEqual(state['status'], 'complete')
        self.assertEqual(state['final'], 'Full-context wording.')
        self.assertEqual(state['draft'], 'Keep my first draft.')
        self.assertEqual(state['quality_bytes'], state['bytes'])
        restored = json.loads((gateway.ROOT / 'recording' / 'state.json').read_text())
        self.assertEqual(restored['quality_bytes'], state['bytes'])
        self.assertEqual(restored['quality_text'], state['final'])
        self.assertEqual(restored['quality_segments'][-1]['end'], state['bytes'])


class ChunkTests(unittest.TestCase):
    def test_waits_for_lookahead_and_keeps_final_tail(self):
        self.assertIsNone(gateway.chunk_end(b'\x00\x00' * 16000 * 30, 0))
        self.assertEqual(gateway.chunk_end(b'\x00\x00' * 16000 * 12, 0, True), 384000)

    def test_splits_inside_pause_not_the_next_word(self):
        pcm = b'\xff\x1f' * 16000 * 31
        start, end = 25 * 32000, 26 * 32000
        pcm = pcm[:start] + b'\x00' * (end - start) + pcm[end:]
        split = gateway.chunk_end(pcm, 0)
        self.assertGreater(split, start)
        self.assertLess(split, end)
        self.assertEqual(split % 2, 0)

    def test_noise_floor_does_not_force_overlap_at_a_real_pause(self):
        pcm = (700).to_bytes(2, 'little') * 16000 * 31
        offset = 25 * 32000
        self.assertEqual(gateway.chunk_start(pcm, offset, len(pcm)), offset)

    def test_overlap_is_removed_without_removing_new_speech(self):
        self.assertEqual(gateway.merge_transcripts('Deploy the NaiaClaw server.', 'the naiaclaw server, then run tests.'), 'Deploy the NaiaClaw server. then run tests.')
        self.assertEqual(gateway.merge_transcripts('Really?', 'Why would you do that?'), 'Really? Why would you do that?')


if __name__ == '__main__':
    unittest.main()

import array
import http.server
import socket
import tempfile
import threading
import time
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

import speak


def item(**fields):
    base = dict(id="a", priority="normal", created=0.0, expires=1000.0, status="ready")
    base.update(fields)
    return base


class Gate(unittest.TestCase):
    def test_plays_when_free(self):
        self.assertEqual(speak.gate(item(), 10, False, 0, False, False)[0], "play")

    def test_waits_while_dictating_even_urgent(self):
        self.assertEqual(speak.gate(item(priority="urgent"), 10, True, 0, False, False),
                         ("wait", "Erik is dictating"))

    def test_waits_right_after_dictation(self):
        self.assertEqual(speak.gate(item(), 10, False, 9.5, False, False)[0], "wait")

    def test_waits_for_read_aloud(self):
        self.assertEqual(speak.gate(item(), 10, False, 0, True, False)[1], "a read-aloud is playing")

    def test_away_rules(self):
        self.assertEqual(speak.gate(item(priority="low"), 10, False, 0, False, True)[0], "drop")
        self.assertEqual(speak.gate(item(), 10, False, 0, False, True)[0], "wait")
        self.assertEqual(speak.gate(item(priority="urgent"), 10, False, 0, False, True)[0], "play")

    def test_next_question_waits_for_his_answer(self):
        self.assertEqual(speak.gate(item(), 10, False, 0, False, False, True)[0], "wait")
        self.assertEqual(speak.gate(item(reply=False), 10, False, 0, False, False, True)[0], "play")
        self.assertEqual(speak.gate(item(priority="urgent"), 10, False, 0, False, False, True)[0], "play")

    def test_expired(self):
        self.assertEqual(speak.gate(item(), 1000, True, 0, False, False)[0], "drop")


class Queue(unittest.TestCase):
    def test_urgent_first_then_oldest(self):
        items = [item(id="old", created=1), item(id="new", created=2),
                 item(id="urgent", created=3, priority="urgent"), item(id="done", status="spoken")]
        self.assertEqual(speak.next_item(items)["id"], "urgent")
        self.assertEqual(speak.next_item(items[:2])["id"], "old")
        self.assertIsNone(speak.next_item(items[3:]))


class Text(unittest.TestCase):
    def test_speakable_drops_markdown(self):
        self.assertEqual(speak.speakable("# Done\n- built `pc`\n```\ncode\n```\n[link](http://x)"),
                         "Done.\nbuilt pc.\nlink.")

    def test_sentences(self):
        self.assertEqual(speak.sentences("Hi there. It works! Try it?\nok"),
                         ["Hi there.", "It works!", "Try it?", "ok"])


class Audio(unittest.TestCase):
    def test_wav_round_trip_and_polish(self):
        samples = array.array("h", [0] * 2400 + [5000] * 2400 + [0] * 2400)
        rate, back = speak.read_wav(speak.wav_bytes(samples, 24000))
        self.assertEqual((rate, list(back)), (24000, list(samples)))
        polished = speak.polish(back, rate)
        # 0.1 s speech + 2 x 30 ms kept + 280 ms pause
        self.assertEqual(len(polished), 2400 + 2 * 720 + 6720)

    def test_streamed_wav_with_bogus_size(self):
        wav = bytearray(speak.wav_bytes(array.array("h", [1, 2, 3]), 16000))
        wav[40:44] = (0xFFFFFFFF).to_bytes(4, "little")
        self.assertEqual(list(speak.read_wav(bytes(wav))[1]), [1, 2, 3])


class Phone(unittest.TestCase):
    def test_only_the_thread_in_voice_mode(self):
        here = {"present": True, "threadId": "personal-agent"}
        self.assertTrue(speak.phone_has(here, "personal-agent"))
        self.assertFalse(speak.phone_has(here, "other"))
        self.assertFalse(speak.phone_has({"present": False, "threadId": "personal-agent"}, "personal-agent"))
        self.assertFalse(speak.phone_has({}, "personal-agent"))


class Mode(unittest.TestCase):
    def test_only_conversation_opens_voice_input(self):
        self.assertTrue(speak.opens_reply("conversation"))
        self.assertTrue(speak.opens_reply("conversation", True))
        self.assertFalse(speak.opens_reply("conversation", False))
        # the mode wins over the caller
        self.assertFalse(speak.opens_reply("voice-out", True))
        self.assertFalse(speak.opens_reply("silent", True))

    def test_cycle_follows_the_toggle_order(self):
        self.assertEqual(speak.next_mode("conversation"), "voice-out")
        self.assertEqual(speak.next_mode("voice-out"), "silent")
        self.assertEqual(speak.next_mode("silent"), "conversation")
        self.assertEqual(speak.next_mode("bogus"), speak.DEFAULT_MODE)

    def test_default_is_voice_out_only(self):
        self.assertEqual(speak.DEFAULT_MODE, "voice-out")
        self.assertEqual(speak.MODES["voice-out"], "Voice out only")


class Daemon(unittest.TestCase):
    """The real queue, worker and HTTP handler with the audio and the T3 app faked:
    what a speak call does in each of Erik's modes."""

    def setUp(self):
        self.state = tempfile.TemporaryDirectory()
        self.addCleanup(self.state.cleanup)
        root = Path(self.state.name)
        self.patches = [
            mock.patch.object(speak, "STATE", root),
            mock.patch.object(speak, "MODE_FILE", root / "mode"),
            mock.patch.object(speak, "HOST", socket.gethostname()),
            mock.patch.object(speak, "generate", self.fake_generate),
            mock.patch.object(speak, "play", lambda _item: True),
            mock.patch.object(speak, "open_reply_window", self.fake_reply_window),
            mock.patch.object(speak, "dictating", lambda: False),
            mock.patch.object(speak, "reading_aloud", lambda: False),
            mock.patch.object(speak, "away", lambda: False),
            mock.patch.object(speak, "answering", lambda: False),
            mock.patch.object(speak, "default_sink", lambda: "test sink"),
            mock.patch.object(speak, "phone_presence", lambda: {}),
            mock.patch.object(speak, "POLL_SECONDS", 0.05),
        ]
        for patch in self.patches:
            patch.start()
            self.addCleanup(patch.stop)
        self.reply_windows = []
        speak.items.clear()
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), speak.Handler)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        patch = mock.patch.object(speak, "DAEMON", f"http://127.0.0.1:{server.server_address[1]}")
        patch.start()
        self.addCleanup(patch.stop)
        shutdown = threading.Event()
        patch = mock.patch.object(speak, "shutdown", shutdown)
        patch.start()
        self.addCleanup(patch.stop)
        worker = threading.Thread(target=speak.worker, daemon=True)
        worker.start()
        self.addCleanup(worker.join)
        self.addCleanup(speak.wake.set)
        self.addCleanup(shutdown.set)

    def fake_generate(self, item):
        with speak.lock:
            item.update(status="ready", voice="fake", audio="x.wav", seconds=1.0,
                        spoken_text=item["text"])
        speak.wake.set()

    def fake_reply_window(self, item):
        self.reply_windows.append(item["id"])
        return "opened"

    def set_mode(self, mode):
        return speak.http_json(f"{speak.DAEMON}/mode", {"mode": mode})

    def say(self, **args):
        is_error, result = speak.call_tool("speak", {"text": "Hello Erik.", **args})
        self.assertFalse(is_error, result)
        # the reply window is asked for right after the status turns spoken
        deadline = time.time() + 5
        while time.time() < deadline and "reply_window" not in speak.items[result["id"]]:
            if result["status"] == "dropped":
                break
            time.sleep(0.02)
        return result

    def test_voice_out_only_ignores_reply_true(self):
        self.assertEqual(speak.http_json(f"{speak.DAEMON}/mode")["mode"], "voice-out")
        result = self.say(reply=True)
        self.assertEqual((result["status"], result["mode"]), ("spoken", "voice-out"))
        self.assertEqual(self.reply_windows, [])
        self.assertEqual(speak.items[result["id"]]["reply_window"], "off")

    def test_conversation_opens_the_reply_window(self):
        self.set_mode("conversation")
        result = self.say(reply=True)
        self.assertEqual((result["status"], result["mode"]), ("spoken", "conversation"))
        self.assertEqual(self.reply_windows, [result["id"]])

    def test_conversation_still_honours_reply_false(self):
        self.set_mode("conversation")
        self.say(reply=False)
        self.assertEqual(self.reply_windows, [])

    def test_silent_says_nothing_and_opens_nothing(self):
        self.set_mode("silent")
        result = self.say(reply=True)
        self.assertEqual((result["status"], result["mode"]), ("dropped", "silent"))
        self.assertIn("Silent", result["reason"])
        self.assertEqual(self.reply_windows, [])

    def test_a_flip_applies_to_a_message_already_queued(self):
        self.set_mode("conversation")
        with mock.patch.object(speak, "play", lambda _item: self.set_mode("voice-out") and True):
            result = self.say(reply=True)
        self.assertEqual(result["status"], "spoken")
        self.assertEqual(self.reply_windows, [])

    def test_the_phone_is_told_not_to_listen_in_voice_out_only(self):
        sent = []
        presence = {"present": True, "threadId": speak.REPLY_THREAD}

        real_http_json = speak.http_json

        def fake_http(url, body=None, timeout=5):
            if url.endswith("/api/voice-presence/say"):
                sent.append(body)
                return {"id": body["id"], "status": "queued"}
            return real_http_json(url, body, timeout)

        with mock.patch.object(speak, "phone_presence", lambda: presence), \
                mock.patch.object(speak, "T3_URL", "http://t3.test"), \
                mock.patch.object(speak, "follow_phone", lambda _item: None), \
                mock.patch.object(speak, "http_json", fake_http):
            speak.submit({"text": "Hi.", "reply": True})
            deadline = time.time() + 5
            while not sent and time.time() < deadline:
                time.sleep(0.02)
        self.assertEqual(len(sent), 1)
        self.assertIs(sent[0]["listen"], False)

    def test_mode_is_stored_and_survives_a_restart(self):
        self.assertEqual(self.set_mode("conversation")["label"], "Conversation")
        self.assertEqual(speak.read_mode(), "conversation")
        self.assertEqual((speak.STATE / "mode").read_text().strip(), "conversation")
        with self.assertRaises(urllib.error.HTTPError):
            self.set_mode("loud")
        self.assertEqual(speak.read_mode(), "conversation")

    def test_mcp_tells_agents_the_mode(self):
        self.assertIn("'Voice out only' (voice-out)", speak.tool_definition()["description"])
        self.set_mode("silent")
        self.assertIn("'Silent' (silent)", speak.tool_definition()["description"])
        self.assertIn("WINS over `reply`", speak.TOOL["description"])
        status = speak.call_tool("speak_status", {"id": self.say()["id"]})[1]
        self.assertEqual(status["mode"], "silent")


if __name__ == "__main__":
    unittest.main()

import array
import unittest

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


if __name__ == "__main__":
    unittest.main()

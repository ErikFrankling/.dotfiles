"""Tests for guards around local inference; no model or GPU is loaded."""
import argparse
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import wave

spec=importlib.util.spec_from_file_location('local_stack',Path(__file__).with_name('local_stack.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class Guards(unittest.TestCase):
    def setUp(self):
        root=Path(__file__).parent/'results';root.mkdir(exist_ok=True)
        self.tmp=tempfile.TemporaryDirectory(dir=root)
        self.root=Path(self.tmp.name)
    def tearDown(self): self.tmp.cleanup()
    def test_vocab_case_dedup_and_validation(self):
        p=self.root/'names';p.write_text('naiaclaw\nNaiaClaw\nClaude Code\n')
        self.assertEqual(m.vocabulary(p),['naiaclaw','Claude Code'])
        p.write_text('bad"name');self.assertRaises(ValueError,m.vocabulary,p)
    def test_plain_rejects_context_before_launch(self):
        (self.root/'model.gguf').write_bytes(b'test')
        context=self.root/'context';context.write_text('project')
        args=argparse.Namespace(model_dir=self.root,output=self.root/'out.json',vocabulary=None,context=context,strategy='plain')
        with patch.object(m.subprocess,'Popen') as launch:
            self.assertRaises(ValueError,m.transcribe,args)
            launch.assert_not_called()
    def test_existing_result_is_not_overwritten(self):
        (self.root/'model.gguf').write_bytes(b'test')
        out=self.root/'out.json';out.write_text('existing')
        args=argparse.Namespace(model_dir=self.root,output=out)
        self.assertRaises(ValueError,m.transcribe,args)
        self.assertEqual(out.read_text(),'existing')
    def test_busy_gpu_prevents_model_launch(self):
        (self.root/'model.gguf').write_bytes(b'test')
        audio=self.root/'audio.wav'
        with wave.open(str(audio),'wb') as w:
            w.setparams((1,2,16000,0,'NONE','not compressed'));w.writeframes(b'\0\0'*16000)
        args=argparse.Namespace(model_dir=self.root,output=self.root/'out.json',vocabulary=None,context=None,strategy='plain',audio=audio,binary='/not/invoked',max_tokens=256,beams=1)
        with patch.dict(m.os.environ,{'XDG_RUNTIME_DIR':str(self.root)}),patch.object(m,'memory',return_value={'vram_bytes':9*m.GIB,'available_ram_bytes':20*m.GIB}),patch.object(m.subprocess,'Popen') as launch:
            self.assertRaises(RuntimeError,m.transcribe,args)
            launch.assert_not_called()

if __name__=='__main__': unittest.main()

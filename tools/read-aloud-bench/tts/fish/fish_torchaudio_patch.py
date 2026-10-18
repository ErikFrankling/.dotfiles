# torchaudio 2.9 routes load() through torchcodec, which the ROCm image lacks.
# Reference clips are plain WAV, so soundfile is enough.
import soundfile as sf
import torch
import torchaudio


def _load(path, *args, **kwargs):
    data, sr = sf.read(path, dtype="float32", always_2d=True)
    return torch.from_numpy(data.T.copy()), sr


torchaudio.load = _load

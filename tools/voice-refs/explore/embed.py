"""Exploration: alternative audio embeddings for the source segments (throwaway analysis, not pipeline code).

  uv run python explore/embed.py cache          # cut every segment once to 16 kHz, cached
  uv run python explore/embed.py wavlm|emotion|gemma
"""

import json
import os
import sys

os.environ.setdefault("HF_HOME", "/internalmedia/voice-refs-work/hf")

import numpy as np

from voicerefs import audio
from voicerefs.config import SOURCE_BOOK, WORK_DIR

SRC = WORK_DIR / "source"
CACHE = SRC / "segaudio16k.npz"
RATE = 16000
DEVICE = "cuda:1"  # torch is pinned to cu126 wheels: phanteks has driver 555 (CUDA 12.5)


def cache() -> None:
    segments = json.loads((SRC / "segments.json").read_text())
    starts = sorted(int(p.stem) for p in (SRC / "pieces").glob("*.json"))
    clips, loaded = [], {}
    for seg in segments:
        piece = max(s for s in starts if s <= seg["start"])
        if piece not in loaded:
            loaded.clear()
            wav = audio.extract(SOURCE_BOOK, piece, 630, WORK_DIR / "features-tmp" / f"{piece}.wav", rate=RATE)
            loaded[piece] = audio.read(wav)[0].astype(np.float32)
            wav.unlink()
        x = loaded[piece][int((seg["start"] - piece) * RATE): int((seg["end"] - piece) * RATE)]
        clips.append(x if len(x) >= RATE // 2 else np.pad(x, (0, RATE // 2 - len(x))))
    lengths = np.array([len(c) for c in clips])
    np.savez(CACHE, flat=np.concatenate(clips).astype(np.float16), lengths=lengths)
    print("cached", len(clips))


def clips():
    d = np.load(CACHE)
    flat, ends = d["flat"].astype(np.float32), np.cumsum(d["lengths"])
    return [flat[a:b] for a, b in zip(np.r_[0, ends[:-1]], ends)]


def run(name, fn) -> None:
    import torch

    out = []
    with torch.no_grad():
        for n, x in enumerate(clips()):
            out.append(fn(x))
            if n % 500 == 0:
                print(name, n, flush=True)
    np.save(SRC / f"emb-{name}.npy", np.array(out))
    print("wrote", name, np.array(out).shape)


def wavlm() -> None:
    import torch
    from transformers import AutoFeatureExtractor, WavLMModel

    fe = AutoFeatureExtractor.from_pretrained("microsoft/wavlm-base-plus")
    m = WavLMModel.from_pretrained("microsoft/wavlm-base-plus").eval().to(DEVICE)

    def fn(x):
        inp = fe(x, sampling_rate=RATE, return_tensors="pt").to(DEVICE)
        hs = m(**inp, output_hidden_states=True).hidden_states
        # mean over time of layers 3-9: the middle layers carry most speaker/style information
        return torch.stack([h.mean(1)[0] for h in hs[3:10]]).mean(0).cpu().numpy()

    run("wavlm", fn)


def emotion() -> None:
    import torch
    import torch.nn as nn
    from transformers import Wav2Vec2Processor
    from transformers.models.wav2vec2.modeling_wav2vec2 import Wav2Vec2Model, Wav2Vec2PreTrainedModel

    class Head(nn.Module):
        def __init__(self, config):
            super().__init__()
            self.dense = nn.Linear(config.hidden_size, config.hidden_size)
            self.dropout = nn.Dropout(config.final_dropout)
            self.out_proj = nn.Linear(config.hidden_size, config.num_labels)

        def forward(self, x):
            return self.out_proj(self.dropout(torch.tanh(self.dense(self.dropout(x)))))

    class EmotionModel(Wav2Vec2PreTrainedModel):  # per the model card
        def __init__(self, config):
            super().__init__(config)
            self.wav2vec2 = Wav2Vec2Model(config)
            self.classifier = Head(config)
            self.post_init()

        def forward(self, input_values):
            hidden = self.wav2vec2(input_values)[0].mean(dim=1)
            return hidden, self.classifier(hidden)

    rid = "audeering/wav2vec2-large-robust-12-ft-emotion-msp-dim"
    proc = Wav2Vec2Processor.from_pretrained(rid)
    m = EmotionModel.from_pretrained(rid).eval().to(DEVICE)

    def fn(x):
        iv = proc(x, sampling_rate=RATE, return_tensors="pt").input_values.to(DEVICE)
        hidden, adv = m(iv)
        return np.concatenate([adv[0].cpu().numpy(), hidden[0].cpu().numpy()])  # arousal, dominance, valence, then 1024

    run("emotion", fn)


def egemma() -> None:
    from voicerefs.clusters import egemma_encoder

    run("egemma", egemma_encoder(DEVICE))


if __name__ == "__main__":
    {"cache": cache, "wavlm": wavlm, "emotion": emotion, "egemma": egemma}[sys.argv[1]]()

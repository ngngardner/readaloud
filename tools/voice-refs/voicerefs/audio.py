"""WAV extraction, reading/writing and loudness levelling."""

import subprocess
from pathlib import Path

import numpy as np
import soundfile as sf

from .config import SAMPLE_RATE


def extract(src: Path, start_s: float, dur_s: float, out: Path, rate: int = SAMPLE_RATE) -> Path:
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-ss", f"{start_s:.3f}", "-t", f"{dur_s:.3f}", "-i", str(src),
         "-ac", "1", "-ar", str(rate), "-c:a", "pcm_s16le", str(out)],
        check=True,
    )
    return out


def read(path: Path) -> tuple[np.ndarray, int]:
    samples, rate = sf.read(str(path), dtype="float64", always_2d=False)
    if samples.ndim > 1:
        samples = samples.mean(axis=1)
    return samples, rate


def write(path: Path, samples: np.ndarray, rate: int = SAMPLE_RATE) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(path), samples, rate, subtype="PCM_16")
    return path


def rms_dbfs(samples: np.ndarray) -> float:
    rms = float(np.sqrt(np.mean(np.square(samples)))) if len(samples) else 0.0
    return 20 * np.log10(rms) if rms > 0 else -120.0


def level(samples: np.ndarray, target_dbfs: float = -20.0) -> np.ndarray:
    current = rms_dbfs(samples)
    if current <= -120.0:
        return samples
    gain = 10 ** ((target_dbfs - current) / 20)
    return np.clip(samples * gain, -1.0, 1.0)

#!/usr/bin/env python3
"""生成适合当前FPGA波表振荡器的合成钢琴和合成提琴波表。"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
import wave

import numpy as np


DEFAULT_FRAME_COUNT = 256
DEFAULT_FRAME_SIZE = 2048
MAX_HARMONICS = 64
OUTPUT_SAMPLE_RATE = 44100


def smoothstep(value: float) -> float:
    return value * value * (3.0 - 2.0 * value)


def render_harmonic_frame(
    frame_size: int,
    amplitudes: np.ndarray,
    phases: np.ndarray,
    target_rms: float,
) -> np.ndarray:
    """用固定相位的整数次谐波生成一个无周期边界跳变的单周期波形。"""
    phase_axis = 2.0 * math.pi * np.arange(frame_size, dtype=np.float64) / frame_size
    harmonic_numbers = np.arange(1, len(amplitudes) + 1, dtype=np.float64)
    waveform = np.sum(
        amplitudes[:, None]
        * np.sin(harmonic_numbers[:, None] * phase_axis + phases[:, None]),
        axis=0,
    )
    waveform -= np.mean(waveform)

    rms = float(np.sqrt(np.mean(waveform * waveform)))
    if rms > 0.0:
        waveform *= target_rms / rms
    peak = float(np.max(np.abs(waveform)))
    if peak > 0.95:
        waveform *= 0.95 / peak
    return waveform


def piano_amplitudes(progress: float, harmonic_count: int) -> np.ndarray:
    """从明亮琴槌起音逐渐过渡到柔和琴弦主体。"""
    n = np.arange(1, harmonic_count + 1, dtype=np.float64)
    transition = smoothstep(progress)

    # 钢琴高次谐波在发音后衰减明显快于基频。WT Position从0向127移动时，
    # 指数阻尼逐渐增强，可由两个独立ADSR分别选取起音帧和主体帧。
    spectral_slope = 1.02 + 0.48 * transition
    high_damping = np.exp(-(0.010 + 0.060 * transition) * (n - 1.0))
    hammer_band = 1.0 + (1.0 - transition) * 0.85 * np.exp(
        -0.5 * ((n - 11.0) / 7.0) ** 2
    )
    string_resonances = (
        1.0
        + 0.32 * np.exp(-0.5 * ((n - 2.0) / 0.55) ** 2)
        + 0.22 * np.exp(-0.5 * ((n - 3.0) / 0.70) ** 2)
        + 0.12 * np.exp(-0.5 * ((n - 5.0) / 1.00) ** 2)
    )
    return hammer_band * string_resonances * high_damping / (n**spectral_slope)


def violin_amplitudes(progress: float, harmonic_count: int) -> np.ndarray:
    """从柔和弓弦逐渐过渡到明亮、带弓毛摩擦感的音色。"""
    n = np.arange(1, harmonic_count + 1, dtype=np.float64)
    transition = smoothstep(progress)

    spectral_slope = 1.62 - 0.62 * transition
    high_damping = np.exp(-(0.030 - 0.017 * transition) * (n - 1.0))
    formants = (
        1.0
        + (0.38 + 0.20 * transition)
        * np.exp(-0.5 * ((n - 5.0) / 2.0) ** 2)
        + (0.20 + 0.38 * transition)
        * np.exp(-0.5 * ((n - 13.0) / 4.0) ** 2)
        + 0.20 * transition * np.exp(-0.5 * ((n - 27.0) / 7.0) ** 2)
    )
    even_odd_balance = np.where((n.astype(np.int64) & 1) == 0, 0.82, 1.0)
    return formants * even_odd_balance * high_damping / (n**spectral_slope)


def build_wavetable(
    instrument: str,
    frame_count: int,
    frame_size: int,
) -> np.ndarray:
    harmonic_count = min(MAX_HARMONICS, frame_size // 2 - 1)
    harmonic_numbers = np.arange(1, harmonic_count + 1, dtype=np.float64)

    if instrument == "piano":
        phases = -math.pi / 2.0 + 0.31 * np.sin(harmonic_numbers * 1.618)
        amplitude_builder = piano_amplitudes
        target_rms = 0.235
    elif instrument == "violin":
        phases = -math.pi / 2.0 + 0.18 * np.sin(harmonic_numbers * 0.73)
        amplitude_builder = violin_amplitudes
        target_rms = 0.245
    else:
        raise ValueError(f"未知乐器类型：{instrument}")

    frames = []
    for frame_index in range(frame_count):
        progress = frame_index / max(1, frame_count - 1)
        amplitudes = amplitude_builder(progress, harmonic_count)
        frames.append(
            render_harmonic_frame(frame_size, amplitudes, phases, target_rms)
        )

    table = np.stack(frames)
    return np.clip(np.rint(table * 32767.0), -32768, 32767).astype("<i2")


def write_pcm16_wav(path: Path, table: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(OUTPUT_SAMPLE_RATE)
        wav_file.writeframes(table.reshape(-1).tobytes())


def spectral_centroid_bins(frame: np.ndarray) -> float:
    spectrum = np.abs(np.fft.rfft(frame.astype(np.float64)))
    bins = np.arange(len(spectrum), dtype=np.float64)
    magnitude_sum = float(np.sum(spectrum))
    return float(np.sum(bins * spectrum) / magnitude_sum)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="生成256帧Serum格式的合成钢琴和合成提琴波表"
    )
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--frame-count", type=int, default=DEFAULT_FRAME_COUNT)
    parser.add_argument("--frame-size", type=int, default=DEFAULT_FRAME_SIZE)
    args = parser.parse_args()

    if args.frame_count < 2:
        parser.error("frame-count必须至少为2")
    if args.frame_size < 256 or args.frame_size % 2:
        parser.error("frame-size必须是至少256的偶数")

    outputs = {
        "piano": args.output_dir / "Synthetic_Piano.wav",
        "violin": args.output_dir / "Synthetic_Violin.wav",
    }
    for instrument, output_path in outputs.items():
        table = build_wavetable(instrument, args.frame_count, args.frame_size)
        write_pcm16_wav(output_path, table)
        first_centroid = spectral_centroid_bins(table[0])
        last_centroid = spectral_centroid_bins(table[-1])
        print(
            f"{instrument}: {output_path}，{args.frame_count}帧×{args.frame_size}点，"
            f"频谱重心 {first_centroid:.2f} -> {last_centroid:.2f} bins"
        )


if __name__ == "__main__":
    main()

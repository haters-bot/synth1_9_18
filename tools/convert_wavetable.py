#!/usr/bin/env python3
"""把Serum/Xfer格式WAV波表转换为FPGA ROM初始化文件。"""

from __future__ import annotations

import argparse
from pathlib import Path
import wave

import numpy as np


def read_pcm16_mono(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as wav_file:
        if wav_file.getnchannels() != 1:
            raise ValueError("输入波表必须是单声道")
        if wav_file.getsampwidth() != 2:
            raise ValueError("输入波表必须是16位PCM")
        if wav_file.getcomptype() != "NONE":
            raise ValueError("输入波表不能使用压缩编码")
        return np.frombuffer(
            wav_file.readframes(wav_file.getnframes()), dtype="<i2"
        ).astype(np.float64)


def fourier_resample(frame: np.ndarray, target_size: int) -> np.ndarray:
    """截去目标Nyquist以上的谐波，再把一个周期缩短到目标点数。"""
    spectrum = np.fft.rfft(frame)
    target_spectrum = np.zeros(target_size // 2 + 1, dtype=np.complex128)
    copied_bins = min(len(spectrum), len(target_spectrum))
    target_spectrum[:copied_bins] = spectrum[:copied_bins]

    if target_size % 2 == 0:
        target_spectrum[-1] = 0

    result = np.fft.irfft(target_spectrum, n=target_size)
    result *= target_size / len(frame)
    return np.clip(np.rint(result), -32768, 32767).astype(np.int16)


def convert(
    input_path: Path,
    output_path: Path,
    source_frame_size: int,
    target_frame_count: int,
    target_frame_size: int,
) -> list[int]:
    samples = read_pcm16_mono(input_path)
    if len(samples) % source_frame_size != 0:
        raise ValueError(
            f"总采样点{len(samples)}不能被源帧长{source_frame_size}整除"
        )

    source_frames = samples.reshape(-1, source_frame_size)
    if len(source_frames) < target_frame_count:
        raise ValueError("源波表帧数少于目标帧数")

    selected_indices = np.rint(
        np.linspace(0, len(source_frames) - 1, target_frame_count)
    ).astype(int)
    converted = np.stack(
        [
            fourier_resample(source_frames[index], target_frame_size)
            for index in selected_indices
        ]
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="ascii", newline="\n") as output_file:
        for sample in converted.reshape(-1):
            output_file.write(f"{int(sample) & 0xFFFF:04X}\n")

    return selected_indices.tolist()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--source-frame-size", type=int, default=2048)
    parser.add_argument("--target-frame-count", type=int, default=16)
    parser.add_argument("--target-frame-size", type=int, default=256)
    args = parser.parse_args()

    selected = convert(
        args.input,
        args.output,
        args.source_frame_size,
        args.target_frame_count,
        args.target_frame_size,
    )
    print("selected source frames:", ", ".join(map(str, selected)))
    print("wrote:", args.output)


if __name__ == "__main__":
    main()

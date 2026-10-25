#!/usr/bin/env python3
"""把若干PCM WAV波表打包为FPGA SD->DDR路径使用的WTB1文件。"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
import struct
import wave


TARGET_FRAMES = 256
TARGET_SAMPLES_PER_FRAME = 256
MAX_TABLES = 16
HEADER_SIZE = 32


def decode_pcm_sample(raw: bytes, sample_width: int) -> int:
    if sample_width == 1:
        return (raw[0] - 128) << 8
    if sample_width == 2:
        return int.from_bytes(raw, "little", signed=True)
    if sample_width == 3:
        value = int.from_bytes(raw, "little", signed=False)
        if value & 0x800000:
            value -= 1 << 24
        return value >> 8
    if sample_width == 4:
        return int.from_bytes(raw, "little", signed=True) >> 16
    raise ValueError(f"不支持的PCM位宽：{sample_width * 8} bit")


def read_float32_first_channel(path: Path) -> list[int]:
    """读取Python wave模块尚不支持的IEEE float32 WAV。"""
    wav_data = path.read_bytes()
    if wav_data[:4] != b"RIFF" or wav_data[8:12] != b"WAVE":
        raise ValueError(f"{path} 不是RIFF/WAVE文件")

    fmt_chunk: bytes | None = None
    sample_data: bytes | None = None
    offset = 12
    while offset + 8 <= len(wav_data):
        chunk_id = wav_data[offset : offset + 4]
        chunk_size = struct.unpack_from("<I", wav_data, offset + 4)[0]
        chunk_start = offset + 8
        chunk_end = chunk_start + chunk_size
        if chunk_end > len(wav_data):
            raise ValueError(f"{path} 的WAV区块长度无效")
        if chunk_id == b"fmt ":
            fmt_chunk = wav_data[chunk_start:chunk_end]
        elif chunk_id == b"data":
            sample_data = wav_data[chunk_start:chunk_end]
        offset = chunk_end + (chunk_size & 1)

    if fmt_chunk is None or len(fmt_chunk) < 16 or sample_data is None:
        raise ValueError(f"{path} 缺少fmt或data区块")
    audio_format, channels, _, _, block_align, bits = struct.unpack_from(
        "<HHIIHH", fmt_chunk
    )
    if audio_format != 3 or bits != 32:
        raise ValueError(f"{path} 不是支持的整数PCM或32位IEEE浮点WAV")
    if channels < 1 or block_align != channels * 4:
        raise ValueError(f"{path} 的声道或块对齐参数无效")
    if len(sample_data) % block_align:
        raise ValueError(f"{path} 的采样数据没有按帧对齐")

    result: list[int] = []
    for frame_offset in range(0, len(sample_data), block_align):
        value = struct.unpack_from("<f", sample_data, frame_offset)[0]
        if not math.isfinite(value):
            raise ValueError(f"{path} 含有NaN或无穷浮点采样")
        if value <= -1.0:
            result.append(-32768)
        elif value >= 1.0:
            result.append(32767)
        else:
            result.append(round(value * 32767.0))
    return result


def read_first_channel(path: Path) -> list[int]:
    try:
        with wave.open(str(path), "rb") as wav_file:
            if wav_file.getcomptype() != "NONE":
                raise ValueError(f"{path} 不是未压缩PCM WAV")
            channels = wav_file.getnchannels()
            sample_width = wav_file.getsampwidth()
            frame_count = wav_file.getnframes()
            raw = wav_file.readframes(frame_count)
    except wave.Error as error:
        if "unknown format: 3" not in str(error):
            raise ValueError(f"无法解析{path}：{error}") from error
        return read_float32_first_channel(path)

    stride = channels * sample_width
    return [
        decode_pcm_sample(raw[offset : offset + sample_width], sample_width)
        for offset in range(0, len(raw), stride)
    ]


def resample_frame(frame: list[int]) -> list[int]:
    if len(frame) == TARGET_SAMPLES_PER_FRAME:
        return frame[:]
    if len(frame) < 2:
        return [frame[0] if frame else 0] * TARGET_SAMPLES_PER_FRAME

    result: list[int] = []
    source_last = len(frame) - 1
    target_last = TARGET_SAMPLES_PER_FRAME - 1
    for target_index in range(TARGET_SAMPLES_PER_FRAME):
        numerator = target_index * source_last
        left_index, remainder = divmod(numerator, target_last)
        right_index = min(left_index + 1, source_last)
        left = frame[left_index]
        right = frame[right_index]
        value = round(left + (right - left) * remainder / target_last)
        result.append(max(-32768, min(32767, value)))
    return result


def convert_table(path: Path, source_frame_size: int) -> list[list[int]]:
    samples = read_first_channel(path)
    if len(samples) < source_frame_size:
        raise ValueError(
            f"{path} 只有{len(samples)}个采样，少于一帧{source_frame_size}个采样"
        )
    source_frame_count = len(samples) // source_frame_size
    if len(samples) % source_frame_size:
        print(f"警告：{path.name}尾部不足一帧的数据将被忽略")

    source_frames = [
        resample_frame(
            samples[index * source_frame_size : (index + 1) * source_frame_size]
        )
        for index in range(source_frame_count)
    ]
    if source_frame_count == 1:
        return [source_frames[0][:] for _ in range(TARGET_FRAMES)]

    # 把源波表的完整帧轴映射到0～255。源帧少于256时在相邻帧间插值，
    # 避免旧实现用最后一帧填满尾部，导致大部分WT Position失去变化。
    table: list[list[int]] = []
    target_last = TARGET_FRAMES - 1
    source_last = source_frame_count - 1
    for target_index in range(TARGET_FRAMES):
        numerator = target_index * source_last
        left_index, remainder = divmod(numerator, target_last)
        right_index = min(left_index + 1, source_last)
        if remainder == 0:
            table.append(source_frames[left_index][:])
            continue
        left_frame = source_frames[left_index]
        right_frame = source_frames[right_index]
        table.append(
            [
                max(
                    -32768,
                    min(
                        32767,
                        round(
                            left
                            + (right - left) * remainder / target_last
                        ),
                    ),
                )
                for left, right in zip(left_frame, right_frame)
            ]
        )
    return table


def build_header(table_count: int) -> bytes:
    header = bytearray(HEADER_SIZE)
    header[0:4] = b"WTB1"
    header[4] = 1
    header[5] = table_count
    header[6:8] = TARGET_FRAMES.to_bytes(2, "little")
    header[8:10] = TARGET_SAMPLES_PER_FRAME.to_bytes(2, "little")
    header[10] = 16
    header[11] = 1  # little endian
    return bytes(header)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="把1～16个波表WAV打包为固定布局的WTB1文件"
    )
    parser.add_argument("inputs", nargs="+", type=Path, help="每个WAV对应一张波表")
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument(
        "--source-frame-size",
        type=int,
        default=2048,
        help="输入WAV每帧采样数，Serum波表通常为2048，默认2048",
    )
    args = parser.parse_args()

    if not 1 <= len(args.inputs) <= MAX_TABLES:
        parser.error(f"输入波表数量必须为1～{MAX_TABLES}")
    if args.source_frame_size < 2:
        parser.error("source-frame-size必须至少为2")

    tables = [convert_table(path, args.source_frame_size) for path in args.inputs]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("wb") as output_file:
        output_file.write(build_header(len(tables)))
        for table in tables:
            for frame in table:
                output_file.write(struct.pack("<256h", *frame))

    expected_size = HEADER_SIZE + len(tables) * 256 * 256 * 2
    actual_size = args.output.stat().st_size
    if actual_size != expected_size:
        raise RuntimeError(f"输出尺寸错误：期望{expected_size}，实际{actual_size}")
    print(
        f"已生成 {args.output}：{len(tables)}张波表，"
        f"每张256帧×256采样，{actual_size}字节"
    )


if __name__ == "__main__":
    main()

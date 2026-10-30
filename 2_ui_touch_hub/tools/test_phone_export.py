from pathlib import Path
import math
import random
import re
from run_phone_rtl import run, ROOT


def main():
    text = (ROOT / "rtl/ui_vector_engine/performance_export_coeffs.vh").read_text()
    coefficients = [int(n, 16) for n in re.findall(r"16'sh([0-9a-f]+)", text)][:127]
    coefficients = [n - 65536 if n >= 32768 else n for n in coefficients]
    assert len(coefficients) == 127 and sum(coefficients) == 32768
    rng = random.Random(4407)
    samples = []
    for n in range(8192):
        if n < 300:
            pair = (32767 if n < 150 else -32768, -32768 if n < 150 else 32767)
        elif n < 800:
            pair = (32767 if n == 400 else 0, -32768 if n == 401 else 0)
        elif n < 4000:
            pair = (int(25000 * math.sin(2 * math.pi * 1000 * n / 96000)),
                    int(30000 * math.sin(2 * math.pi * 8000 * n / 96000)))
        else:
            pair = (rng.randint(-32768, 32767), rng.randint(-32768, 32767))
        samples.append(pair)
    def packed(pair):
        return f"{((pair[1] & 65535) << 16) | (pair[0] & 65535):08x}"
    golden = []
    for at in range(11, len(samples), 12):
        values = []
        for channel in (0, 1):
            accum = sum(c * samples[at - k][channel] for k, c in enumerate(coefficients) if at >= k)
            values.append(max(-32768, min(32767, (accum + 16384) >> 15)))
        golden.append(values)
    run("tb_performance_audio_export", ["rtl/performance/performance_export_filter.v",
        "rtl/performance/performance_audio_export.v", "sim/tb_performance_audio_export.v"],
        {"pcm.hex": "\n".join(map(packed, samples)), "gold.hex": "\n".join(map(packed, golden))})


if __name__ == "__main__":
    main()

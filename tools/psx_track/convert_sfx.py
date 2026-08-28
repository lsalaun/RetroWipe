"""Decodes wipeout/SOUND/WIPEOUT.VB (Sony VAG ADPCM, 16-byte blocks) to WAV.

Mirrors sfx_load() in src/wipeout/sfx.c. Sample names follow sfx.h
sfx_source_t. Mixing in the C engine plays non-voice SFX at pitch 0.5
(22.05 kHz content in a 44.1 kHz mix) and voice samples at pitch 1.0
(44.1 kHz). This exporter writes WAV at the *content* rate so Godot
AudioStreamWAV plays at the intended pitch without a pitch_scale hack.

Usage:
    py convert_sfx.py wipeout/SOUND/WIPEOUT.VB out_dir/
"""

from __future__ import annotations

import argparse
import struct
import wave
from pathlib import Path

VAG_REGION_START = 1
VAG_REGION = 2
VAG_REGION_END = 4

# sfx.c vag_tab, already << 14
VAG_TAB = (
    (0, 0),
    (15360, 0),
    (29440, -13312),
    (25088, -14080),
    (31232, -15360),
)

# sfx.h sfx_source_t order. Extra decoded regions (if any) get sfx_NN.wav.
SFX_NAMES = [
    "crunch",
    "ebolt",
    "engine_intake",
    "engine_rumble",
    "engine_thrust",
    "explosion_1",
    "explosion_2",
    "impact",
    "menu_move",
    "menu_select",
    "menu_transition",
    "mine_drop",
    "missile_fire",
    "engine_remote",
    "powerup",
    "shield",
    "siren",
    "tractor",
    "turbulence",
    "crowd",
    "voice_mines",
    "voice_missile",
    "voice_rockets",
    "voice_revcon",
    "voice_shockwave",
    "voice_special",
    "voice_count_3",
    "voice_count_2",
    "voice_count_1",
    "voice_count_go",
]

VOICE_START_INDEX = 20  # SFX_VOICE_MINES
MIX_RATE = 44100


def clamp_i16(sample: int) -> int:
    return max(-32768, min(32767, sample))


def decode_vag(vb: bytes) -> list[list[int]]:
    """Port of sfx_load()'s VAG loop. Returns one PCM list per region."""
    sources: list[list[int]] = []
    current: list[int] | None = None
    history = [0, 0]
    p = 0
    size = len(vb)
    while p < size:
        header = vb[p]
        flags = vb[p + 1]
        p += 2
        shift = header & 0x0F
        predictor = min(header >> 4, 4)

        # sfx_load(): END sets sources[n].samples to the current buffer index
        # (begin capture). START closes the region. Blocks before the first END
        # still decode into the global PCM buffer but are not referenced.
        if flags & VAG_REGION_END:
            current = []
            sources.append(current)

        for _ in range(14):
            byte = vb[p]
            p += 1
            nibbles = ((byte & 0x0F) << 12, (byte & 0xF0) << 8)
            for nibble in nibbles:
                sample = nibble
                if sample & 0x8000:
                    sample |= -65536
                sample >>= shift
                sample += (history[0] * VAG_TAB[predictor][0] + history[1] * VAG_TAB[predictor][1]) >> 14
                history[1] = history[0]
                history[0] = sample
                if current is not None:
                    current.append(clamp_i16(sample))

        if flags & VAG_REGION_START:
            current = None

    if current is not None:
        raise SystemExit("VAG stream ended inside a region (missing VAG_REGION_START)")
    return sources


def content_rate(index: int) -> int:
    # sfx_get_node(): pitch = 1.0 for voice, 0.5 otherwise, mix is 44100 Hz.
    return MIX_RATE if index >= VOICE_START_INDEX else MIX_RATE // 2


def write_wav(path: Path, samples: list[int], sample_rate: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "w") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def source_name(index: int) -> str:
    if 0 <= index < len(SFX_NAMES):
        return SFX_NAMES[index]
    return f"sfx_{index:02d}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("vb", type=Path, help="Path to WIPEOUT.VB")
    parser.add_argument("output_dir", type=Path, help="Directory to write one WAV per SFX")
    parser.add_argument(
        "--mix-rate",
        action="store_true",
        help="Write every sample at 44100 Hz (engine mix rate) instead of content rate",
    )
    args = parser.parse_args()

    sources = decode_vag(args.vb.read_bytes())
    args.output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Decoded {len(sources)} VAG region(s) from {args.vb}")
    for index, samples in enumerate(sources):
        rate = MIX_RATE if args.mix_rate else content_rate(index)
        name = source_name(index)
        out_path = args.output_dir / f"{name}.wav"
        write_wav(out_path, samples, rate)
        seconds = len(samples) / rate if rate else 0.0
        print(f"  [{index:02d}] {name}: {len(samples)} samples @ {rate} Hz ({seconds:.2f}s) -> {out_path.name}")


if __name__ == "__main__":
    main()

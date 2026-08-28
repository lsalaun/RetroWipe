"""Copy wipeout/music into Godot and decode WIPEOUT.VB SFX.

Godot 4 imports MP3 natively. QOA is what the C engine plays; keep it in
scratch if you need bit-exact source, but copy MP3 (or WAV SFX) into
godot/src/assets/.

Usage:
    py import_audio.py
    py import_audio.py --sfx-only
    py import_audio.py --music-only
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
GODOT_DIR = TOOLS_DIR.parent.parent
REPO_ROOT = GODOT_DIR.parent

MUSIC_NAMES = {
    "track01": "cairodrome",
    "track02": "cardinal_dancer",
    "track03": "cold_comfort",
    "track04": "doh_t",
    "track05": "messij",
    "track06": "operatique",
    "track07": "tentative",
    "track08": "trancevaal",
    "track09": "afro_ride",
    "track10": "chemical_beats",
    "track11": "wipeout",
}


def copy_music(src_dir: Path, dest_dir: Path) -> None:
    dest_dir.mkdir(parents=True, exist_ok=True)
    files = sorted(src_dir.glob("track*.mp3"))
    if not files:
        raise SystemExit(f"no track*.mp3 in {src_dir}")
    for src in files:
        pretty = MUSIC_NAMES.get(src.stem.lower(), src.stem.lower())
        dest = dest_dir / f"{pretty}.mp3"
        shutil.copy2(src, dest)
        print(f"copied {src.name} -> {dest.name}")


def decode_sfx(vb: Path, dest_dir: Path) -> None:
    cmd = [sys.executable, str(TOOLS_DIR / "convert_sfx.py"), str(vb), str(dest_dir)]
    print("+", " ".join(cmd))
    subprocess.run(cmd, check=True, cwd=str(TOOLS_DIR))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--wipeout-root", type=Path, default=REPO_ROOT / "wipeout")
    parser.add_argument("--music-dest", type=Path, default=GODOT_DIR / "src" / "assets" / "music")
    parser.add_argument("--sfx-dest", type=Path, default=GODOT_DIR / "src" / "assets" / "sfx")
    parser.add_argument("--music-only", action="store_true")
    parser.add_argument("--sfx-only", action="store_true")
    args = parser.parse_args()

    do_music = not args.sfx_only
    do_sfx = not args.music_only
    if args.music_only and args.sfx_only:
        do_music = do_sfx = True

    if do_music:
        copy_music(args.wipeout_root / "music", args.music_dest)
    if do_sfx:
        decode_sfx(args.wipeout_root / "SOUND" / "WIPEOUT.VB", args.sfx_dest)
    print("done audio")


if __name__ == "__main__":
    main()

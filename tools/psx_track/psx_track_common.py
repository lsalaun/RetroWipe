"""Shared helpers for the PSX WipEout track converters (convert_track_geometry.py,
convert_track_sections.py). See convert_track_geometry.py's module docstring
for why reads are big-endian and why Y gets negated by default.
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path
from typing import TypedDict

# Derived from TRACK01/Altima VII: its documented real-world lap length
# (~5500m, wipeout.fandom.com/wiki/Altima_VII) divided by the raw length of
# the TRACK.TRS centerline (585969 raw units) = ~106.5 raw units per meter.
# A cross-check from the documented elevation change (359m vs 11948 raw units
# of Y range) gives ~33.3 instead -- an unresolved ~3.2x discrepancy, see
# docs/.transactional/26-08-24-02/audit/physique_vaisseau_audit.md point 4.
# Treat this as an estimate: override with --units-per-meter if a better
# figure turns up, or pass 1.0 to keep raw PSX units unscaled.
DEFAULT_UNITS_PER_METER = 106.5


def make_axis_transform(flip_z: bool):
    def transform(v: tuple[float, float, float]) -> tuple[float, float, float]:
        x, y, z = v
        return (x, -y, -z if flip_z else z)

    # An odd number of negated axes flips triangle winding/handedness.
    reverse_winding = not flip_z
    return transform, reverse_winding


def scale_point(v: tuple[float, float, float], units_per_meter: float) -> tuple[float, float, float]:
    """Converts a raw-PSX-unit position (already axis-transformed) to meters.

    Only for positions/centers, never for normals or other pure directions --
    dividing a direction by a scalar keeps it pointing the same way but no
    longer unit-length.
    """
    return (v[0] / units_per_meter, v[1] / units_per_meter, v[2] / units_per_meter)


# ---------------------------------------------------------------------------
# Track texture retrieval (LIBRARY.CMP + LIBRARY.TTF -> per-face PNG tiles).
#
# Ports of image.c's lzss_decompress()/image_load_compressed()/
# image_load_from_bytes() and track.c's track_load_tile_format()/track_load()
# tile-assembly loop. All reads here are little-endian (get_*_le in the C
# code), unlike TRACK.TRV/TRF's big-endian geometry -- this is not a typo,
# see convert_track_geometry.py's module docstring.

_LZSS_INDEX_BIT_COUNT = 13
_LZSS_LENGTH_BIT_COUNT = 4
_LZSS_WINDOW_SIZE = 1 << _LZSS_INDEX_BIT_COUNT
_LZSS_BREAK_EVEN = (1 + _LZSS_INDEX_BIT_COUNT + _LZSS_LENGTH_BIT_COUNT) // 9

_TIM_TYPE_PALETTED_4_BPP = 0x08
_TIM_TYPE_PALETTED_8_BPP = 0x09
_TIM_TYPE_TRUE_COLOR_16_BPP = 0x02

TRACK_TILE_SUB_TILE_SIZE = 32
TRACK_TILE_GRID = 4  # 4x4 sub-tiles per assembled near-LOD texture (128x128)


class TtfTile(TypedDict):
    near: list[int]
    med: list[int]
    far: int


class _BitReader:
    """MSB-first bit reader matching image.c's in_bfile_rack/in_bfile_mask."""

    def __init__(self, data: bytes) -> None:
        self._data = data
        self._pos = 0
        self._rack = 0
        self._mask = 0x80

    def read_bit(self) -> int:
        if self._mask == 0x80:
            self._rack = self._data[self._pos]
            self._pos += 1
        value = 1 if (self._rack & self._mask) else 0
        self._mask >>= 1
        if self._mask == 0:
            self._mask = 0x80
        return value

    def read_bits(self, count: int) -> int:
        result = 0
        for _ in range(count):
            result = (result << 1) | self.read_bit()
        return result


def lzss_decompress(data: bytes, decompressed_size: int) -> bytes:
    """Port of image.c's lzss_decompress(), stopping once `decompressed_size`
    bytes have been produced (mirrors the fixed-size output buffer the C code
    writes into) or the end-of-stream marker (a zero match position) is hit,
    whichever comes first.
    """
    reader = _BitReader(data)
    window = bytearray(_LZSS_WINDOW_SIZE)
    current_position = 1
    out = bytearray()

    while len(out) < decompressed_size:
        if reader.read_bit():
            cc = reader.read_bits(8)
            out.append(cc)
            window[current_position] = cc
            current_position = (current_position + 1) % _LZSS_WINDOW_SIZE
        else:
            match_position = reader.read_bits(_LZSS_INDEX_BIT_COUNT)
            if match_position == 0:
                break
            match_length = reader.read_bits(_LZSS_LENGTH_BIT_COUNT) + _LZSS_BREAK_EVEN
            for i in range(match_length + 1):
                cc = window[(match_position + i) % _LZSS_WINDOW_SIZE]
                out.append(cc)
                window[current_position] = cc
                current_position = (current_position + 1) % _LZSS_WINDOW_SIZE
                if len(out) >= decompressed_size:
                    break

    return bytes(out[:decompressed_size])


def parse_cmp(data: bytes) -> list[bytes]:
    """Port of image_load_compressed(): a CMP file is a header of per-entry
    decompressed sizes followed by a single LZSS stream for all entries
    concatenated together.
    """
    image_count = struct.unpack_from("<i", data, 0)[0]
    p = 4
    sizes = list(struct.unpack_from(f"<{image_count}i", data, p))
    p += 4 * image_count

    decompressed = lzss_decompress(data[p:], sum(sizes))

    entries = []
    offset = 0
    for size in sizes:
        entries.append(decompressed[offset:offset + size])
        offset += size
    return entries


def _tim_16bit_to_rgba(c: int, transparent: bool) -> tuple[int, int, int, int]:
    r = ((c >> 0) & 0x1F) << 3
    g = ((c >> 5) & 0x1F) << 3
    b = ((c >> 10) & 0x1F) << 3
    if c == 0 or (transparent and (c & 0x7FFF) == 0):
        a = 0x00
    else:
        a = 0xFF
    return (r, g, b, a)


def parse_tim(data: bytes, transparent: bool = False) -> tuple[int, int, bytes]:
    """Port of image_load_from_bytes(). Returns (width, height, rgba_bytes)."""
    p = 4  # skip magic
    type_ = struct.unpack_from("<i", data, p)[0] & 0xF
    p += 4

    palette = [(0, 0, 0, 0)] * 256
    if type_ in (_TIM_TYPE_PALETTED_4_BPP, _TIM_TYPE_PALETTED_8_BPP):
        p += 4  # header_length
        p += 2  # palette_x
        p += 2  # palette_y
        palette_colors = struct.unpack_from("<H", data, p)[0]
        p += 2
        p += 2  # palettes
        for i in range(palette_colors):
            color = struct.unpack_from("<H", data, p)[0]
            p += 2
            palette[i] = _tim_16bit_to_rgba(color, transparent)

    p += 4  # data_size

    pixels_per_16bit = 1
    if type_ == _TIM_TYPE_PALETTED_8_BPP:
        pixels_per_16bit = 2
    elif type_ == _TIM_TYPE_PALETTED_4_BPP:
        pixels_per_16bit = 4

    p += 2  # skip_x
    p += 2  # skip_y
    entries_per_row = struct.unpack_from("<H", data, p)[0]
    p += 2
    rows = struct.unpack_from("<H", data, p)[0]
    p += 2

    width = entries_per_row * pixels_per_16bit
    height = rows
    entry_count = entries_per_row * rows

    pixels = bytearray(width * height * 4)
    pos = 0

    if type_ == _TIM_TYPE_TRUE_COLOR_16_BPP:
        for _ in range(entry_count):
            color = struct.unpack_from("<H", data, p)[0]
            p += 2
            pixels[pos:pos + 4] = bytes(_tim_16bit_to_rgba(color, transparent))
            pos += 4
    elif type_ == _TIM_TYPE_PALETTED_8_BPP:
        for _ in range(entry_count):
            value = struct.unpack_from("<H", data, p)[0]
            p += 2
            for shift in (0, 8):
                pixels[pos:pos + 4] = bytes(palette[(value >> shift) & 0xFF])
                pos += 4
    elif type_ == _TIM_TYPE_PALETTED_4_BPP:
        for _ in range(entry_count):
            value = struct.unpack_from("<H", data, p)[0]
            p += 2
            for shift in (0, 4, 8, 12):
                pixels[pos:pos + 4] = bytes(palette[(value >> shift) & 0xF])
                pos += 4
    else:
        raise ValueError(f"Unsupported TIM type {type_:#x}")

    return width, height, bytes(pixels)


def parse_ttf(data: bytes) -> list[TtfTile]:
    """Port of track_load_tile_format(): each 42-byte entry maps a track
    texture id to 16 near-LOD, 4 med-LOD and 1 far-LOD sub-tile indices into
    LIBRARY.CMP's entries. Unlike LIBRARY.CMP/the TIM images it references,
    LIBRARY.TTF is read with track.c's big-endian get_i16() (not get_i16_le),
    matching TRACK.TRV/TRF -- see convert_track_geometry.py's module
    docstring for why.
    """
    tile_struct_size = 16 * 2 + 4 * 2 + 2
    num_tiles = len(data) // tile_struct_size
    tiles = []
    p = 0
    for _ in range(num_tiles):
        near = list(struct.unpack_from(">16H", data, p))
        p += 32
        med = list(struct.unpack_from(">4H", data, p))
        p += 8
        far = struct.unpack_from(">H", data, p)[0]
        p += 2
        tiles.append({"near": near, "med": med, "far": far})
    return tiles


def build_tile_texture(cmp_entries: list[bytes], near: list[int]) -> tuple[int, int, bytes]:
    """Assembles one near-LOD track texture (default 128x128) from its 4x4
    grid of 32x32 sub-tiles, mirroring track_load()'s temp_tile assembly.
    """
    tile_size = TRACK_TILE_SUB_TILE_SIZE
    grid = TRACK_TILE_GRID
    size = tile_size * grid
    out = bytearray(size * size * 4)

    for ty in range(grid):
        for tx in range(grid):
            sub_tile_index = near[ty * grid + tx]
            sub_w, sub_h, sub_pixels = parse_tim(cmp_entries[sub_tile_index])
            for row in range(sub_h):
                src_off = row * sub_w * 4
                dst_x = tx * tile_size
                dst_y = ty * tile_size + row
                dst_off = (dst_y * size + dst_x) * 4
                out[dst_off:dst_off + sub_w * 4] = sub_pixels[src_off:src_off + sub_w * 4]

    return size, size, bytes(out)


def write_png(path: Path, width: int, height: int, rgba: bytes) -> None:
    """Minimal stdlib-only 8-bit RGBA PNG writer (no Pillow dependency)."""

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    stride = width * 4
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type 0 (None)
        raw.extend(rgba[y * stride:(y + 1) * stride])

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # color type 6 = RGBA
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", ihdr)
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)

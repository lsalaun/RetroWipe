"""Shared helpers for the PSX WipEout track converters (convert_track_geometry.py,
convert_track_sections.py). See convert_track_geometry.py's module docstring
for why reads are big-endian and why Y gets negated by default.
"""

from __future__ import annotations

import json
import struct
import zlib
from dataclasses import dataclass
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
# TRACK.TRV / TRACK.TRF parsing, shared by convert_track_geometry.py and
# convert_track_face_flags.py. See convert_track_geometry.py's module
# docstring for the exact binary layout and why reads are big-endian.

FACE_TRACK_BASE       = 1 << 0
FACE_PICKUP_LEFT      = 1 << 1
FACE_FLIP_TEXTURE     = 1 << 2
FACE_PICKUP_RIGHT     = 1 << 3
FACE_START_GRID       = 1 << 4
FACE_BOOST            = 1 << 5
FACE_PICKUP_COLLECTED = 1 << 6
FACE_PICKUP_ACTIVE    = 1 << 7

VERTEX_STRUCT = struct.Struct(">3i4x")  # x, y, z (int32, big-endian), 4 bytes padding
FACE_STRUCT = struct.Struct(">4h3hBBI")  # v0..v3, nx,ny,nz, texture, flags, color (big-endian)


@dataclass
class Face:
    indices: tuple[int, int, int, int]
    normal: tuple[float, float, float]
    texture: int
    flags: int


def parse_trv(path: Path) -> list[tuple[float, float, float]]:
    data = path.read_bytes()
    count = len(data) // VERTEX_STRUCT.size
    return [VERTEX_STRUCT.unpack_from(data, i * VERTEX_STRUCT.size) for i in range(count)]


def parse_trf(path: Path) -> list[Face]:
    data = path.read_bytes()
    count = len(data) // FACE_STRUCT.size
    faces = []
    for i in range(count):
        v0, v1, v2, v3, nx, ny, nz, texture, flags, _color = FACE_STRUCT.unpack_from(
            data, i * FACE_STRUCT.size
        )
        normal = (nx / 4096.0, ny / 4096.0, nz / 4096.0)
        faces.append(Face((v0, v1, v2, v3), normal, texture, flags))
    return faces


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


# ---------------------------------------------------------------------------
# Scenery objects (SCENE.PRM/SKY.PRM + SCENE.CMP/SKY.CMP).
#
# Port of objects_load() in wipeout-rewrite's src/wipeout/object.c. All
# reads are big-endian (get_i16()/get_i32()), like TRACK.TRV/TRF/TRS -- see
# convert_track_geometry.py's module docstring for why. Unlike LIBRARY.CMP
# (a tiled texture atlas indexed per track face), SCENE.CMP/SKY.CMP are a
# flat list of standalone textures -- see image_get_compressed_textures() in
# image.c -- so each `texture` index here maps 1:1 to a parse_cmp() entry,
# decoded directly with parse_tim(), no tile assembly needed.

PRM_TYPE_F3 = 1
PRM_TYPE_FT3 = 2
PRM_TYPE_F4 = 3
PRM_TYPE_FT4 = 4
PRM_TYPE_G3 = 5
PRM_TYPE_GT3 = 6
PRM_TYPE_G4 = 7
PRM_TYPE_GT4 = 8
PRM_TYPE_LF2 = 9  # defined upstream but never emitted by any real asset
PRM_TYPE_TSPR = 10
PRM_TYPE_BSPR = 11
PRM_TYPE_LSF3 = 12
PRM_TYPE_LSFT3 = 13
PRM_TYPE_LSF4 = 14
PRM_TYPE_LSFT4 = 15
PRM_TYPE_LSG3 = 16
PRM_TYPE_LSGT3 = 17
PRM_TYPE_LSG4 = 18
PRM_TYPE_LSGT4 = 19
PRM_TYPE_SPLINE = 20
PRM_TYPE_INFINITE_LIGHT = 21
PRM_TYPE_POINT_LIGHT = 22
PRM_TYPE_SPOT_LIGHT = 23


class ScenePrimitive(TypedDict):
    type: int
    coords: list[int]  # indices into the object's vertex list
    texture: int | None  # index into the CMP's flat texture list, or None if untextured
    uvs: list[tuple[int, int]]  # raw 0..255 texel bytes, one per coord (only if textured)
    colors: list[tuple[int, int, int, int]]  # one per coord


class SceneObject(TypedDict):
    name: str
    origin: tuple[float, float, float]
    vertices: list[tuple[float, float, float]]
    primitives: list[ScenePrimitive]


class _Cursor:
    """Sequential big-endian reader mirroring utils.h's get_i16()/get_i32()."""

    def __init__(self, data: bytes) -> None:
        self.data = data
        self.pos = 0

    def i16(self) -> int:
        v = struct.unpack_from(">h", self.data, self.pos)[0]
        self.pos += 2
        return v

    def u8(self) -> int:
        v = self.data[self.pos]
        self.pos += 1
        return v

    def i32(self) -> int:
        v = struct.unpack_from(">i", self.data, self.pos)[0]
        self.pos += 4
        return v

    def u32(self) -> int:
        v = struct.unpack_from(">I", self.data, self.pos)[0]
        self.pos += 4
        return v

    def skip(self, n: int) -> None:
        self.pos += n


def _read_color(cur: _Cursor) -> tuple[int, int, int, int]:
    # rgba_from_u32(): r/g/b are the top 3 bytes of the u32; alpha is always
    # opaque (the 4th byte in the file is discarded, matching the engine).
    v = cur.u32()
    return ((v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, 255)


def _read_primitive(cur: _Cursor, prm_type: int) -> ScenePrimitive | None:
    """Port of the big switch in objects_load(). Returns None for primitive
    types that carry no mesh geometry (sprites/splines/lights); the cursor is
    still advanced past their fields so the primitive stream stays aligned.
    """
    if prm_type == PRM_TYPE_F3:
        coords = [cur.i16() for _ in range(3)]
        cur.skip(2)  # pad1
        color = _read_color(cur)
        return {"type": prm_type, "coords": coords, "texture": None, "uvs": [], "colors": [color] * 3}

    if prm_type == PRM_TYPE_F4:
        coords = [cur.i16() for _ in range(4)]
        color = _read_color(cur)
        return {"type": prm_type, "coords": coords, "texture": None, "uvs": [], "colors": [color] * 4}

    if prm_type == PRM_TYPE_FT3:
        coords = [cur.i16() for _ in range(3)]
        texture = cur.i16()
        cur.skip(4)  # cba, tsb
        uvs = [(cur.u8(), cur.u8()) for _ in range(3)]
        cur.skip(2)  # pad1
        color = _read_color(cur)
        return {"type": prm_type, "coords": coords, "texture": texture, "uvs": uvs, "colors": [color] * 3}

    if prm_type == PRM_TYPE_FT4:
        coords = [cur.i16() for _ in range(4)]
        texture = cur.i16()
        cur.skip(4)  # cba, tsb
        uvs = [(cur.u8(), cur.u8()) for _ in range(4)]
        cur.skip(2)  # pad1
        color = _read_color(cur)
        return {"type": prm_type, "coords": coords, "texture": texture, "uvs": uvs, "colors": [color] * 4}

    if prm_type == PRM_TYPE_G3:
        coords = [cur.i16() for _ in range(3)]
        cur.skip(2)  # pad1
        colors = [_read_color(cur) for _ in range(3)]
        return {"type": prm_type, "coords": coords, "texture": None, "uvs": [], "colors": colors}

    if prm_type == PRM_TYPE_G4:
        coords = [cur.i16() for _ in range(4)]
        colors = [_read_color(cur) for _ in range(4)]
        return {"type": prm_type, "coords": coords, "texture": None, "uvs": [], "colors": colors}

    if prm_type == PRM_TYPE_GT3:
        coords = [cur.i16() for _ in range(3)]
        texture = cur.i16()
        cur.skip(4)  # cba, tsb
        uvs = [(cur.u8(), cur.u8()) for _ in range(3)]
        cur.skip(2)  # pad1
        colors = [_read_color(cur) for _ in range(3)]
        return {"type": prm_type, "coords": coords, "texture": texture, "uvs": uvs, "colors": colors}

    if prm_type == PRM_TYPE_GT4:
        coords = [cur.i16() for _ in range(4)]
        texture = cur.i16()
        cur.skip(4)  # cba, tsb
        uvs = [(cur.u8(), cur.u8()) for _ in range(4)]
        cur.skip(2)  # pad1
        colors = [_read_color(cur) for _ in range(4)]
        return {"type": prm_type, "coords": coords, "texture": texture, "uvs": uvs, "colors": colors}

    if prm_type == PRM_TYPE_LSF3:
        coords = [cur.i16() for _ in range(3)]
        cur.skip(2)  # normal index (lighting only, not needed for static geometry)
        color = _read_color(cur)
        return {"type": prm_type, "coords": coords, "texture": None, "uvs": [], "colors": [color] * 3}

    if prm_type == PRM_TYPE_LSF4:
        coords = [cur.i16() for _ in range(4)]
        cur.skip(2)  # normal index
        cur.skip(2)  # pad1
        color = _read_color(cur)
        return {"type": prm_type, "coords": coords, "texture": None, "uvs": [], "colors": [color] * 4}

    if prm_type == PRM_TYPE_LSFT3:
        coords = [cur.i16() for _ in range(3)]
        cur.skip(2)  # normal index
        texture = cur.i16()
        cur.skip(4)  # cba, tsb
        uvs = [(cur.u8(), cur.u8()) for _ in range(3)]
        color = _read_color(cur)  # no pad1 for this type
        return {"type": prm_type, "coords": coords, "texture": texture, "uvs": uvs, "colors": [color] * 3}

    if prm_type == PRM_TYPE_LSFT4:
        coords = [cur.i16() for _ in range(4)]
        cur.skip(2)  # normal index
        texture = cur.i16()
        cur.skip(4)  # cba, tsb
        uvs = [(cur.u8(), cur.u8()) for _ in range(4)]
        color = _read_color(cur)  # no pad1 for this type
        return {"type": prm_type, "coords": coords, "texture": texture, "uvs": uvs, "colors": [color] * 4}

    if prm_type == PRM_TYPE_LSG3:
        coords = [cur.i16() for _ in range(3)]
        cur.skip(6)  # 3 normal indices
        colors = [_read_color(cur) for _ in range(3)]
        return {"type": prm_type, "coords": coords, "texture": None, "uvs": [], "colors": colors}

    if prm_type == PRM_TYPE_LSG4:
        coords = [cur.i16() for _ in range(4)]
        cur.skip(8)  # 4 normal indices
        colors = [_read_color(cur) for _ in range(4)]
        return {"type": prm_type, "coords": coords, "texture": None, "uvs": [], "colors": colors}

    if prm_type == PRM_TYPE_LSGT3:
        coords = [cur.i16() for _ in range(3)]
        cur.skip(6)  # 3 normal indices
        texture = cur.i16()
        cur.skip(4)  # cba, tsb
        uvs = [(cur.u8(), cur.u8()) for _ in range(3)]
        colors = [_read_color(cur) for _ in range(3)]  # no pad1 for this type
        return {"type": prm_type, "coords": coords, "texture": texture, "uvs": uvs, "colors": colors}

    if prm_type == PRM_TYPE_LSGT4:
        coords = [cur.i16() for _ in range(4)]
        cur.skip(8)  # 4 normal indices
        texture = cur.i16()
        cur.skip(4)  # cba, tsb
        uvs = [(cur.u8(), cur.u8()) for _ in range(4)]
        cur.skip(2)  # pad1 (this variant does have one)
        colors = [_read_color(cur) for _ in range(4)]
        return {"type": prm_type, "coords": coords, "texture": texture, "uvs": uvs, "colors": colors}

    if prm_type in (PRM_TYPE_TSPR, PRM_TYPE_BSPR):
        cur.skip(2 + 2 + 2)  # coord, width, height
        cur.skip(2)  # texture -- billboards aren't exported as mesh geometry (yet)
        cur.skip(4)  # color
        return None

    if prm_type == PRM_TYPE_SPLINE:
        cur.skip((4 * 3 + 4) * 3)  # control1, position, control2 (i32 vec3 + 4 bytes padding, x3)
        cur.skip(4)  # color
        return None

    if prm_type == PRM_TYPE_POINT_LIGHT:
        cur.skip(4 * 3 + 4)  # position + padding
        cur.skip(4)  # color
        cur.skip(2 + 2)  # startFalloff, endFalloff
        return None

    if prm_type == PRM_TYPE_SPOT_LIGHT:
        cur.skip(4 * 3 + 4)  # position + padding
        cur.skip(2 * 3 + 2)  # direction + padding
        cur.skip(4)  # color
        cur.skip(2 * 4)  # startFalloff, endFalloff, coneAngle, spreadAngle
        return None

    if prm_type == PRM_TYPE_INFINITE_LIGHT:
        cur.skip(2 * 3 + 2)  # direction + padding
        cur.skip(4)  # color
        return None

    raise ValueError(f"Unsupported PRM primitive type {prm_type} at offset {cur.pos}")


def parse_prm(data: bytes) -> list[SceneObject]:
    """Port of objects_load(): a PRM file is a flat list of Objects back to
    back, each with its own vertex/primitive arrays (normals are parsed only
    to advance the cursor -- Godot recomputes its own shading normals, so
    they aren't carried into the output).
    """
    cur = _Cursor(data)
    objects: list[SceneObject] = []

    while cur.pos < len(data):
        name = data[cur.pos:cur.pos + 16].split(b"\x00", 1)[0].decode("ascii", errors="replace")
        cur.skip(16)

        vertices_len = cur.i16()
        cur.skip(2)  # padding
        cur.skip(4)  # vertices pointer (runtime only)
        normals_len = cur.i16()
        cur.skip(2)  # padding
        cur.skip(4)  # normals pointer (runtime only)
        primitives_len = cur.i16()
        cur.skip(2)  # padding
        cur.skip(4)  # primitives pointer (runtime only)
        cur.skip(4 * 3)  # two unnamed fields + skeleton ref (runtime only)
        cur.skip(4)  # extent
        cur.skip(2)
        cur.skip(2)  # flags + padding
        cur.skip(4)  # next pointer (runtime only)
        cur.skip(3 * 3 * 2 + 2)  # relative rotation matrix + padding

        origin = (float(cur.i32()), float(cur.i32()), float(cur.i32()))

        cur.skip(3 * 3 * 2 + 2)  # absolute rotation matrix + padding
        cur.skip(3 * 4)  # absolute translation matrix
        cur.skip(2 + 2)  # skeleton update flag + padding
        cur.skip(4 * 3)  # skeleton super/sub/next (runtime only)

        vertices = []
        for _ in range(vertices_len):
            x, y, z = cur.i16(), cur.i16(), cur.i16()
            cur.skip(2)
            vertices.append((float(x), float(y), float(z)))

        cur.skip(normals_len * 8)  # normals: i16 x,y,z + 2 bytes padding each

        primitives: list[ScenePrimitive] = []
        for _ in range(primitives_len):
            prm_type = cur.i16()
            cur.skip(2)  # flag
            prim = _read_primitive(cur, prm_type)
            if prim is not None:
                primitives.append(prim)

        objects.append({"name": name, "origin": origin, "vertices": vertices, "primitives": primitives})

    return objects


# ---------------------------------------------------------------------------
# Shared triangle-soup/export helpers for PRM objects with a flat CMP texture
# list (SCENE.PRM/SKY.PRM/ALLSH.PRM/..., as opposed to LIBRARY.CMP's tiled
# track textures). Used by convert_track_scenery.py and convert_ships.py.

# object_draw() in object.c renders a primitive's coords in this order (NOT
# their storage order) -- e.g. `case PRM_TYPE_GT3: ... vertex[coord2],
# vertex[coord1], vertex[coord0]`, and for quads a 2nd triangle
# `vertex[coord2], vertex[coord3], vertex[coord1]`.
PRM_TRI3_ORDER = (2, 1, 0)
PRM_TRI4_ORDER_A = (2, 1, 0)
PRM_TRI4_ORDER_B = (2, 3, 1)


def emit_prm_object_triangles(
    world_vertices: list[tuple[float, float, float]],
    primitives: list[ScenePrimitive],
    cmp_entries: list[bytes],
    reverse_winding: bool,
    texture_dims_cache: dict[int, tuple[int, int]],
    groups: dict,
) -> None:
    """Appends one PRM object's primitives (vertices already in their final
    output space -- world space for scenery, local space for ship models) into
    `groups` (keyed by texture id, or None for untextured), matching the
    engine's object_draw() vertex order and per-vertex color/UV.
    """

    def texture_size(index: int) -> tuple[int, int]:
        if index not in texture_dims_cache:
            w, h, _ = parse_tim(cmp_entries[index])
            texture_dims_cache[index] = (w, h)
        return texture_dims_cache[index]

    order = (0, 2, 1) if reverse_winding else (0, 1, 2)

    for prim in primitives:
        coords = prim["coords"]
        texture = prim["texture"]
        colors = [(r / 255.0, g / 255.0, b / 255.0, a / 255.0) for r, g, b, a in prim["colors"]]

        if texture is not None:
            tex_w, tex_h = texture_size(texture)
            uvs = [(u / tex_w, v / tex_h) for u, v in prim["uvs"]]
        else:
            uvs = [(0.0, 0.0)] * len(coords)

        group = groups.setdefault(texture, {"positions": [], "uvs": [], "colors": []})

        def emit_tri(engine_order: tuple[int, int, int]) -> None:
            tri_positions = [world_vertices[coords[i]] for i in engine_order]
            tri_uvs = [uvs[i] for i in engine_order]
            tri_colors = [colors[i] for i in engine_order]
            for k in order:
                group["positions"].append(tri_positions[k])
                group["uvs"].append(tri_uvs[k])
                group["colors"].append(tri_colors[k])

        if len(coords) == 3:
            emit_tri(PRM_TRI3_ORDER)
        else:
            emit_tri(PRM_TRI4_ORDER_A)
            emit_tri(PRM_TRI4_ORDER_B)


def export_flat_textures(cmp_entries: list[bytes], texture_ids: set[int], out_dir: Path) -> dict[int, str]:
    """Writes one PNG per texture id actually used, decoded directly from a
    flat CMP list (SCENE.CMP/SKY.CMP/ALLSH.CMP/...; no tile assembly, unlike
    LIBRARY.CMP).
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    texture_files: dict[int, str] = {}
    for texture_id in sorted(texture_ids):
        width, height, pixels = parse_tim(cmp_entries[texture_id])
        filename = f"tex_{texture_id}.png"
        write_png(out_dir / filename, width, height, pixels)
        texture_files[texture_id] = filename
    return texture_files


def write_prm_obj(
    groups: dict,
    out_path: Path,
    texture_files: dict[int, str] | None,
    texture_subdir: str,
) -> None:
    """Writes a `groups` dict (from emit_prm_object_triangles) as OBJ+MTL.
    Untextured groups fall back to a flat averaged Kd (OBJ has no clean
    per-vertex color story like glTF's COLOR_0).
    """
    mtl_path = out_path.with_suffix(".mtl")
    lines = [f"mtllib {mtl_path.name}"]
    mtl_lines = []

    vertex_index = 1  # OBJ indices are 1-based
    for group_id in sorted(groups, key=lambda k: (k is None, k)):
        group = groups[group_id]
        positions, uvs, colors = group["positions"], group["uvs"], group["colors"]
        if not positions:
            continue

        mat_name = f"tex_{group_id}" if group_id is not None else "vertex_color"
        avg_color = tuple(sum(c[i] for c in colors) / len(colors) for i in range(3))
        mtl_lines.append(f"newmtl {mat_name}\nKd {avg_color[0]:.4f} {avg_color[1]:.4f} {avg_color[2]:.4f}")
        texture_filename = (texture_files or {}).get(group_id)
        if texture_filename:
            texture_path = f"{texture_subdir}/{texture_filename}" if texture_subdir else texture_filename
            mtl_lines.append(f"map_Kd {texture_path}")
        mtl_lines.append("")

        lines.append(f"g group_{mat_name}")
        lines.append(f"usemtl {mat_name}")

        for p in positions:
            lines.append(f"v {p[0]:.6f} {p[1]:.6f} {p[2]:.6f}")
        for uv in uvs:
            lines.append(f"vt {uv[0]:.6f} {uv[1]:.6f}")

        for tri in range(len(positions) // 3):
            a, b, c = (vertex_index + tri * 3 + k for k in range(3))
            lines.append(f"f {a}/{a} {b}/{b} {c}/{c}")
        vertex_index += len(positions)

    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    mtl_path.write_text("\n".join(mtl_lines), encoding="utf-8")


def write_prm_gltf(
    groups: dict,
    out_path: Path,
    texture_files: dict[int, str] | None,
    texture_subdir: str,
    generator: str = "psx_track_common.py",
) -> None:
    """Writes a `groups` dict (from emit_prm_object_triangles) as glTF, with
    per-vertex COLOR_0 in addition to any texture.
    """
    bin_path = out_path.with_suffix(".bin")
    buffer_bytes = bytearray()
    buffer_views = []
    accessors = []
    materials = []
    primitives = []
    images = []
    textures = []
    image_index_by_id: dict[int, int] = {}

    def push_floats(values: list[tuple[float, ...]], component_count: int, want_bounds: bool) -> int:
        offset = len(buffer_bytes)
        flat = [c for v in values for c in v]
        buffer_bytes.extend(struct.pack(f"<{len(flat)}f", *flat))
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(flat) * 4, "target": 34962})
        accessor = {
            "bufferView": len(buffer_views) - 1,
            "componentType": 5126,  # FLOAT
            "count": len(values),
            "type": {2: "VEC2", 3: "VEC3", 4: "VEC4"}[component_count],
        }
        if want_bounds:
            cols = list(zip(*values))
            accessor["min"] = [min(c) for c in cols]
            accessor["max"] = [max(c) for c in cols]
        accessors.append(accessor)
        return len(accessors) - 1

    for group_id in sorted(groups, key=lambda k: (k is None, k)):
        group = groups[group_id]
        positions, uvs, colors = group["positions"], group["uvs"], group["colors"]
        if not positions:
            continue

        pos_idx = push_floats(positions, 3, want_bounds=True)
        uv_idx = push_floats(uvs, 2, want_bounds=False)
        color_idx = push_floats(colors, 4, want_bounds=False)

        material: dict = {
            "name": f"tex_{group_id}" if group_id is not None else "vertex_color",
            "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1]},
        }
        texture_filename = (texture_files or {}).get(group_id)
        if texture_filename:
            if group_id not in image_index_by_id:
                uri = f"{texture_subdir}/{texture_filename}" if texture_subdir else texture_filename
                images.append({"uri": uri})
                textures.append({"source": len(images) - 1})
                image_index_by_id[group_id] = len(textures) - 1
            material["pbrMetallicRoughness"]["baseColorTexture"] = {"index": image_index_by_id[group_id]}
        materials.append(material)

        primitives.append(
            {
                "attributes": {"POSITION": pos_idx, "TEXCOORD_0": uv_idx, "COLOR_0": color_idx},
                "material": len(materials) - 1,
                "mode": 4,  # TRIANGLES
            }
        )

    gltf = {
        "asset": {"version": "2.0", "generator": generator},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": primitives}],
        "materials": materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"uri": bin_path.name, "byteLength": len(buffer_bytes)}],
    }
    if images:
        gltf["images"] = images
        gltf["textures"] = textures

    bin_path.write_bytes(bytes(buffer_bytes))
    out_path.write_text(json.dumps(gltf), encoding="utf-8")


# Format, axes, and import gotchas

## Mixed endianness

Not uniform across PSX assets:

| Data | Endian | Readers |
| --- | --- | --- |
| TRACK.TRV / TRF / TRS | big | `track.c` `get_i16()` / `get_i32()` |
| LIBRARY.TTF | big | same |
| LIBRARY.CMP header + TIM images | little | `image.c` `get_*_le()` |
| SCENE.PRM | big | object/scene parsers |
| SCENE.CMP / SKY.CMP | little | same as LIBRARY.CMP TIM |

Classic symptom: plausible but garbage TTF sub-tile indices (e.g. `65280`) then `IndexError` into CMP.

### LIBRARY.CMP

int32 image_count (LE), then image_count int32 sizes (LE), then **one** LZSS stream for all entries concatenated. Decompress once, slice by cumulative sizes.

### LIBRARY.TTF

42-byte entries (16× uint16 near + 4× uint16 med + 1× uint16 far), one per track texture id. `near[ty*4+tx]` indexes decompressed CMP entries to assemble 128×128 from a 4×4 grid of 32×32 TIM (`track_load()` in `track.c`).

### TIM

magic(4)+type(4, `& 0xF`: `0x2` 16bpp, `0x8` 4bpp paletted, `0x9` 8bpp paletted), optional palette, data_size(4), skip_x/skip_y, entries_per_row, rows, pixels. Color `0x0000` is always fully transparent. Track tiles use `transparent=false` so only literal 0x0000 texels go transparent.

## Axes and scale

Source engine +Y is down. Converters negate Y (Godot/glTF +Y up) and reverse winding. Default `(x,-y,z)` is a **reflection** (odd axis count). `--flip-z` is `(x,-y,-z)` (even count, rotation). Required for Track01 / Track02 / Track03 vs wipeout-rewrite (L/R swapped, ads backwards without it).

`DEFAULT_UNITS_PER_METER = 106.5` in `psx_track_common.py` (documented lap length / raw spline length). Override `--units-per-meter` or `1.0` for raw PSX units. Elevation cross-check ~33.3 (~3.2× gap, unresolved) — do not silently change scale mid-track.

**Same flags on geometry, sections, flags, and scenery** or mesh / curve / pads diverge.

## PRM scenery / sky (`parse_prm` in `psx_track_common.py`)

Flat back-to-back Object records. 144-byte header then vertices, skippable normals, variable primitives (`type i16` + `flag i16`).

PRM_TYPE (object.h, values start at 1): F3, FT3, F4, FT4, G3, GT3, G4, GT4, LF2 unused, TSPR, BSPR, LSF3, LSFT3, LSF4, LSFT4, LSG3, LSGT3, LSG4, LSGT4, SPLINE, INFINITE_LIGHT, POINT_LIGHT, SPOT_LIGHT.

Pad1 presence is inconsistent even within families (G3 has pad1, G4 does not; LSFT3/LSFT4/LSG3/LSGT3 no pad1 before color, LSGT4 does). Follow `object.c` switch, do not infer.

Verify: full-file parse lands at EOF; max texture index == CMP entry count − 1.

`rgba_from_u32(v)`: r=(v>>24), g=(v>>16), b=(v>>8); alpha **always 255** (low byte discarded).

SCENE.CMP / SKY.CMP are a **flat** list of standalone textures (unlike LIBRARY.CMP 4×4 assembly). Primitive `texture` is a 0-based index, no offset.

### Winding (`object_draw`)

Stored order is not draw order. Tris: `(coords[2], coords[1], coords[0])`. Quads: two tris `(c2,c1,c0)` then `(c2,c3,c1)`. Bake this **before** axis-flip winding correction.

Sprites (TSPR/BSPR), splines, lights: parse for alignment, no mesh.

C enums/structs may live outside the Godot workspace. Fetch `https://raw.githubusercontent.com/phoboslab/wipeout-rewrite/<local-commit-hash>/<path>` when local grep cannot see `#include`d definitions. Remote: `https://github.com/phoboslab/wipeout-rewrite.git`.

## Godot / tooling

- Fresh `class_name` can be unresolved during validation; prefer `const Foo = preload("res://...")` in touched scripts.
- Do not parallel-edit the same file (duplicated GDScript blocks).
- After Godot generates files, `file_search`/`grep` can miss them; `read_file` / `list_dir` the path.
- `str(value)` not `String(value)` in GDScript validators.
- Some warnings are fatal in headless; `var x := max(...)` may infer Variant — use `maxi`/`maxf` or explicit types.
- Do not type-annotate helper params with scripts that lack `class_name`.
- PowerShell `$ErrorActionPreference = 'Stop'` can promote Godot stderr (`ObjectDB instances leaked`) to terminating errors; use `Continue` around native Godot if `$LASTEXITCODE` is already checked.
- `--import` required before UIDs exist on brand-new assets.
- Prefer a driver that awaits N `physics_frame`s then `quit(0)` over killing a long headless run.
- `file_search`/`grep_search` are workspace-scoped; sibling `wipeout/` C sources need absolute `read_file` / `list_dir`.

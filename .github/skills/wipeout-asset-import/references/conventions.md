# Shared format / axis conventions (non-track)

Same rules as the track pipeline. Break them and ships/weapons will not sit in the same world as `Track_NN`.

## Endianness

| Data | Endian |
| --- | --- |
| PRM (ALLSH, ALCOL, ROCK, …) | big |
| CMP header + TIM pixels (`ALLSH.CMP`, `TEXTURES/*.cmp`, `*.tim`) | little |

Symptom of mix-up: garbage texture indices / `IndexError`.

## Axes and scale

C +Y is down. Converters negate Y. **`--flip-z` → `(x,-y,-z)`** (even axis count = rotation). Without it: `(x,-y,z)` = reflection.

- `import_ships.py`: `--flip-z` **on by default**; `--no-flip-z` diagnostic only.
- `convert_common.py`: **must pass `--flip-z`** (flag is opt-in).
- `DEFAULT_UNITS_PER_METER = 106.5` in `psx_track_common.py`.

## Local vs baked origin

| Asset | Origin |
| --- | --- |
| Track scenery / sky (other skill) | baked into vertices |
| Ships, weapons, droid, menu PRM | **local** — `object_draw()` applies live transform |

Do not bake ship/weapon origin “to match scenery”.

## PRM winding (`object_draw`)

Tris: `(c2,c1,c0)`. Quads: `(c2,c1,c0)` then `(c2,c3,c1)`. Baked before axis-flip winding correction. Pad1 is inconsistent per primitive type — follow `object.c`, do not infer.

`rgba_from_u32`: RGB from high bytes; alpha always 255.

Sprites / splines / lights: parsed, not meshed.

## CMP kinds

| Kind | Files | Tool |
| --- | --- | --- |
| Flat TIM list | `TEXTURES/*.cmp`, `ALLSH.CMP`, `MINE.CMP`, `SCENE.CMP` | `parse_cmp` / `convert_textures.py` |
| Tiled 4×4 | `LIBRARY.CMP` + `LIBRARY.TTF` | **track** converters only |

TIM `0x0000` is always transparent. Semi-trans stems for HUD: `shad1`–`shad4`, `target2` (see textures.md).

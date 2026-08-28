# 2D textures — TEXTURES TIM / flat CMP

Long form: `docs/.transactional/26-08-27-01/documentation/workflow_import_textures.md`.

Not track tiles (`LIBRARY.CMP`+TTF).

## Sources

`wipeout/TEXTURES/`: standalone `.TIM` (`image_get_texture` / `_semi_trans`) and flat `.CMP` (same as `SCENE.CMP`: LE count + sizes + one LZSS stream).

Priority files the C actually loads:

| File | Consumer |
| --- | --- |
| `wipeout1.tim` | main menu bg |
| `wiptitle.tim` | title |
| `speedo.tim` | HUD — **128×32** |
| `target2.tim` | HUD / weapons — semi-trans |
| `shad1.tim` … `shad4.tim` | ship shadows — semi-trans |
| `dekka.cmp` `chang.cmp` `arial.cmp` `anast.cmp` `solar.cmp` `arian.cmp` `sophi.cmp` `paul.cmp` | `def.pilots[].portrait` (often 2 images) |
| `track.cmp` | circuit thumbs |
| `drfonts.cmp` | UI fonts (glyph sheet, not `FontFile`) |

## Tool

`godot/tools/psx_track/convert_textures.py` (stdlib only).

- TIM → one PNG.
- CMP → `<stem>/<stem>_00.png`, `_01.png`, …
- Default transparent: TIM `0x0000` always. Semi-trans bit forced for stems `shad1`–`shad4` and `target2` unless `--opaque` / `--transparent`.

Never point this at `LIBRARY.CMP`.

## Run

Whole folder into Godot:

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_textures.py `
  D:\code\wipeout-rewrite\wipeout\TEXTURES `
  D:\code\wipeout-rewrite\godot\src\assets\ui
```

Single file:

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_textures.py `
  D:\code\wipeout-rewrite\wipeout\TEXTURES\speedo.tim `
  D:\code\wipeout-rewrite\godot\src\assets\ui\speedo.png
```

Menus (`MainMenu.tscn`, `PilotMenu.tscn`) are still text/buttons. Copying PNG does **not** wire UI unless the user asked.

Then Godot `--import`.

## Checks

- Log `TIM WxH`. `speedo.tim` → 128×32.
- CMP count > 0; a bad TIM entry is **skipped** (`skip stem[i]`); others still written.
- Two portrait frames is not a bug.
- Rainbow noise → endianness (must stay LE via `parse_tim`).

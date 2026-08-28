# Audio — WIPEOUT.VB + music MP3

Long form: `docs/.transactional/26-08-27-01/documentation/workflow_import_audio.md`.

Godot 4 imports WAV and MP3. C plays `.qoa`; copy the sibling `.mp3`.

## Sources

| File | C | Export |
| --- | --- | --- |
| `wipeout/SOUND/WIPEOUT.VB` | `sfx_load()` | 30 WAV named from `sfx.h` |
| `wipeout/SOUND/WIPEOUT.VH` | **unread** | ignore |
| `wipeout/music/track01.qoa` … `track11.qoa` | `sfx_music_play()` | do not copy (no QOA decoder) |
| `wipeout/music/track01.mp3` … `track11.mp3` | twins of QOA | renamed per `game.c` |

Mix is 44100 Hz. `sfx_get_node()`: pitch `0.5` for index `< SFX_VOICE_MINES` (content 22050), pitch `1.0` for voices. Export WAV at **content rate** so Godot needs no `pitch_scale`.

Voices (20–29) 44100: `voice_mines` … `voice_count_go`. All earlier names 22050 (`crunch`, engines, menu, weapons, …).

Music dest names: `cairodrome`, `cardinal_dancer`, `cold_comfort`, `doh_t`, `messij`, `operatique`, `tentative`, `trancevaal`, `afro_ride`, `chemical_beats`, `wipeout` (from `track01`…`track11`).

## Run

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_audio.py
```

Writes `godot/src/assets/music/*.mp3` and `godot/src/assets/sfx/*.wav`.

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_audio.py --music-only
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_audio.py --sfx-only
```

Scratch decode:

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_sfx.py `
  D:\code\wipeout-rewrite\wipeout\SOUND\WIPEOUT.VB `
  D:\code\wipeout-rewrite\_converted_tracks\sfx_probe
```

Do **not** pass `--mix-rate` for Godot (forces 44100 on every source).

VAG: 16-byte ADPCM blocks; `VAG_REGION_END` opens a source, `VAG_REGION_START` closes it. Blocks **before the first END** update ADPCM history but are **not** stored (matches C).

## Wiring

`WipeoutShip.tscn` `WallImpactSFX` / `ShipImpactSFX`: `crunch.wav` (`SFX_CRUNCH`). Copying files does not play music or menu voices until nodes exist. Do not invent an audio bus layout unless asked.

## Checks

- `Decoded 30 VAG region(s)`
- `crunch.wav` ~0.66 s @ 22050; `voice_count_go.wav` ~0.90 s @ 44100
- 11 MP3 with `game.c` names, not `track01.mp3`

Out of scope: `intro.mpeg`; re-encoding QOA; Doppler (C mix-time).

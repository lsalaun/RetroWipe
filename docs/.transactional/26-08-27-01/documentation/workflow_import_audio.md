# Workflow d'import audio (SOUND + music → Godot)

Documentation opérationnelle pour les SFX VAG et la bande-son. Godot 4 importe nativement WAV et MP3. Le C joue le `.qoa` ; on copie le `.mp3` jumeau pour le port.

Python = `py`.

---

## 1. Sources PSX

| Fichier | Consommateur C | Export |
| --- | --- | --- |
| `wipeout/SOUND/WIPEOUT.VB` | `sfx_load()` dans `src/wipeout/sfx.c` | 30 WAV, un par `sfx_source_t` (`sfx.h`) |
| `wipeout/SOUND/WIPEOUT.VH` | **non lu** | ignoré |
| `wipeout/music/track01.qoa` … `track11.qoa` | `sfx_music_play()` | non copiés (Godot n'a pas de décodeur QOA) |
| `wipeout/music/track01.mp3` … `track11.mp3` | jumeaux des QOA | MP3 renommés d'après `def` musique dans `game.c` |

Le mixage C est à **44100 Hz**. `sfx_get_node()` : pitch `0.5` pour tout index `< SFX_VOICE_MINES` (contenu 22050 Hz), pitch `1.0` pour les voix. L'export écrit le WAV au **taux de contenu** pour que Godot joue juste sans `pitch_scale`.

Noms exportés (ordre `sfx.h`) :

| Index | Fichier | Taux |
| --- | --- | --- |
| 0 | `crunch.wav` | 22050 |
| 1 | `ebolt.wav` | 22050 |
| 2–4 | `engine_intake.wav` `engine_rumble.wav` `engine_thrust.wav` | 22050 |
| 5–7 | `explosion_1.wav` `explosion_2.wav` `impact.wav` | 22050 |
| 8–10 | `menu_move.wav` `menu_select.wav` `menu_transition.wav` | 22050 |
| 11–19 | `mine_drop` `missile_fire` `engine_remote` `powerup` `shield` `siren` `tractor` `turbulence` `crowd` | 22050 |
| 20–29 | `voice_mines` … `voice_count_go` | 44100 |

Musique (`game.c`) :

| Source | Destination Godot |
| --- | --- |
| `track01.mp3` | `godot/src/assets/music/cairodrome.mp3` |
| `track02.mp3` | `cardinal_dancer.mp3` |
| `track03.mp3` | `cold_comfort.mp3` |
| `track04.mp3` | `doh_t.mp3` |
| `track05.mp3` | `messij.mp3` |
| `track06.mp3` | `operatique.mp3` |
| `track07.mp3` | `tentative.mp3` |
| `track08.mp3` | `trancevaal.mp3` |
| `track09.mp3` | `afro_ride.mp3` |
| `track10.mp3` | `chemical_beats.mp3` |
| `track11.mp3` | `wipeout.mp3` |

---

## 2. Outils

| Script | Rôle |
| --- | --- |
| `godot/tools/psx_track/import_audio.py` | Copie les 11 MP3 + décode le VB vers `godot/src/assets/` |
| `godot/tools/psx_track/convert_sfx.py` | VB → WAV uniquement (scratch ou destination custom) |

Décodage VAG : blocs 16 octets (header + flags + 14 octets de nibbles), table `vag_tab` de `sfx.c`. `VAG_REGION_END` ouvre une source, `VAG_REGION_START` la ferme. Les blocs **avant le premier END** sont décodés pour l'historique ADPCM mais **pas** stockés (comme le C).

---

## 3. Commandes

Tout (musique + SFX) vers le projet :

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_audio.py
```

Écrit :

- `godot/src/assets/music/*.mp3`
- `godot/src/assets/sfx/*.wav`

Uniquement l'un ou l'autre :

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_audio.py --music-only
py D:\code\wipeout-rewrite\godot\tools\psx_track\import_audio.py --sfx-only
```

SFX vers un scratch :

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_sfx.py `
  D:\code\wipeout-rewrite\wipeout\SOUND\WIPEOUT.VB `
  D:\code\wipeout-rewrite\_converted_tracks\sfx_probe
```

`--mix-rate` sur `convert_sfx.py` force 44100 Hz pour **toutes** les sources (désaccordé par rapport au C pour les SFX non-voix). Ne pas l'utiliser pour un import Godot normal.

Contrôle attendu : `Decoded 30 VAG region(s)`, `crunch.wav` ≈ 0.66 s @ 22050 Hz, `voice_count_go.wav` ≈ 0.90 s @ 44100 Hz.

Réimport headless ensuite :

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src --import
```

---

## 4. Câblage Godot

`WipeoutShip.tscn` / `WipeoutShipAI.tscn` ont déjà `WallImpactSFX` et `ShipImpactSFX` (`AudioStreamPlayer3D`) avec exports vides :

- mur → `crunch.wav` (C : `SFX_CRUNCH`)
- vaisseau-vaisseau → à brancher selon le hit (`SFX_CRUNCH` aussi dans `ship.c`, gated 0.2 s)

Les voix d'armes / countdown / menu n'ont pas encore de nœuds audio. `OptionsAudioMenu` ne gère qu'un volume master (pas de bus music/sfx séparés).

La musique n'est lue par aucune scène pour l'instant : copier les MP3 ne les fait pas jouer.

---

## 5. Limites

- `intro.mpeg` (vidéo + MP2) hors scope.
- QOA non réexporté : le MP3 du dump est la source Godot.
- Pas de spatialisation / Doppler à l'import (le C le fait au mixage).

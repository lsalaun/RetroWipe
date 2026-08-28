# Workflow d'import des textures 2D (TEXTURES → PNG)

Documentation opérationnelle pour `wipeout/TEXTURES` (et CMP/TIM isolés de `COMMON`). Ce n'est **pas** le pipeline des tuiles de piste (`LIBRARY.CMP` + `LIBRARY.TTF`, voir [workflow_import_circuit.md](workflow_import_circuit.md)).

Python = `py`. Stdlib uniquement (pas de Pillow).

---

## 1. Sources PSX

`wipeout/TEXTURES/` mélange :

- **`.TIM`** autonomes — une image (HUD, title, ombres, reticles). Lues par `image_get_texture()` / `image_get_texture_semi_trans()` (`src/wipeout/image.c`). En-tête + pixels **little-endian**.
- **`.CMP`** — liste plate de TIM (même format que `SCENE.CMP` / `ALLSH.CMP`) : `int32` LE `image_count`, tailles, **un** flux LZSS pour toutes les entrées. Chaque entrée = une TIM complète. Pas d'assemblage 4×4.

Fichiers C réellement chargés (liste non exhaustive, pour prioriser) :

| Fichier | Consommateur C | Notes |
| --- | --- | --- |
| `wipeout1.tim` | `main_menu.c` fond | |
| `wiptitle.tim` | `title.c` | |
| `speedo.tim` | `hud.c` | Vérifié : 128×32 |
| `target2.tim` | HUD + armes | semi-trans |
| `shad1.tim` … `shad4.tim` | `ship.c` ombres | semi-trans |
| `dekka.cmp` `chang.cmp` `arial.cmp` `anast.cmp` `solar.cmp` `arian.cmp` `sophi.cmp` `paul.cmp` | `def.pilots[].portrait` | CMP 2 images (ex. Dekka) |
| `track.cmp` | miniatures circuits menu | |
| `drfonts.cmp` | `ui.c` polices | |

Le reste du dossier (loads, legal, win/lose, …) peut être converti en masse ; Godot ne les référence pas encore.

---

## 2. Outil

`godot/tools/psx_track/convert_textures.py`

- TIM → un PNG.
- CMP → un sous-dossier `<stem>/` avec `<stem>_00.png`, `_01.png`, …
- `parse_tim(..., transparent=)` : couleur `0x0000` toujours transparente. Le bit semi-trans TIM n'est forcé que pour les stems `shad1`–`shad4` et `target2` (équivalent `image_get_texture_semi_trans()`), sauf `--transparent` / `--opaque`.

Ne **pas** pointer ce script sur `LIBRARY.CMP` (tuiles de piste) : mauvais assembleur.

---

## 3. Commandes

Dossier entier vers le projet Godot :

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_textures.py `
  D:\code\wipeout-rewrite\wipeout\TEXTURES `
  D:\code\wipeout-rewrite\godot\src\assets\ui
```

Fichier unique :

```powershell
py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_textures.py `
  D:\code\wipeout-rewrite\wipeout\TEXTURES\speedo.tim `
  D:\code\wipeout-rewrite\godot\src\assets\ui\speedo.png

py D:\code\wipeout-rewrite\godot\tools\psx_track\convert_textures.py `
  D:\code\wipeout-rewrite\wipeout\TEXTURES\dekka.cmp `
  D:\code\wipeout-rewrite\godot\src\assets\ui
```

Le CMP écrit `godot/src/assets/ui/dekka/dekka_00.png`, `dekka_01.png`, …

Forcer le bit transparent / l'opaque :

```powershell
py ...\convert_textures.py wipeout\TEXTURES\shad1.tim out\shad1.png --transparent
py ...\convert_textures.py wipeout\TEXTURES\speedo.tim out\speedo.png --opaque
```

Après copie, réimport headless pour obtenir des UID :

```powershell
d:\Godot_4\Godot_v4.6.1-stable_win64_console.exe --headless --path D:\code\wipeout-rewrite\godot\src --import
```

Les menus Godot (`MainMenu.tscn`, `PilotMenu.tscn`, …) sont encore du texte/boutons : brancher les PNG est une étape runtime séparée.

---

## 4. Contrôles

- TIM : log `TIM WxH`. `speedo.tim` → 128×32.
- CMP : nombre d'images > 0 ; une entrée TIM pourrie est **sautée** (`skip stem[i]: …`), les autres sont écrites.
- Portraits : 2 frames n'est pas un bug (palette / lod PSX).
- Si le PNG est du bruit coloré : endianness TIM (doit rester LE via `parse_tim`).

---

## 5. Limites

- Pas de conversion des `.TEX` de piste (`LIBRARY.TEX`, `ICONS.TEX`) : artefacts tooling, pas lus par le moteur.
- `VRAM.TIM` / dumps plein écran : convertibles mais inutiles en jeu.
- Polices `drfonts.cmp` : feuilles de glyphes, pas une `FontFile` Godot.

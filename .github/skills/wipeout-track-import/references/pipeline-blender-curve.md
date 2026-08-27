# Pipeline B — Blender racing line (Track12-style)

Use when the AI line is **not** extracted from `TRACK.TRS` but from a `.blend` Curve (historical Track12: mesh and curve independent).

## Never glTF the curve

A Blender Curve with `bevel_depth=0` / `extrude=0` exports as an empty Node3D (0 mesh, 0 accessors). Godot creates neither Path3D nor geometry. Confirmed via `blender --background file.blend --python inspect.py`.

Bypass glTF. Sample the spline in Blender and write JSON for `track_center_line.gd`.

## Export

```powershell
blender --background chemin\vers\track_curve.blend --python D:\code\wipeout-rewrite\godot\tools\blender\export_track_curve.py -- `
  D:\code\wipeout-rewrite\godot\src\assets\tracks\Track_NN\track_NN_curve.json `
  16
```

- 2nd extra arg: samples per Bezier segment (default 16)
- 3rd extra arg (optional): Curve object name if several curves exist
- Axes: Blender Z-up → Godot Y-up `(x, y, z) → (x, z, -y)`
- `BEZIER`: sampled via `mathutils.geometry.interpolate_bezier` (respects `use_cyclic_u`)
- `POLY`: raw points; Godot synthesizes handles on reimport
- JSON includes ordered `points` + `closed` (`Curve3D.closed` in Godot 4.6)

Script: `godot/tools/blender/export_track_curve.py`.

## Inverse inspect (JSON → .blend)

```powershell
blender --background --python D:\code\wipeout-rewrite\godot\tools\blender\import_track_curve.py -- `
  track_NN_curve.json track_NN_curve.blend TrackCenterLine
```

## ShipSpawn height

Do **not** use `point0.y + 2.0`. That constant is only valid for curves from `convert_track_sections.py` (real elevation baked from TRACK.TRS).

For Blender-authored curves, raycast or measure against the track mesh. Track12: offset ≈ 3.14 m with curve y = 0.0.

# Godot scene wiring (`TrackNN.tscn`)

Reference scenes: `godot/src/scenes/Track01.tscn`, `Track02.tscn`. New circuits follow the same **scene** name: `Track03.tscn` (no underscore). Asset folders stay `Track_03/` (underscore).

## Tree

```text
TrackNN (Node3D + TrackMeshCollider)
├── TrackMesh          instance of Track_NN_mesh.glb
├── Scenery            instance of Track_NN_scene.glb   (visual only)
├── Sky                instance of Track_NN_sky.glb     (visual only)
├── CenterLine         Path3D + track_center_line.gd
│                      source_json = res://assets/tracks/Track_NN/track_NN_curve.json
├── GameplayZones      Node3D + track_gameplay_zones.gd
│                      source_json = res://assets/tracks/Track_NN/track_NN_face_flags.json
└── ShipSpawn          Marker3D
```

UIDs in `ext_resource` must match `*.glb.import` **after** `godot --headless --path godot/src --import`. Updating `path=` with a stale UID still loads the old asset.

`.tscn` node headers are metadata only. Put `visible = false` on a following property line, not in `[node ...]`.

## Runtime scripts

| Script | Role |
| --- | --- |
| `godot/src/scripts/track_center_line.gd` | Loads curve JSON into Path3D / Curve3D in `_ready()`. If Curve3D already populated in editor, JSON is not re-read. |
| `godot/src/scripts/track_mesh_collider.gd` | Only `TrackMesh` (`track_mesh_path` default). Per MeshInstance3D: StaticBody3D + CollisionShape3D via `create_trimesh_shape()`, `shape.backface_collision = true`, materials duplicated with `CULL_DISABLED`. |
| `godot/src/scripts/track_gameplay_zones.gd` | `_ready()`: `boost_pads` → TrackBoostPad Area3D (one-shot impulse); `pickup_pads` / `start_grid` → Marker3D (anchors only). |
| `godot/src/scripts/track_boost_pad.gd` | Speed impulse on pad contact. |

Never convex-decompose edge shelves / side walls: inflated hulls false-trigger wall contacts in the lane.

## ShipSpawn — TRS curves (`convert_track_sections.py`)

Yaw-only (no pitch/roll) from the **first two** JSON points:

1. `forward = normalize((p1.x - p0.x, 0, p1.z - p0.z))` — ignore Δy for orientation.
2. `basis.z = -forward`, `basis.y = (0, 1, 0)`, `basis.x = UP.cross(basis.z)`.
3. Origin XZ = p0.xz exactly; **Y = p0.y + 2.0** (hover clearance). Valid only because TRS conversion bakes real section altitude.

Always reproduce Track01's published `Transform3D` from **Track01's** JSON before trusting a new track.

Blender-curve tracks: do not use +2.0; raycast against mesh (see pipeline-blender-curve.md).

## `Transform3D` literal (critical)

Godot `.tscn` `Transform3D(a,b,c, d,e,f, g,h,i, ox,oy,oz)` is **row-major**.

Given `basis.x=(x1,x2,x3)`, `basis.y=(y1,y2,y3)`, `basis.z=(z1,z2,z3)`:

```text
Transform3D(x1, y1, z1,  x2, y2, z2,  x3, y3, z3,  ox, oy, oz)
```

Writing columns as consecutive triples produces the **transpose** (inverse of a rotation). A ~45° intended heading often shows as ~90° error. Empirical: `Transform3D(1,2,3, 4,5,6, 7,8,9, ...)` loads `basis.x = (1,4,7)`.

Do not round the basis to 5 decimals: Godot 4.6 requires a normalized Basis (`get_rotation_quaternion()` in `wipeout_ship.gd` `_physics_process` will throw). Emit ≥12 invariant decimals (decimal point, not FR comma). PowerShell:

```powershell
[double].ToString("F12", [System.Globalization.CultureInfo]::InvariantCulture)
```

Prefer computing + printing the basis with a probe script over hand-transcribing.

`basis.y` must be exactly `(0, 1, 0)` for yaw-only spawns.

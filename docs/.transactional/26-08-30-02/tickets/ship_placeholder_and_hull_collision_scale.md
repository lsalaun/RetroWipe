# Ship Placeholder Scale & Configurable Hull Collision Size

**Date:** 2026-08-30  
**Status:** Complete  
**Scope:** Resize the placeholder ship mesh to match the imported ALLSH ship models; make the ship-vs-ship hull collision box size configurable and shrink it by default

---

## Overview

Two related ship-sizing issues came up while reviewing `WipeoutShip.tscn`:

1. The placeholder debug box (`BodyMesh`) shown when no real `.glb` is assigned
   (direct scene boot, no pilot selected) was much smaller than the real
   imported ship meshes, making it look like the ship-vs-ship collision box
   was oversized when it was actually just being compared against the wrong
   reference.
2. Once the placeholder was corrected, the `HullArea` box used for
   ship-vs-ship collisions (deliberately sized from the original game's
   `ALCOL.PRM` hull data) still visibly overshoots the hull. Rather than
   diverge from the measured original data outright, it was made a
   configurable multiplier defaulting to a 10% reduction.

---

## Investigation

### Placeholder mesh vs. real mesh vs. collision boxes

Measured the real imported ship AABBs headlessly:

```powershell
Godot_v4.6.1-stable_win64_console.exe --headless --path src `
  -s res://tools/inspect_scene.gd -- res://assets/ships/sophia/sophia.glb
Godot_v4.6.1-stable_win64_console.exe --headless --path src `
  -s res://tools/inspect_scene.gd -- res://assets/ships/chang/chang.glb
```

| Source | Size (X, Y, Z) |
| --- | --- |
| `sophia.glb` (FEISAR) | `3.399, 1.540, 7.981` |
| `chang.glb` (AG Systems) | `3.437, 1.559, 7.812` |
| `BoxShape3D_1` (root wall collision, unchanged) | `3.4, 1.5, 7.9` |
| `BodyMesh` placeholder (before) | `1.8, 0.45, 3.6` |
| `HullArea` box (ship-vs-ship, from `ALCOL.PRM`) | `4.23, 1.05, 8.45` |

The root wall `CollisionShape3D` already matched the real mesh almost
exactly. Only the visual placeholder was undersized. `HullArea` is
intentionally larger than the visible hull because it is measured from the
original `ALCOL.PRM` collision data (see `ship_collision_manager.gd` and
`validate_ship_collision.gd`), not guessed — this was confirmed correct as
originally implemented, not a bug.

---

## Changes

### 1. Placeholder `BodyMesh` resized to match the real ship meshes

`src/scenes/WipeoutShip.tscn` and `src/scenes/WipeoutShipAI.tscn`:

```diff
 [sub_resource type="BoxMesh" id="BoxMesh_1"]
-size = Vector3(1.8, 0.45, 3.6)
+size = Vector3(3.4, 1.5, 7.9)
```

`Canopy`'s transform (child of `BodyMesh`) was scaled by the same per-axis
ratios (`1.889`, `3.333`, `2.194`) so it keeps its original relative size and
position on the larger placeholder body instead of looking buried or
floating.

This incidentally now matches `BoxShape3D_1`, the existing wall-collision
box, so the placeholder box lines up visually with that collision shape too.

### 2. Configurable `hull_collision_scale` for ship-vs-ship collision

`src/scripts/wipeout_ship.gd`:

- Added `@export var hull_collision_scale: float = 0.9` — multiplies the
  `HullArea` hitbox (measured from `ALCOL.PRM`) so ship-vs-ship contact hugs
  the visible hull more closely, while keeping the option to set it back to
  `1.0` (raw measured size) or tune it per ship in the inspector.
- Added `_apply_hull_collision_scale()`, called from `_ready()`, which
  duplicates the `HullCollisionShape3D`'s `BoxShape3D` before scaling it.

`wipeout_ship_ai.gd` extends `WipeoutShip`, so AI ships pick up the same
export and behavior for free.

#### Why duplicate the shape resource

The `BoxShape3D` embedded in the `.tscn` is a single `Resource` object shared
across every instance of that scene — Godot only duplicates an embedded
sub_resource per instance when it is flagged `local_to_scene`, which this one
is not. Mutating `.size` in place would have shrunk (or, on a second
`_ready()`, re-shrunk) every ship's hull box at once instead of just the
instance being configured. `_apply_hull_collision_scale()` duplicates the
shape first so each ship gets its own independent resource.

### 3. `validate_ship_collision.gd` updated for the new default

The test asserted the hull box was exactly `Vector3(4.23, 1.05, 8.45)`. With
`hull_collision_scale` defaulting to `0.9`, the live box is smaller than
that, so the test now compares against `MEASURED_HULL_SIZE *
hull_collision_scale` (read from the instantiated ship) instead of the raw
measured constant, and the nose/side overlap placement offsets scale the
same way.

---

## Validation

```powershell
Godot_v4.6.1-stable_win64_console.exe --headless --path src `
  -s res://tools/validate_ship_collision.gd
Godot_v4.6.1-stable_win64_console.exe --headless --path src `
  -s res://tools/validate_ship_impact.gd
```

Both report `OK`. Also loaded `WipeoutShip.tscn` headlessly via
`inspect_scene.gd` to confirm the `BodyMesh` AABB is now `(3.4, 1.5, 7.9)`,
matching the real ship meshes.

---

## Not Changed

- The root wall `CollisionShape3D` (`BoxShape3D_1`) and `HullPenetrationProbe`
  shape are untouched.
- The measured `ALCOL.PRM` hull size itself (`MEASURED_HULL_SIZE` /
  `4.23, 1.05, 8.45`) is untouched — only multiplied by the new configurable
  factor, which defaults to `0.9`.
- Real ship model loading (`ship_model_scene` / `set_ship_model()`) is
  unaffected; this only changes the fallback placeholder and the ship-vs-ship
  hitbox.

---

## Files Modified

- `src/scenes/WipeoutShip.tscn`
- `src/scenes/WipeoutShipAI.tscn`
- `src/scripts/wipeout_ship.gd`
- `src/tools/validate_ship_collision.gd`
- `docs/.transactional/26-08-30-02/tickets/ship_placeholder_and_hull_collision_scale.md`

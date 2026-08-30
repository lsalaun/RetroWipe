# AI Start Grid Positions: ship.c → Godot

**Date:** 2026-08-30
**Status:** Complete (code), pending in-editor visual verification
**Scope:** Fix the 8-ship starting grid to match `ships_init()`/`ship_init()`'s real section-based stagger

---

## Overview

An audit comparing `WipeoutShipAI`/`race_field.gd`'s starting-grid placement against
`src/wipeout/ship.c`'s `ships_init()` and `ship_init()` found that the grid was not just
too compact, but anchored and oriented backwards relative to the original:

1. **Wrong anchor.** `ShipSpawn` (the scene marker used to place the grid) is exported at
   TRACK.TRS section `start_line_pos - 15` — which `ship_init()` uses as `start_sections[0]`,
   the section handed to `inv_start_rank == 0`, i.e. **the player's own (last-place) grid
   slot**. The previous Godot code anchored grid slot 0 (pole, strongest AI) at that marker
   instead, with the player offset away from it — i.e. pole and last place were swapped
   relative to the marker.
2. **Wrong direction.** The previous table stepped the player *behind* the marker. The
   original instead builds every other grid slot *ahead* of the player's section, walking
   forward along the section chain.
3. **Wrong magnitude.** The stagger was a fixed 2 m per slot (14 m pole-to-back total). The
   original advances by whole TRACK.TRS sections in a non-uniform `2,1,2,1,2,1,2` pattern
   (`ships_init()`'s `if ((i % 2) == 0) section = section->next;`), and one section is
   ~14–17 m on the imported tracks (see `wipeout_ship_ai.gd`'s `SECTION_LENGTH_FALLBACK`
   comment) — an 11-section, ~150–190 m span from pole to back, roughly 12× longer than
   the previous 14 m table.
4. **Straight-line extrapolation.** The previous code applied the offset via
   `spawn.global_transform.translated_local(...)`, a fixed local-space translation that
   ignores track curvature. Over ~150–190 m this would place forward grid slots off the
   actual racing surface on any track that curves near the start.

A secondary documentation bug was found in the same file: the `AI_SETTINGS` table comment
claimed index 0 was the strongest entry (front of grid), when the data and the lookup
(`inv_start_rank - 1`) actually hand index 0 to the weakest AI (the slot right in front of
the player) and index 6 to the pole-position AI.

What was **not** wrong: the ordering logic itself (which roster slot is pole, which is
last, which `AI_SETTINGS` row each slot's stats come from) was already equivalent to the
original — only the physical placement math was off.

---

## Changes by File

### `src/scripts/race_field.gd`

**Replaced the static offset table**
- Removed `GRID_OFFSETS: Array[Vector3]` (8 fixed local offsets, pole at the marker, player
  14 m behind in 2 m steps)
- Added `GRID_SECTION_OFFSETS: Array[float] = [11.0, 9.0, 8.0, 6.0, 5.0, 3.0, 2.0, 0.0]` —
  sections *forward* of `ShipSpawn` for grid slots 0 (pole) through 7 (player), derived
  directly from `ships_init()`'s stagger loop reversed by `rank_inv = 7 - i`
- Added `GRID_LATERAL_OFFSET := 1.8` (unchanged magnitude, same alternating left/right
  convention as before — not derived from real per-section track-face width like the
  original, flagged as a remaining approximation)
- Added `GRID_HOVER_CLEARANCE := 2.0`, matching `compute_ship_spawn.py`'s
  `HOVER_CLEARANCE_M`, needed because `place_ship()` now samples the raw curve instead of
  reusing the marker's own (already hover-raised) Y

**Rewrote `place_ship()`**
- New signature: `place_ship(ship, spawn, center_line, spawn_offset, grid_index)`
- Walks `center_line`'s `Curve3D` from `spawn_offset` by `GRID_SECTION_OFFSETS[grid_index] *
  section_length_meters`, so forward slots follow actual track curvature instead of a
  straight-line projection
- Builds the ship's transform from the curve tangent at that point (forward/right/up),
  applying the lateral lane offset perpendicular to the real tangent, not the marker's fixed
  axes
- Falls back to the old straight-line-from-marker behavior only when `center_line` has no
  usable curve (e.g. a track missing that data)
- Added `_section_length_meters(curve)`: `baked_length / point_count`, the same derivation
  already used independently in `wipeout_ship_ai.gd`

**Comment fix**
- `AI_SETTINGS` header comment corrected: index 0 is the weakest entry (front-of-player
  slot), index 6 the strongest (pole), not the reverse as previously stated

### `src/scripts/main.gd`

- Added `_spawn_offset(center_line, track_scene)`: computes `ShipSpawn`'s own curve offset
  from its TRACK.TRS section index (`start_line_pos - SPAWN_SECTION_OFFSET`), the same
  pattern already used by the existing `_start_line_offset()`, rather than resolving it
  spatially from the marker's world position (which sits 2 m higher due to hover clearance)
- Threaded `center_line` and the new `spawn_offset` through both `place_ship()` call sites
  (time trial's solo placement and the per-ship loop for a full race)

---

## Test Results

No Godot executable was available in this environment to run `validate_ai_field.gd` or
launch the race scene, so this change has **not** been exercised in the editor. The GDScript
was reviewed manually for type/signature consistency across all call sites (`main.gd`,
`race_field.gd`); no other file references the old `GRID_OFFSETS` constant or the old
4-argument `place_ship()` signature.

**Follow-up needed:** run `validate_ai_field.gd` and/or start a race in-editor to confirm:
- the player spawns at `ShipSpawn`'s own position (not offset from it)
- the 7 AI ships spread out ahead of the player along the track, following any curve near
  the start, spanning roughly 150–190 m pole-to-back (track-dependent)
- no ship spawns off the track surface or clipped into a wall on a track that curves within
  that span

---

## Not Changed (Intentional)

**Lateral (left/right) offset magnitude**
- Still a fixed ±1.8 m, alternating by slot parity, matching the *pattern* of the original's
  odd/even `inv_start_rank` face pick but not its *magnitude*, which the original derives
  from the real width of the two track faces adjacent to each section
- Real per-section track-face width isn't currently exported; deriving it would need either
  new export data or a runtime probe (as `wipeout_ship_ai.gd`'s `_measure_half_width()`
  already does for the AI's racing line) — left as a possible follow-up, not attempted here
  since the primary, quantified divergence was the longitudinal placement

---

## Impact on Gameplay

1. **Correct start order relative to track geometry**: the player now starts exactly at the
   grid's true back marker instead of ahead of it, and AI ships spread out ahead in the real
   pole → back order instead of behind a mispositioned "pole" anchor
2. **Curve-safe placement**: grid slots on the far side of a start-area curve no longer risk
   spawning off the racing surface
3. **Realistic grid depth**: ~150–190 m pole-to-back (track-dependent) instead of 14 m,
   matching the original's section-based stagger

---

## Files Modified

- `src/scripts/race_field.gd` (grid offset table, `place_ship()`, `AI_SETTINGS` comment)
- `src/scripts/main.gd` (`_spawn_offset()`, threading `center_line`/`spawn_offset` into
  `place_ship()` calls)

Diff stat: 2 files changed, 84 insertions(+), 18 deletions(-).

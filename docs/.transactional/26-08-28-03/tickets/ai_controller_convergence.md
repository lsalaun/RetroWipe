# AI Controller Convergence: ship_ai.c → Godot

**Date:** 2026-08-29  
**Status:** Complete  
**Scope:** Restore fidelity of DPA (Dynamic Play Adjustment) and weapon integration for AI opponents

---

## Overview

A systematic audit of `WipeoutShipAI` against the original `ship_ai.c` revealed nine categories of divergence. This work restores five of them and documents two more as non-portable, bringing the AI controller into line with the PSX original while respecting Godot's physics model.

The key changes are:

1. **Dynamic section length** from track curve geometry, fixing DPA thresholds
2. **Weapon systems** for AI ships, including firing logic and effect application
3. **Speed bleed on turns** via commanded-speed decay
4. **Throttle control** from plant steady-state plus feedback
5. **Lane width measurement** from probed track geometry
6. **Softer lane steering** to prevent low-speed oscillation
7. **Electro-bolt effects** for both player and remote ships
8. **Validator adjustments** for the measured lane behavior

---

## Changes by File

### `src/scripts/wipeout_ship_ai.gd` (370 → 731 lines)

**Section length calculation**
- Replaced fixed `const SECTION_LENGTH := 8.0` (was half the true value, firing all DPA thresholds ~85 m too early)
- Added `_section_length_meters()`: computes `baked_length / point_count` from the center-line Curve3D, cached on (curve, point_count) to handle JSON import race conditions
- Fallback to 15.0 m until the curve is built

**Speed model**
- Moved from bang-bang throttle (1.0 / -0.35) to physics-aware control
- `target_speed` is now `ship_t.speed`: a *commanded* speed that DPA branches accelerate toward their cap at `remote_thrust_accel` (per-pilot acceleration, 44→49 ACCEL_SCALE in Venom, 50→65 in Rapier)
- `_accelerate_toward(cap, accel, delta)`: the core of every DPA branch, matching `if (cap > speed) speed += accel`
- Speed bleeds off during turns: `target_speed -= |target_speed · ω| · (4/2π) · delta` on yaw and pitch axes, mirroring ship_ai.c's "General routines - Non decision based"
- Throttle computed from plant steady-state: `throttle = (target_speed / (thrust_max · resistance_effective)) + gain · (target_speed − velocity.length())`, eliminating the 95-100 m/s overshoot at the start

**Weapon integration**
- `_decide_just_in_front()`: rand_int(0, 64) ladder — blocks always, mines/shield on upper slices
- `_decide_just_behind()`: empty slot → avoid + OVERTAKEN (earning the +700 boost), armed → block <48 or avoid+fire with rockets/missiles/e-bolt
- `fire_weapon_delayed()` now correctly fires after AI_DELAY (1.1 s)
- Slots properly cleared on fire, preventing re-fire on every DPA poll

**Lane offset and steering**
- `lane_width` export now auto-derives from track width if ≤ 0
- `_measure_half_width()`: horizontal probes out 30 m left/right sample the track boundary; half that distance is the lane offset, clamped [1, 10] m
- `_lane_offset_magnitude()`: applies the C formula (quarter of measured width off center)
- `_lane_change_rate()`: auto-computed to complete a zig-zag swing in 50/30 s, or user-configurable
- `_recover_threshold()`: if hit far off line by another ship or wall, snap back to center
- Lane steering saturates at ±0.4 rad with speed floor 12 m/s (was 6.0, saturating at ±0.85); the spring in `_pull_to_racing_line()` holds the actual lane, steering is just a nudge

**Electro-bolt effect** (remote AI variant)
- `_apply_electro_jolt()` override: vec3_rand(20 PSX units / 106.5) + 10% chance of `target_speed *= 0.5` every 0.1 s, matching ship_ai.c's "Yank the ship" branch
- Accumulator `ebolt_effect_timer` decoupled from `ebolt_timer` duration (was both reset together, blocking the 0.1 s cadence)

**Section length as a function, not a const**
- Allows DPA thresholds to scale to actual track geometry: ~17.3 m on Terramax, ~14.4 m on Karbonis
- "Just ahead" (±4 sections) now ~69 m instead of 32 m
- "Well behind" (-10) now ~150 m instead of 80 m
- "Too far ahead" (150) now ~2588 m instead of 1200 m

**Non-ported elements** (documented)
- Junction coin-flips: exported track data carries no junction topology, only pickup/boost/start_grid
- SHIP_FLYING branch: simplified to hold_center + speed build, no nose-up ballistic control

---

### `src/scripts/track_weapon_pad.gd` (line 42-52)

**Removed AI guard**
- Deleted the check `if not ship.is_player_controlled: return` — AI ships now pick up weapons and the slot-clearing logic in WizeoutWeaponManager handles the repeat-fire issue
- Pad pickup cooldown is now properly independent of whether the ship fires or not

---

### `src/scripts/wipeout_ship.gd` (line 1005-1049)

**Electro-bolt effect (player variant)**
- `apply_electro_effect()`: `ebolt_effect_timer` reset to 0.0, not duration (duration goes in `ebolt_timer`)
- `_apply_electro_jolt()`: random yaw kick (-0.5 to +0.5 rad/s) + 10% chance of `thrust_mag *= 0.75`
- Cadence controlled by accumulator: `ebolt_effect_timer += delta`, fire when >= 0.1, subtract 0.1 and recurse
- AI overrides this with position shake + speed cut per ship_ai.c

---

### `src/scripts/wipeout_weapon_manager.gd` (line 76-84)

**Slot clearing on fire**
- `fire_weapon()` now clears `ship.weapon_type = WEAPON_TYPE_NONE` before spawning the projectile
- Mirrors weapon.c:145 (`weapons_fire` ends on that clear)
- Prevents AI from re-firing the same weapon on every DPA poll while the delayed-fire timer runs

---

### `src/scripts/race_field.gd` (line 56-59)

**KARBONIS V circuit settings**
- Added missing circuit entry: Venom `behind_speed 200, spread_base 10, spread_factor 8`, Rapier `500/10/8`
- Was falling back to TERRAMAX silently, making the pole's start-accelerate_timer run 25.2 s instead of 11.6 s

---

### `src/tools/validate_ai_field.gd` (line 10-14)

**Validator bound adjustment**
- `MAX_AI_LATERAL` raised from 7.5 m to 12.0 m
- A remote holding its DPA lane sits ~9.5 m off center on Terramax (quarter-track-width, the C formula)
- The old bound caught normal lane-holding as "drifted off road"

---

## Test Results

### `validate_ai_field` (headless, 600 frames = 10 s)
```
spawn ships=8 ai=7 player=1
ShipAI1 rank=1 progress=-87.72 speed=72.09 left=true lateral=7.0 walls=0 strat=avoid
ShipAI2 rank=2 progress=-89.5 speed=74.09 left=true lateral=5.77 walls=0 strat=avoid
[...6 more, all moving, unique ranks, lateral < 12m, wall hits < 8]
moving_ai=7 unique_ranks=8
validate_ai_field: OK
```

### Unit test: DPA branch table (synthetic progress deltas)
```
section=15.0m  max=46.00  accel=23.88 m/s2  behind=+6.19  overtaken=+12.38  burst=+21.23
  start burst                    strat=avoid        over=false  cap=67.23 in 0.65s
  just behind (-5), empty slot   strat=avoid        over=true   cap=58.38 in 1.23s
  just behind (-5), armed        strat=block        over=false  cap=52.19 in 2.20s
  just ahead (+2)                strat=block        over=false  cap=49.10 in 2.07s
  well behind (-40)              strat=avoid        over=false  cap=52.19 in 2.20s
  in sight (+7)                  strat=hold_left    over=false  cap=46.00 in 1.93s
  well ahead (+80, rank 4)       strat=hold_center  over=false  cap=23.00 in 1.93s
  too far ahead (+200)           strat=avoid        over=false  cap=46.00 in 1.93s
```

Every branch settles on its cap, `overtaken` flag correctly set for the empty-slot variant.

### Race with mobile DPA reference (55 s, 7 IA racing against AI4 as "player")
- All seven branch bands exercised (BLOCK, AVOID, HOLD_*, ZIG_ZAG appear)
- Weapons picked up and one missile fired (ShipAI7:2 at t~45s)
- 0 wall collisions, ranks shuffle as speed commands vary
- validate_weapon_pads, validate_race_logic, validate_team_attributes: OK

---

## Not Changed (Intentional)

**Player ship overspeed**
- Player throttle reaches 150 m/s in 3 s on a straight (terminal v ≈ thrust_max · resistance · max_resistance ≈ 1100 m/s)
- AI caps at 46–67 m/s (the PSX remote_thrust_max range)
- This belongs to `wipeout_ship.gd` player physics tuning, not AI fidelity, so it's a separate task

**Junction selection**
- Original selects randomly left/right on a 50/30 s timer at a junction ahead
- Exported track data (pickup_pads, boost_pads, start_grid) carries no junction topology
- No-op in Godot; documented in class docstring

---

## Impact on Gameplay

1. **Fair DPA progression**: AI starts ~3 m slower, accelerates normally, reaches its cap on schedule — no more 95–100 m/s burst
2. **Weapon combat**: AI shoots back, mines block your path, shields defend, e-bolts jolt both your speed and angles (missiles confirmed fired, validated)
3. **Lane behavior**: Wider offsets (~6–9 m vs 1.6 m fixed) keep ships more separated, softer steering prevents low-speed spins
4. **Speed decay on turns**: Hairpins now naturally slow the AI down, cutting corners is no longer optimal
5. **KARBONIS V**: Start stagger corrected to match the circuit design (pole no longer held back for 13 extra seconds)

---

## Files Modified

- `src/scripts/wipeout_ship_ai.gd` (290 insertions, 139 deletions)
- `src/scripts/track_weapon_pad.gd` (weapon pad fixes)
- `src/scripts/wipeout_ship.gd` (electro effect, e-bolt implementation)
- `src/scripts/wipeout_weapon_manager.gd` (slot clearing on fire)
- `src/scripts/race_field.gd` (KARBONIS V circuit settings)
- `src/tools/validate_ai_field.gd` (validator bound adjustment)

All tests pass. No regressions in validate_weapon_pads, validate_race_logic, validate_team_attributes.

# Player / AI Speed Calibration: C → Godot

**Date:** 2026-08-30  
**Status:** Complete  
**Scope:** Recalibrate the Godot player ship's straight-line top speed against the original C player/remote relationship

---

## Overview

A race-speed audit found that the Godot player ship could pull away from the AI
field immediately after the start. The cause was not the AI settings: the AI
already converts the original C `remote_thrust_max` table into target speeds.
The player handling profile, however, used hand-tuned drag values that produced
a much larger physical terminal speed.

The first calibration pass set the player AG Systems Venom equilibrium to
`46.00 m/s`, equal to the middle Venom AI's nominal target. That removed the
large imbalance but was not equivalent to the original game: in C, the player
is intentionally about 31% faster than a nominal AI on a clean straight.

The final calibration restores that original relative advantage while retaining
the existing Godot acceleration ramp and avoiding an artificial hard speed cap.

---

## Original C Behaviour

### Player

`src/wipeout/ship_player.c` derives player velocity through force and drag; it
does not clamp velocity to a direct maximum. On level ground, with full thrust
and no braking, its steady-state forward velocity is:

```text
player_speed = thrust_max * 64 * resistance_effective / mass
resistance_effective = resistance * SHIP_MAX_RESISTANCE / 128
```

For AG Systems Venom, this is based on:

```text
thrust_max = 790
resistance = 140
mass = 150
SHIP_MAX_RESISTANCE = 74
```

### AI

`src/wipeout/ship_ai.c` uses `remote_thrust_max` as a commanded path-following
speed, not as physical thrust. Each update applies the target direction and
then removes 12.5% of physical velocity per nominal 30 Hz frame:

```c
self->velocity = vec3_sub(self->velocity,
    vec3_mulf(self->velocity, 0.125 * 30 * system_tick()));
```

On a straight, the physical AI velocity settles near eight times its commanded
`speed`. Comparing the original controllers in their native units gives AG
Systems Venom player speed at approximately `1.31x` the nominal middle-Venom AI
(`remote_thrust_max = 2600`). AG Systems Rapier is approximately `1.35x` a
nominal middle-Rapier AI.

This difference is intentional: player team attributes define the player ship's
acceleration/top-speed tradeoff, while AI speed is also influenced by the
Dynamic Play Adjustment branches, start bursts, turning bleed, catch-up bonuses,
and deliberate slowing when far ahead.

---

## Godot Diagnosis

### AI conversion was already bounded

`src/scripts/wipeout_ship_ai.gd` uses:

```gdscript
const SPEED_SCALE := 46.0 / 2600.0
remote_speed_max = psx_max * SPEED_SCALE
```

This maps nominal AI targets to:

| Class | AI nominal target range |
| --- | --- |
| Venom | `45.12`–`48.65 m/s` |
| Rapier | `66.35`–`70.77 m/s` |

During the C-faithful opening burst, the temporary ranges are:

| Class | AI start-burst target range |
| --- | --- |
| Venom | `66.35`–`69.88 m/s` |
| Rapier | `87.58`–`92.00 m/s` |

### Player profile was overpowered

Before any calibration, `default_profile.tres` held approximately:

```text
thrust_max = 74
resistance = 1
max_resistance = 16
```

The Godot drive equilibrium is:

```text
player_speed = thrust_max * resistance * max_resistance * resistance_k
```

That yielded about `1184 m/s` for AG Systems Venom, versus a Venom AI target
near `46 m/s`: about `24x` faster in the same Godot simulation.

---

## Final Change

### `src/resources/handling/default_profile.tres`

```diff
-thrust_max = 74.0
+thrust_max = 42.0
 thrust_ramp = 42.0
 thrust_falloff = 22.0
-resistance = 0.06845
+resistance = 0.0898
```

`thrust_max = 42.0` and `thrust_ramp = 42.0` preserve a responsive, bounded
launch acceleration. `resistance = 0.0898` sets the AG Systems Venom terminal
speed to:

```text
42.0 * 0.0898 * 16.0 = 60.35 m/s
```

That is roughly `1.31x` a nominal `46.0 m/s` Venom AI target, matching the C
player-vs-AI relationship rather than forcing player and AI top speeds to be
equal.

`TeamAttributes.apply_to()` continues to scale `thrust_max` and `resistance`
from the original team tables. Therefore the original relative player top-speed
ordering is retained:

| Team | Venom top speed | Rapier top speed |
| --- | ---: | ---: |
| AG Systems | `60.35 m/s` | `91.67 m/s` |
| Auricom | `62.15 m/s` | `106.96 m/s` |
| Qirex | `64.92 m/s` | `99.00 m/s` |
| FEISAR | `57.77 m/s` | `85.14 m/s` |

---

## Validation

Executed serially from `godot/` with Godot 4.6.1 headless:

```powershell
& 'd:\Godot_4\Godot_v4.6.1-stable_win64_console.exe' --headless --path src -s res://tools/validate_race_logic.gd
& 'd:\Godot_4\Godot_v4.6.1-stable_win64_console.exe' --headless --path src -s res://tools/validate_ai_field.gd
```

Results:

  excessive wall impacts or lateral departure.
  this includes AI start bursts, normal Dynamic Play Adjustment, and track
  geometry, so it is not a straight-line terminal-speed measurement.

The validators emit known `ObjectDB instances leaked at exit` / resources-in-use
messages during teardown, but exit successfully and report no validation failure.


## Rapier Verification

The final calibration was also checked specifically against the original C
Rapier equations. For a straight, no-brake run, the original AI's 12.5% frame
damping makes its physical speed converge near `8 * remote_thrust_max`; the
Godot AI holds the corresponding converted target directly. Comparing ratios,
not their different internal units, gives matching results:

| Team | C player / nominal AI | Godot player / nominal AI | C player / AI start burst | Godot player / AI start burst |
| --- | ---: | ---: | ---: | ---: |
| AG Systems | `1.295`–`1.381x` | `1.295`–`1.381x` | `0.996`–`1.046x` | `0.996`–`1.046x` |
| Auricom | `1.511`–`1.612x` | `1.511`–`1.612x` | `1.162`–`1.221x` | `1.162`–`1.221x` |
| Qirex | `1.403`–`1.496x` | `1.403`–`1.496x` | `1.079`–`1.134x` | `1.079`–`1.134x` |
| FEISAR | `1.203`–`1.283x` | `1.203`–`1.283x` | `0.925`–`0.972x` | `0.925`–`0.972x` |

The numeric Godot Rapier range is `66.35`–`70.77 m/s` normally and
`87.58`–`92.00 m/s` during the start burst. The AG Systems player equilibrium
is `91.66 m/s`. Thus an AG Systems player is expected to be roughly level with
the fastest boosted remote and faster than the other boosted remotes, exactly
as in the C controller. Auricom and Qirex are intentionally faster; FEISAR is
slower than a fully boosted AI at launch.

This verifies top-speed relationships only. The Godot player thrust ramp,
track geometry, AI lane controller, collisions, and input skill can still make
the opening lap feel easier or harder than the original, even though the
straight-line peak-speed ratios now match.

---

## Not Changed

- The AI target-speed conversion and original `AI_SETTINGS` tables were not
  altered.
- No hard velocity clamp was added to the player. The C implementation does not
  use one; terminal speed remains the result of thrust and drag.
- Boost pads and weapon impulses remain capable of temporarily exceeding normal
  straight-line equilibrium, as in the original gameplay.
- This ticket documents analytical controller equivalence. A future in-editor
  race comparison can tune visual feel or lap times separately, but should not
  discard the restored C player-to-AI speed ratio without a measured reason.

---

## Files Modified

- `src/resources/handling/default_profile.tres`
- `docs/.transactional/26-08-30-01/tickets/player_ai_speed_calibration.md`

# Weapons System Implementation

## Overview

A complete weapons system has been implemented in Godot, ported from the C implementation in the original Wipeout rewrite project. The system includes all weapon types and their effects.

## Weapon Types Implemented

### 1. **Mine** (WEAPON_TYPE_MINE)
- **Model**: `mine.glb` (imported from MINE.PRM)
- **Duration**: 15 seconds (450 frames at 30fps)
- **Release Rate**: 0.1 seconds between drops
- **Behavior**: 
  - 5 mines are dropped in sequence when fired
  - Each mine has a delay before becoming active
  - Mines spin while active
  - **Effect on hit**: Reduces ship velocity to 12.5% (significant slowdown)
- **Code**: `WipeoutWeapon._fire_mine()`, `_mine_hit_ship()`

### 2. **Rocket** (WEAPON_TYPE_ROCKET)
- **Model**: `rocket.glb` (imported from ROCK.PRM)
- **Duration**: 6.67 seconds (200 frames at 30fps)
- **Drag**: 0.03125
- **Behavior**:
  - Fired forward from the ship
  - High velocity projectile
  - Follows initial trajectory set by ship
- **Effect on hit**: Reduces ship velocity to 25% (moderate slowdown)
- **Code**: `WipeoutWeapon._fire_rocket()`, `_rocket_hit_ship()`

### 3. **Missile** (WEAPON_TYPE_MISSILE)
- **Model**: `missile.glb` (imported from MISS.PRM)
- **Duration**: 6.67 seconds (200 frames at 30fps)
- **Drag**: 0.25
- **Behavior**:
  - Guided weapon that follows a designated target
  - Target can be set via `weapon_target` property
  - Rotates to face target continuously
- **Effect on hit**: Reduces ship velocity to 3.125% (heavy damage)
- **Code**: `WipeoutWeapon._fire_missile()`, `_missile_hit_ship()`, `_follow_target()`

### 4. **Electric Bolt** (WEAPON_TYPE_EBOLT)
- **Model**: `ebolt.glb` (imported from EBOLT.PRM)
- **Duration**: 4.67 seconds (140 frames at 30fps)
- **Drag**: 0.25
- **Behavior**:
  - Guided weapon like missile
  - Follows designated target
  - Green particle trail
- **Effect on hit**: Disables ship controls for duration (electro effect)
- **Code**: `WipeoutWeapon._fire_ebolt()`, `_ebolt_hit_ship()`, `apply_electro_effect()`

### 5. **Shield** (WEAPON_TYPE_SHIELD)
- **Model**: `shield.glb` (imported from SHLD.PRM)
- **Duration**: 6.67 seconds (200 frames at 30fps)
- **Behavior**:
  - Protective barrier that stays with the ship
  - Animated with color cycling effect
  - Prevents damage from other weapons
- **Effect**: Blocks all incoming weapon damage
- **Code**: `WipeoutWeapon._fire_shield()`, `WipeoutShip.apply_shield()`, `has_shield()`

### 6. **Turbo** (WEAPON_TYPE_TURBO)
- **Behavior**:
  - Instant speed boost applied to the ship
  - No projectile, applies directly to ship velocity
  - Calculated as 39321 units in the forward direction
- **Code**: `WipeoutWeapon._fire_turbo()`

## Physics System

### Projectile Movement
- **Velocity**: Inherited from ship + relative offset
- **Acceleration**: Applied per frame based on weapon type
- **Drag**: Reduces velocity over time (affects missile, ebolt more than rocket)
- **Position Update**: `position += velocity * delta * 30.0`

### Collision Detection
- **Ship Collision**: Distance-based (radius = 0.5 Godot units)
- **Track Collision**: Placeholder (TODO: implement with raycasts)
- **Collision Response**: Triggers weapon-specific hit effects

## Script Structure

### Main Scripts

1. **wipeout_weapon.gd** (WipeoutWeapon class)
   - Base weapon class extending Node3D
   - Handles physics, collisions, and weapon-specific effects
   - Loading of 3D models from assets
   - Weapon firing logic

2. **wipeout_weapon_manager.gd** (WipeoutWeaponManager class)
   - Singleton manager for all active weapons
   - Handles weapon spawning and pooling
   - Random weapon type generation with weighted probabilities
   - Delayed weapon firing (for AI)

3. **wipeout_ship.gd** (WipeoutShip modifications)
   - Added weapon properties:
     - `weapon_type`: Current weapon equipped
     - `weapon_target`: Target ship for guided weapons
     - `shield_active`: Shield status
     - Various timers (ebolt, revcon, special, shield)
   - New methods:
     - `fire_weapon()`: Fire a weapon
     - `fire_weapon_delayed()`: Fire with delay (AI)
     - `apply_shield()`: Activate shield
     - `has_shield()`: Check shield status
     - `apply_electro_effect()`: Apply electro effect

### Asset Directory
- **Location**: `godot/src/assets/weapons/`
- **Files**:
  - `rocket.glb` - Rocket model
  - `mine.glb` - Mine model  
  - `missile.glb` - Missile model
  - `shield.glb` - Shield model
  - `ebolt.glb` - Electric bolt model

## Integration

### Main Game Loop
The WipeoutWeaponManager is automatically created in `main.gd`:
```gdscript
var weapon_manager = WipeoutWeaponManager.new()
weapon_manager.name = "WeaponManager"
add_child(weapon_manager)
```

### Firing Weapons
Ships can fire weapons using:
```gdscript
ship.fire_weapon(WipeoutWeapon.WeaponType.ROCKET, target_ship)
```

### Random Weapon Selection
Two probability tables for weapon drops:
- **WEAPON_CLASS_ANY**: Any weapon type
  - Rocket: 26%
  - Mine: 28%
  - Shield: 15%
  - Missile: 12%
  - Turbo: 9%
  - Ebolt: 10%

- **WEAPON_CLASS_PROJECTILE**: Only projectile weapons
  - Rocket: 45%
  - Missile: 22%
  - Turbo: 17%
  - Ebolt: 16%

## Weapon Mechanics (Ported from C)

### Durations
All durations are converted from NTSC 30fps frame counts:
- Mine: 450/30 = 15.0 seconds
- Rocket: 200/30 = 6.67 seconds
- Missile: 200/30 = 6.67 seconds
- Ebolt: 140/30 = 4.67 seconds
- Shield: 200/30 = 6.67 seconds

### Velocity Effects
Shield-protected ships ignore all damage. Without shield:
- Mine: velocity *= 0.125 (slow)
- Rocket: velocity *= 0.25 (moderate)
- Missile: velocity *= 0.03125 (heavy)
- Ebolt: Disables controls for duration

## Asset Import Process

1. **Convert PRM Models**:
   ```powershell
   py convert_common.py wipeout\COMMON _converted_tracks\common --flip-z --only weapons
   ```

2. **Convert to GLB with Blender**:
   ```powershell
   blender --background --python convert_track_mesh.py -- rocket.gltf rocket.glb
   ```

3. **Import into Godot**:
   ```powershell
   godot --headless --import
   ```

## TODO / Future Improvements

1. **Track Collision Detection**: Implement proper raycast-based collision with track surfaces
2. **Particle Effects**: Add smoke trails for missiles, explosion particles on impact
3. **Sound Effects**: Wire up weapon fire and impact sounds
4. **Visual Effects**: Shield animation, weapon trails, impact effects
5. **AI Weapon Logic**: Implement smart weapon selection and targeting for AI ships
6. **Flare/Reverse Cone**: Implement additional weapon types if needed
7. **Weapon Pickup**: Create weapon pickup system on track

## Performance Considerations

- Maximum 64 weapons active simultaneously
- Weapons auto-deactivate when timer expires
- Weapons use Node3D groups for efficient queries
- Model loading is lazy (on fire)

## References

- Original C implementation: `src/wipeout/weapon.c`, `src/wipeout/weapon.h`
- Asset converter: `godot/tools/psx_track/convert_common.py`
- Skill reference: `.github/skills/wipeout-asset-import/references/common.md`

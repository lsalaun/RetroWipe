# Weapon Pads System

> **Controls**: press **Space** (or the gamepad's **X / Square** button) to fire
> the weapon you are holding. The held weapon's name is shown at the top-centre
> of the HUD; a pad only arms you when that slot is empty.

## Overview

The weapon pads system allows players to pick up weapons scattered on the track. When a ship drives over a weapon pad, it randomly receives one of the available weapon types. Each pad can only give one weapon at a time and must respawn before giving another.

## Implementation

### TrackWeaponPad Class

**File**: `src/scripts/track_weapon_pad.gd`

Weapon pads are Area3D-based gameplay triggers that:
- Detect when ships pass over them
- Give a random weapon to the ship
- Animate and provide visual feedback
- Respawn after a cooldown period

#### Key Properties

```gdscript
@export var box_size: Vector3 = Vector3(3.0, 2.0, 3.0)  # Collision area size
@export var weapon_class: int = 1  # 1=ANY, 2=PROJECTILE_ONLY
@export var respawn_time: float = 5.0  # Cooldown before next pickup
@export var pad_color: Color = Color.YELLOW  # Visual color
@export var show_visual: bool = true  # Show 3D visual representation
```

#### Key Methods

```gdscript
func _give_weapon_to_ship(ship: WipeoutShip) -> void
  # Gives a random weapon to the ship

func is_active() -> bool
  # Returns true if the pad can give weapons

func get_weapon_class() -> int
  # Returns the weapon class this pad provides

func set_weapon_class(new_class: int) -> void
  # Changes the weapon class
```

### Track Integration

Weapon pads are automatically created from track data via the `TrackGameplayZones` script:

**File**: `src/scripts/track_gameplay_zones.gd`

The script reads from track JSON files (e.g., `Track_01_face_flags.json`) and creates three types of gameplay objects:
1. **WeaponPads** - Weapon pickup locations
2. **BoostPads** - Speed boost pads
3. **StartGrid** - Starting line markers

#### Auto-Spawning Process

```gdscript
func _spawn_weapon_pads(entries: Array) -> void
  # Iterates through "pickup_pads" entries in the track JSON
  # Creates TrackWeaponPad instances at each location
  # Groups them under a "WeaponPads" node
```

### Scene Integration

Weapon pads are placed in the scene hierarchy as:

```
Track01 (Node3D)
├── TrackMesh
├── Scenery
├── CenterLine
├── GameplayZones (TrackGameplayZones)
│   ├── WeaponPads (Node3D group)
│   │   ├── WeaponPad_0 (TrackWeaponPad)
│   │   ├── WeaponPad_1 (TrackWeaponPad)
│   │   └── ...
│   ├── BoostPads
│   │   ├── BoostPad_0
│   │   └── ...
│   └── StartGrid
└── ShipSpawn
```

## Features

### Visual Representation

Each weapon pad has an optional 3D visual indicator:
- **Shape**: Animated cylinder
- **Color**: Yellow (configurable via `pad_color`)
- **Animation**: Floating up and down effect
- **Brightness**: Dims when inactive, brightens when active

### Pickup Mechanics

1. **Detection**: Ship enters the pad's collision area
2. **Assignment**: Random weapon selected based on `weapon_class`
3. **Feedback**: Visual flash and scale animation
4. **Cooldown**: Pad becomes inactive for `respawn_time`
5. **Respawn**: Pad becomes active again and can give another weapon

### Weapon Selection

Two weapon classes determine which weapons can be picked up:

**WEAPON_CLASS_ANY** (default)
- Rocket: 26%
- Mine: 28%
- Shield: 15%
- Missile: 12%
- Turbo: 9%
- Ebolt: 10%

**WEAPON_CLASS_PROJECTILE**
- Rocket: 45%
- Missile: 22%
- Turbo: 17%
- Ebolt: 16%

## Usage

### Manual Placement

To manually place a weapon pad on a track:

1. Open the track scene
2. Add a new `TrackWeaponPad` node to the `GameplayZones/WeaponPads` group
3. Position it on the track
4. Configure the pad properties:
   - `weapon_class`: Type of weapons to give
   - `respawn_time`: Cooldown between pickups
   - `show_visual`: Whether to show the 3D visual

### Automatic Spawning

Weapon pads are automatically created from track data:

1. Track converter exports "pickup_pads" in the track JSON
2. `TrackGameplayZones._spawn_weapon_pads()` creates TrackWeaponPad instances
3. Pads appear at specified locations on the track

### Configuration

Configure a pad via the Inspector:

```gdscript
weapon_pad.weapon_class = 1  # ANY weapons
weapon_pad.respawn_time = 5.0  # 5 second cooldown
weapon_pad.box_size = Vector3(3.0, 2.0, 3.0)  # Pickup area
weapon_pad.pad_color = Color.YELLOW  # Visual color
```

Or programmatically:

```gdscript
var pad = TrackWeaponPad.new()
pad.position = Vector3(0, 2, 0)
pad.set_weapon_class(1)  # ANY weapons
track.get_node("GameplayZones/WeaponPads").add_child(pad)
```

## Interaction with Ships

When a ship picks up a weapon:

```gdscript
# The weapon is assigned to the ship
ship.weapon_type = weapon_type

# The pad provides visual/audio feedback
pad._play_pickup_effect(ship)

# The pad becomes inactive
pad._deactivate_pad()

# After respawn_time, the pad is active again
await get_tree().create_timer(respawn_time).timeout
pad._activate_pad()
```

## Performance Considerations

- Weapon pads use simple distance-based detection with Area3D
- Each pad checks overlapping areas every physics frame
- Pads are culled from the physics engine when not needed
- Maximum typical pads per track: 20-30 (no hard limit)

## Validation

Use the validation tool to check weapon pads on a track:

**File**: `src/tools/validate_weapon_pads.gd`

Checks performed:
- ✓ All pads have proper scripts
- ✓ All pads have collision shapes
- ✓ All pads are positioned correctly
- ✓ All pads have visual representations (optional warning)

## Asset Files

### Scenes
- `scenes/track_weapon_pad.tscn` - Weapon pad scene template

### Scripts
- `src/scripts/track_weapon_pad.gd` - Main weapon pad class
- `src/scripts/track_gameplay_zones.gd` - Track spawner (modified)
- `src/tools/validate_weapon_pads.gd` - Validation tool

## Integration with Weapons System

The weapon pad system is fully integrated with the weapons system:

1. **Random Selection**: Uses `WipeoutWeaponManager.get_random_weapon()`
2. **Assignment**: Sets `ship.weapon_type` directly
3. **Firing**: Ship fires weapon using normal fire mechanism
4. **Effects**: All weapon effects apply as usual

## Future Improvements

- [ ] Track-specific weapon pad configurations
- [ ] Weapon icon display on pads
- [ ] Sound effect on pickup
- [ ] Particle effects on pickup
- [ ] Difficulty-based weapon probability tables
- [ ] Special weapon pads (guaranteed weapon type)
- [ ] Time-limited weapons on pads
- [ ] Weapon pad placement tool in editor

## References

- Original Wipeout weapon system: C implementation in `weapon.c`
- Track data format: `convert_track_face_flags.py`
- GameplayZones integration: `track_gameplay_zones.gd`
- Boost pads reference: `track_boost_pad.gd` (similar pattern)

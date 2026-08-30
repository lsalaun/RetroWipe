extends SceneTree

## Headless check for TrackWeaponPad's detection box, same reasoning as
## validate_boost_pad.gd: the pad is spawned axis-aligned at the flagged
## face's centre (track_gameplay_zones.gd), not rotated to the track's local
## direction there, so it needs to be generous enough that a ship travelling
## at speed still overlaps it instead of clipping past.
##
## Unlike the boost pad's polled get_overlapping_areas(), arming happens off
## Area3D's area_entered signal, which Godot only emits once the physics
## server has actually settled the new overlap state -- several idle ticks
## after a teleport, not the next one.

const SHIP_SCENE := "res://scenes/WipeoutShip.tscn"
const SETTLE_TICKS := 5

## The box_size this replaced (see track_weapon_pad.gd's git history).
const OLD_BOX_SIZE := Vector3(6.0, 5.0, 6.0)

var _failures: Array[String] = []
var _frames := 0
var _sub_tick := 0
var _pad: Area3D = null
var _ship: Node3D = null
var _stage := 0 # 0 = far (sanity), 1 = edge (the actual fix), 2 = done


func _initialize() -> void:
	var packed := load(SHIP_SCENE) as PackedScene
	if packed == null:
		push_error("validate_weapon_pad_size: failed to load WipeoutShip")
		quit(1)
		return
	_ship = packed.instantiate()
	_ship.is_player_controlled = false
	# Park it far from the pad (both would otherwise default-instantiate at the
	# origin) before the pad's own _ready() ever runs, so it can't fire off an
	# incidental pickup -- and its 5s respawn_time cooldown -- before the test
	# gets a chance to place it deliberately.
	_ship.position = Vector3(0, 0, 30.0)
	root.add_child(_ship)
	_ship.gravity = 0.0

	var pad_script := load("res://scripts/track_weapon_pad.gd") as GDScript
	_pad = pad_script.new()
	root.add_child(_pad)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_ship.set_physics_process(false) # add_child()/_ready() timing is not reliable in --script mode; re-assert every tick
	if _frames < 3:
		return false

	if _frames == 3:
		_check("box_size was increased from the old %s" % OLD_BOX_SIZE, _pad.box_size.x > OLD_BOX_SIZE.x and _pad.box_size.z > OLD_BOX_SIZE.z and _pad.box_size.y > OLD_BOX_SIZE.y)
		_ship.weapon_type = WipeoutWeapon.WeaponType.NONE
		_ship.global_position = Vector3(0, 0, 30.0) # far outside, sanity baseline

	_sub_tick += 1
	if _sub_tick < SETTLE_TICKS:
		return false
	_sub_tick = 0

	match _stage:
		0:
			_check("far outside the pad: not armed", _ship.weapon_type == WipeoutWeapon.WeaponType.NONE)
			# Within the new box's half-length (5.0) but outside the old one's (3.0).
			_ship.global_position = Vector3(0, 0, 4.0)
		1:
			_check("within the new (but not the old) box extent: armed", _ship.weapon_type != WipeoutWeapon.WeaponType.NONE)
		2:
			if _failures.is_empty():
				print("validate_weapon_pad_size: OK")
				quit(0)
			else:
				for failure in _failures:
					push_error("validate_weapon_pad_size: %s" % failure)
				quit(1)
			return true

	_stage += 1
	return false


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures.append(what)

extends SceneTree

## Headless check for TrackBoostPad's detection box, ported from
## ship_player_update_race()'s FACE_BOOST handling: the pad is spawned
## axis-aligned at the flagged face's centre (track_gameplay_zones.gd), not
## rotated to the track's local direction there, so it has to be generous
## enough that a ship travelling at speed (or hovering a bit high) still
## overlaps it instead of clipping past.
##
## Area3D overlap pairs lag a placement by a physics tick or two (the physics
## server recomputes them once per step, and this SceneTree callback's own
## _physics_process has no fixed ordering relative to node-level ones, so a
## just-moved ship can still draw one more tick of boost off its old spot).
## Each position below gets several idle ticks to fully settle, then its
## velocity is re-zeroed and given one more tick alone -- what grows *after*
## that clean tick is the pad's real, current verdict on that position, not
## as a "did it move at all" check.

const SHIP_SCENE := "res://scenes/WipeoutShip.tscn"
const SETTLE_TICKS := 5

## The box_size this replaced (see track_boost_pad.gd's git history).
const OLD_BOX_SIZE := Vector3(6.0, 4.0, 6.0)

## One entry per position to probe: (label, z, expect_boost).
const CASES: Array[Array] = [
	["far outside the pad", 30.0, false],
	["within the new (but not the old) box extent", 4.0, true], # new half-length 5.0, old half-length 3.0
	["centred on the pad", 0.0, true],
]

var _failures: Array[String] = []
var _frames := 0
var _case_index := 0
var _sub_tick := 0
var _pad: Area3D = null
var _ship: Node3D = null
var _velocity_before := 0.0


func _initialize() -> void:
	var packed := load(SHIP_SCENE) as PackedScene
	if packed == null:
		push_error("validate_boost_pad: failed to load WipeoutShip")
		quit(1)
		return
	_ship = packed.instantiate()
	_ship.is_player_controlled = false
	root.add_child(_ship)
	# This scene has no track/floor under the ship, so its own hover/gravity
	# physics would otherwise drift the ship every tick regardless of the pad.
	_ship.gravity = 0.0

	var pad_script := load("res://scripts/track_boost_pad.gd") as GDScript
	_pad = pad_script.new()
	root.add_child(_pad)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	# Re-assert every tick: add_child()/_ready() timing in --script mode is not
	# guaranteed relative to a single call made right after instantiate(), so a
	# one-shot set_physics_process(false) in _initialize() is not reliable here.
	_ship.set_physics_process(false)
	if _frames < 3:
		return false

	if _frames == 3:
		_check("box_size was increased from the old %s" % OLD_BOX_SIZE, _pad.box_size.x > OLD_BOX_SIZE.x and _pad.box_size.z > OLD_BOX_SIZE.z and _pad.box_size.y > OLD_BOX_SIZE.y)
		_ship.global_position = Vector3(0, 0, CASES[0][1])
		_ship.velocity = Vector3.ZERO

	if _case_index >= CASES.size():
		if _failures.is_empty():
			print("validate_boost_pad: OK")
			quit(0)
		else:
			for failure in _failures:
				push_error("validate_boost_pad: %s" % failure)
			quit(1)
		return true

	_sub_tick += 1
	if _sub_tick == SETTLE_TICKS:
		# Fully settled at this position now; re-zero and give it one clean tick.
		_ship.velocity = Vector3.ZERO
		_velocity_before = 0.0
	elif _sub_tick == SETTLE_TICKS + 1:
		var case_entry: Array = CASES[_case_index]
		var label: String = case_entry[0]
		var expect_boost: bool = case_entry[2]
		var boosted: bool = _ship.velocity.length() > _velocity_before
		if expect_boost:
			_check("%s: boost applied" % label, boosted)
		else:
			_check("%s: no boost applied" % label, not boosted)

		_case_index += 1
		_sub_tick = 0
		if _case_index < CASES.size():
			_ship.global_position = Vector3(0, 0, CASES[_case_index][1])
			_ship.velocity = Vector3.ZERO

	return false


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures.append(what)

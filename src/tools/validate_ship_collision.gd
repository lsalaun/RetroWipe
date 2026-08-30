extends SceneTree

## Headless check that WipeoutShip's HullArea (ship-vs-ship contact, ship.c's
## ship_collide_with_ship()/alcol.prm) is sized from the real ALCOL.PRM hull
## (tools/psx_track/import_ships.py --collision) instead of a guessed box
## smaller than the visible ALLSH mesh -- see WipeoutShip.tscn's
## BoxShape3D_hull_area.
##
## Area3D overlap pairs are only current as of the last physics step, not the
## instant a position is written, so each placement below gets its own physics
## tick to settle before the following tick reads the result.

const SHIP_SCENE := "res://scenes/WipeoutShip.tscn"

## Measured from ALCOL.PRM, identical across all 8 ships. The live hull box is
## this times WipeoutShip.hull_collision_scale (see _initialize()), not this
## raw value -- the export lets the box hug the visible hull more tightly than
## the measured ALCOL.PRM extent.
const MEASURED_HULL_SIZE := Vector3(4.23, 1.05, 8.45)

enum Phase {
	NOSE_IN, NOSE_IN_CHECK,
	NOSE_OUT, NOSE_OUT_CHECK,
	SIDE_IN, SIDE_IN_CHECK,
	SIDE_OUT, SIDE_OUT_CHECK,
	DONE,
}

var _failures: Array[String] = []
var _frames := 0
var _phase: int = Phase.NOSE_IN
var _ship_a: Node3D = null
var _ship_b: Node3D = null
var _expected_size: Vector3 = MEASURED_HULL_SIZE


func _initialize() -> void:
	var packed := load(SHIP_SCENE) as PackedScene
	if packed == null:
		push_error("validate_ship_collision: failed to load WipeoutShip")
		quit(1)
		return
	_ship_a = packed.instantiate()
	_ship_b = packed.instantiate()
	_ship_a.is_player_controlled = false
	_ship_b.is_player_controlled = false
	root.add_child(_ship_a)
	root.add_child(_ship_b)
	_expected_size = MEASURED_HULL_SIZE * _ship_a.hull_collision_scale


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	if _frames == 3:
		_check_hull_box_size()

	match _phase:
		Phase.NOSE_IN:
			_place_ships(Vector3(0, 0, 1) * (_expected_size.z - 0.3))
		Phase.NOSE_IN_CHECK:
			_check("nose-to-tail: overlaps just inside the real hull extent", _hull_areas_overlap())
			_place_ships(Vector3(0, 0, 1) * (_expected_size.z + 0.3))
		Phase.NOSE_OUT_CHECK:
			_check("nose-to-tail: clears just outside the real hull extent", not _hull_areas_overlap())
			_place_ships(Vector3(1, 0, 0) * (_expected_size.x - 0.3))
		Phase.SIDE_IN_CHECK:
			_check("side-by-side: overlaps just inside the real hull extent", _hull_areas_overlap())
			_place_ships(Vector3(1, 0, 0) * (_expected_size.x + 0.3))
		Phase.SIDE_OUT_CHECK:
			_check("side-by-side: clears just outside the real hull extent", not _hull_areas_overlap())
		Phase.DONE:
			if _failures.is_empty():
				print("validate_ship_collision: OK")
				quit(0)
			else:
				for failure in _failures:
					push_error("validate_ship_collision: %s" % failure)
				quit(1)
			return true

	_phase += 1
	return false


func _check_hull_box_size() -> void:
	var shape: CollisionShape3D = _ship_a.get_node_or_null("HullArea/HullCollisionShape3D")
	if shape == null or not (shape.shape is BoxShape3D):
		_check("HullArea has a BoxShape3D", false)
		return
	var size: Vector3 = (shape.shape as BoxShape3D).size
	_check("hull box matches hull_collision_scale times the measured ALCOL.PRM size (not a guessed smaller one)", size.is_equal_approx(_expected_size))
	_check("hull box is wider than the old 2.0 guess", size.x > 3.0 * _ship_a.hull_collision_scale)
	_check("hull box is longer than the old 5.4 guess", size.z > 7.0 * _ship_a.hull_collision_scale)


func _place_ships(offset: Vector3) -> void:
	_ship_a.global_position = Vector3.ZERO
	_ship_b.global_position = offset


func _hull_areas_overlap() -> bool:
	var area_a: Area3D = _ship_a.get_node_or_null("HullArea")
	var area_b: Area3D = _ship_b.get_node_or_null("HullArea")
	if area_a == null or area_b == null:
		return false
	return area_a.get_overlapping_areas().has(area_b)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures.append(what)

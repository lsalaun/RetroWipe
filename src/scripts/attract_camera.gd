extends Camera3D
class_name AttractCamera

## Roaming demo camera, ported from camera.c's attract-mode chain.
##
## camera_update_attract_random() coin-flips between two treatments and arms a
## five second timer; when it expires the flip is re-rolled:
##
##   camera_update_attract_circle -- orbits the subject, the orbit angle driven
##     by the view timer (sinf/cosf(update_timer * 0.25) * 512).
##   camera_update_static_follow -- parks on the track centre eleven sections
##     ahead of the subject (section->next plus ten more), raised, and only
##     rotates to keep the subject framed as it flies past.
##
## Two deliberate departures from the original:
##
##  - race.c calls camera_update() with g.ships[g.pilot] every frame, so the
##    original watches a single ship for the whole demo. Re-picking the subject
##    on each roll is this port's addition, so the demo tours the field.
##  - the circle's radius oscillates in the original (a 512 base plus a 512
##    swing off the same timer); this holds it at the sum, which frames the
##    ship more steadily than a camera that breathes in and out.
##
## PSX offsets convert at 106.5 units/m, the scale ship_ai.c's ELECTRO_SHAKE
## already establishes: the circle's 512+512 becomes ~9.6 m out, its -200/-400
## becomes ~5.6 m up, and static follow's 500 becomes ~4.7 m up.

enum Mode {
	ORBIT, ## camera_update_attract_circle
	STATIC, ## camera_update_static_follow
}

## camera->update_timer = 5 on both branches of camera_update_attract_random().
const VIEW_DURATION := 5.0

const PSX_UNITS_PER_METER := 106.5

const ORBIT_RADIUS := (512.0 + 512.0) / PSX_UNITS_PER_METER
const ORBIT_HEIGHT := (200.0 + 400.0) / PSX_UNITS_PER_METER
## The `camera->update_timer * 0.25` that walks the circle, in radians/second.
const ORBIT_ANGULAR_SPEED := 0.25

## `section = ship->section->next` then ten more hops.
const STATIC_SECTIONS_AHEAD := 11
const STATIC_HEIGHT := 500.0 / PSX_UNITS_PER_METER

## Matches WipeoutShip.tscn's CameraRig/Camera3D, so cutting to this camera
## does not also change the lens.
const FOV := 82.0
const NEAR := 0.05
const FAR := 400.0

var _ships: Array[WipeoutShip] = []
var _center_line: Path3D = null
var _subject: WipeoutShip = null
var _mode: int = Mode.ORBIT
var _view_timer: float = 0.0
var _orbit_phase: float = 0.0
## Held for the whole STATIC view: the point is picked once, when the view is
## rolled, and the camera then only rotates -- that standing-still is the whole
## character of camera_update_static_follow.
var _static_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	fov = FOV
	near = NEAR
	far = FAR


## Called by main.gd once the demo grid exists. `center_line` may be null (or
## curve-less) on a track missing that data, in which case STATIC views fall
## back to a vantage derived from the subject itself.
func setup(ships: Array[WipeoutShip], center_line: Path3D) -> void:
	_ships = ships
	_center_line = center_line
	current = true
	_roll_view()


func _process(delta: float) -> void:
	if _subject == null or not is_instance_valid(_subject):
		_roll_view()
		if _subject == null:
			return

	_view_timer -= delta
	if _view_timer <= 0.0:
		_roll_view()

	match _mode:
		Mode.ORBIT:
			_orbit_phase += delta * ORBIT_ANGULAR_SPEED
			var offset := Vector3(sin(_orbit_phase), 0.0, cos(_orbit_phase)) * ORBIT_RADIUS
			global_position = _subject.global_position + offset + Vector3.UP * ORBIT_HEIGHT
		Mode.STATIC:
			global_position = _static_position

	_look_at_subject()


## camera_update_attract_random(): pick a treatment, arm the timer, and run the
## chosen update once immediately so the cut lands on a framed shot rather than
## on wherever the previous view left the camera.
func _roll_view() -> void:
	_subject = _pick_subject()
	if _subject == null:
		return
	_mode = Mode.ORBIT if randi() % 2 == 0 else Mode.STATIC
	_view_timer = VIEW_DURATION
	if _mode == Mode.ORBIT:
		# A fresh angle per view, so two orbits in a row don't look continuous.
		_orbit_phase = randf() * TAU
		var offset := Vector3(sin(_orbit_phase), 0.0, cos(_orbit_phase)) * ORBIT_RADIUS
		global_position = _subject.global_position + offset + Vector3.UP * ORBIT_HEIGHT
	else:
		_static_position = _static_vantage(_subject)
		global_position = _static_position
	_look_at_subject()


## A random live ship, preferring one that is not the ship just watched so a
## re-roll actually cuts somewhere new.
func _pick_subject() -> WipeoutShip:
	var candidates: Array[WipeoutShip] = []
	for ship in _ships:
		if ship != null and is_instance_valid(ship):
			candidates.append(ship)
	if candidates.is_empty():
		return null
	if candidates.size() > 1 and _subject != null:
		candidates.erase(_subject)
	return candidates[randi() % candidates.size()]


## The centre of the section STATIC_SECTIONS_AHEAD in front of `ship`, raised.
## Section length is baked_length / point_count, the same derivation
## race_field.gd and wipeout_ship_ai.gd use (one curve point per TRACK.TRS
## section).
func _static_vantage(ship: WipeoutShip) -> Vector3:
	var curve: Curve3D = _center_line.curve if _center_line != null else null
	if curve == null or curve.point_count < 2:
		# No centre line to walk: stand off the ship's own nose instead, which
		# still reads as a fixed vantage it flies towards.
		var forward := -ship.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		return ship.global_position + forward.normalized() * ORBIT_RADIUS + Vector3.UP * STATIC_HEIGHT

	var length := maxf(curve.get_baked_length(), 0.001)
	var section_length := length / float(maxi(curve.point_count, 1))
	var offset := curve.get_closest_offset(_center_line.to_local(ship.global_position))
	var ahead := fposmod(offset + float(STATIC_SECTIONS_AHEAD) * section_length, length)
	return _center_line.to_global(curve.sample_baked(ahead, true)) + Vector3.UP * STATIC_HEIGHT


## Both treatments end by aiming the camera at the subject (the atan2 pair that
## sets camera->angle.x/y). look_at() throws if the target coincides with the
## camera or lies straight along the up axis, so both are guarded.
func _look_at_subject() -> void:
	var target := _subject.global_position
	var to_target := target - global_position
	if to_target.length_squared() < 0.0001:
		return
	if absf(to_target.normalized().dot(Vector3.UP)) > 0.999:
		return
	look_at(target, Vector3.UP)

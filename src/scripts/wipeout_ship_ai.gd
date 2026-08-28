extends WipeoutShip
class_name WipeoutShipAI

## Port of ship_ai.c's DPA (Dynamic Play Adjustment) onto Godot path-following.
## Original remotes do not steer at an offset lookahead point: angular velocity
## follows the section tangent (next.center - section.center) while position is
## attracted onto a parallel ray (center + lane offset). Aiming the player-style
## steer axis at a laterally shifted point overshoots into the walls and bounce-
## zigzags. This controller keeps that split: heading = centerline tangent,
## lane = damped crosstrack, plus wall-probe avoidance.
##
## `target_speed` is ship_t.speed: a *commanded* speed that each DPA branch
## accelerates toward its own cap at the pilot's remote_thrust_mag, that bleeds
## off as the craft rotates, and that the throttle then holds -- not a per-branch
## constant. Two pieces of ship_ai_update_race() are still not ported: the
## junction coin-flip (the exported track data carries no junction topology) and
## the SHIP_FLYING control law (airborne remotes fall back to hold-center path
## following instead of the original's nose-up ballistic branch).

const UPDATE_TIME_JUST_FRONT := 150.0 / 30.0
const UPDATE_TIME_JUST_BEHIND := 200.0 / 30.0
const UPDATE_TIME_IN_SIGHT := 200.0 / 30.0
const NUM_PILOTS := 8
## One TRACK.TRS section, in meters. Every DPA threshold in ship_ai.c is a
## section count, and the exported center line carries one point per TRS
## section (see main.gd's _start_line_offset), so the conversion is just
## baked_length / point_count: ~14.4 m on Karbonis, ~17.3 m on Terramax. The
## fallback only applies before the curve is built from its JSON.
const SECTION_LENGTH_FALLBACK := 15.0
## PSX speed unit -> m/s. 2600 is the mid-field Venom remote_thrust_max.
const SPEED_SCALE := 46.0 / 2600.0
## ship_ai.c: speed += remote_thrust_mag * 30 * system_tick(). A per-pilot
## acceleration in PSX units per NTSC frame, and what actually separates the
## seven opponents (44..49 in Venom, 50..65 in Rapier).
const ACCEL_SCALE := 30.0 * SPEED_SCALE
## The extra +150 on remote_thrust_mag while start_accelerate_timer runs.
const START_BURST_ACCEL := 150.0 * ACCEL_SCALE
## Tail-ender nerf in the JUST BEHIND branch when fight_back is clear.
const TAIL_ENDER_SPEED := 2100.0 * SPEED_SCALE
const TAIL_ENDER_ACCEL := 25.0 * ACCEL_SCALE
## speed -= fabsf(speed * angular_velocity.y) * 4 / (M_PI * 2), per second.
const TURN_SPEED_BLEED := 4.0 / TAU
## ship_ai.c yanks an electroed remote by vec3_rand(20) PSX units every 0.1 s.
const ELECTRO_SHAKE := 20.0 / 106.5
## Horizontal wall probes used to size the lane offset, see _measure_half_width.
const HALF_WIDTH_PROBE_RANGE := 30.0
const HALF_WIDTH_PROBE_INTERVAL := 0.2

const STRAT_HOLD_CENTER := &"hold_center"
const STRAT_HOLD_LEFT := &"hold_left"
const STRAT_HOLD_RIGHT := &"hold_right"
const STRAT_BLOCK := &"block"
const STRAT_AVOID := &"avoid"
const STRAT_ZIG_ZAG := &"zig_zag"

@export var lane_offset: float = 0.0 # unused by DPA; kept so existing scene exports still load
## Lane offset in meters, or <= 0 to derive it from the measured track width,
## which is what ship_ai.c does -- see _lane_offset_magnitude().
@export var lane_width: float = 0.0
@export var lane_width_fallback: float = 4.0
@export var lane_width_max: float = 10.0
@export var lookahead_distance: float = 8.0
## ship_t.speed: the commanded speed, driven by the DPA, held by the throttle.
@export var target_speed: float = 0.0
@export var steer_gain: float = 1.05
@export var yaw_damp_gain: float = 0.18
@export var crosstrack_gain: float = 2.8
## Rate limit on lane changes, or <= 0 to derive one that still completes a full
## zig-zag swing inside its 50/30 s half period.
@export var lane_change_speed: float = 0.0
@export var wall_avoid_steer: float = 0.55
@export var recover_lateral: float = 3.2
## ship_ai.c: acceleration += (best_path - position) * 0.5, integrated at 30 Hz
## -- a spring of 0.5 * 30 onto the section ray.
@export var racing_line_spring: float = 15.0
## Closed-loop gain on (target_speed - speed), in 1/s, on top of the
## feed-forward throttle. See _throttle_for_target_speed().
@export var speed_gain: float = 3.0

var fight_back: bool = true
var start_accelerate_timer: float = 0.0
var update_timer: float = 0.0
var strategy: StringName = STRAT_HOLD_CENTER
var overtaken: bool = false
var remote_speed_max: float = 46.0
var remote_thrust_accel: float = 45.0 * ACCEL_SCALE
var behind_speed_bonus: float = 6.0
var start_burst_bonus: float = 1200.0 * SPEED_SCALE
var overtaken_bonus: float = 700.0 * SPEED_SCALE
var inv_start_rank: int = 1
var current_lane: float = 0.0
var _ai_delta: float = 1.0 / 60.0
var _section_length: float = SECTION_LENGTH_FALLBACK
var _section_length_curve: Curve3D = null
var _section_length_points: int = 0
var _half_width: float = 0.0
var _half_width_timer: float = 0.0


func configure_from_race(settings: Dictionary, circuit: Dictionary, start_rank_inv: int) -> void:
	inv_start_rank = start_rank_inv
	position_rank = NUM_PILOTS - start_rank_inv
	var psx_max := float(settings.get("thrust_max", 2600.0))
	remote_speed_max = psx_max * SPEED_SCALE
	remote_thrust_accel = float(settings.get("thrust_magnitude", 45.0)) * ACCEL_SCALE
	# ship_init(): every ship starts the race at a standstill and has to build
	# its commanded speed up through the DPA, start burst included.
	target_speed = 0.0
	behind_speed_bonus = float(circuit.get("behind_speed", 350.0)) * SPEED_SCALE
	start_burst_bonus = 1200.0 * SPEED_SCALE
	overtaken_bonus = 700.0 * SPEED_SCALE
	fight_back = bool(settings.get("fight_back", true))
	var p := start_rank_inv - 1
	var spread_base := float(circuit.get("spread_base", 60.0))
	var spread_factor := float(circuit.get("spread_factor", 11.0))
	start_accelerate_timer = maxf(float(p) * (spread_base + float(p) * spread_factor) / 30.0, 0.0)
	strategy = STRAT_HOLD_CENTER
	update_timer = 0.0
	overtaken = false
	current_lane = 0.0


func _ready() -> void:
	is_player_controlled = false
	super._ready()
	var cam := camera_rig.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.current = false


func _physics_process(delta: float) -> void:
	_ai_delta = delta
	# ship_ai_update_intro_await_go() only bobs the ship on the grid: no DPA, and
	# start_accelerate_timer must not burn down before GO or the whole staggered
	# start collapses. The racing-line pull is skipped too, otherwise the two
	# grid columns get dragged onto the centerline during the countdown.
	if not race_control_enabled:
		super._physics_process(delta)
		return
	_update_dpa(delta)
	super._physics_process(delta)
	_pull_to_racing_line(delta)


func _gather_inputs() -> Dictionary:
	var result := {
		"throttle": 0.0,
		"steer": 0.0,
		"pitch": 0.0,
		"brake_left": false,
		"brake_right": false,
	}

	var frame := _sample_path()
	if frame.is_empty():
		return result
	var path_dir: Vector3 = frame["dir"]
	var path_right: Vector3 = frame["right"]
	var center_error: float = frame["center_error"]

	_measure_half_width(path_right)

	var recover := _recover_threshold()
	var desired_lane := _lane_offset_for_strategy()
	if absf(center_error) > recover:
		desired_lane = 0.0
	current_lane = move_toward(current_lane, desired_lane, _lane_change_rate() * _ai_delta)
	var crosstrack := center_error - current_lane

	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return result
	forward = forward.normalized()

	# Stanley-style: heading follows the local centerline tangent (short
	# lookahead, so hairpins are not cut into the inner wall) while crosstrack
	# is a speed-scaled atan term. Aiming steer at a laterally offset point was
	# what produced the left/right wall ping-pong.
	var heading_error := forward.signed_angle_to(path_dir, Vector3.UP)
	# The lane is held by the positional spring in _pull_to_racing_line(), the
	# way ship_ai.c does it -- this steering term is only a nudge that helps the
	# Godot grip model get there. It stays small and its speed floor stays high
	# on purpose: a nearly stationary ship asked for a full lane change used to
	# saturate the atan term and spin itself off the grid.
	var speed := maxf(velocity.length(), 12.0)
	var yaw_damp := clampf(yaw_velocity * yaw_damp_gain, -0.5, 0.5)
	var lane_steer := clampf(-atan(crosstrack_gain * crosstrack / speed), -0.4, 0.4)
	var wall_steer := _wall_avoidance_steer()
	if absf(crosstrack) > recover:
		wall_steer = 0.0
	result.steer = clampf(-heading_error * steer_gain + lane_steer + yaw_damp + wall_steer, -1.0, 1.0)
	# No extra corner slowdown here: ship_ai.c bleeds the *commanded* speed as
	# the craft rotates (see _update_dpa), so the set point is already lower
	# through a turn and the throttle only has to follow it.
	result.throttle = _throttle_for_target_speed()
	return result


## Nearest point on the center line plus its tangent frame and the ship's signed
## lateral error, shared by the steering and the racing-line spring.
func _sample_path(lookahead: float = -1.0) -> Dictionary:
	if center_line == null or center_line.curve == null or center_line.curve.point_count < 2:
		return {}
	var curve := center_line.curve
	var offset := curve.get_closest_offset(center_line.to_local(global_position))
	var closest_local := curve.sample_baked(offset, true)
	var ahead := lookahead if lookahead > 0.0 else lookahead_distance
	var path_dir := curve.sample_baked(offset + ahead, true) - closest_local
	path_dir.y = 0.0
	if path_dir.length_squared() < 0.0001:
		return {}
	path_dir = path_dir.normalized()
	var path_right := path_dir.cross(Vector3.UP)
	if path_right.length_squared() < 0.0001:
		return {}
	path_right = path_right.normalized()
	var lateral := global_position - center_line.to_global(closest_local)
	lateral.y = 0.0
	return {"dir": path_dir, "right": path_right, "center_error": lateral.dot(path_right)}


## ship_ai.c adds 0.5 * (best_path - position) into `acceleration`, where
## best_path is the ship projected onto the section ray shifted by the lane
## offset. That is a spring of 0.5 * 30 per second squared, damped by the same
## global drag every ship gets -- not a velocity override, so a ship-to-ship hit
## still knocks a remote off line instead of being cancelled on the spot.
func _pull_to_racing_line(delta: float) -> void:
	var frame := _sample_path(1.0)
	if frame.is_empty():
		return
	var path_right: Vector3 = frame["right"]
	var crosstrack: float = frame["center_error"] - current_lane
	velocity -= path_right * crosstrack * racing_line_spring * delta


## ship_ai_strat_hold_left/right return (v1 - v0) * 0.5 across one base face of
## the section: half a face, which is a quarter of the full track width. The
## exported tracks keep no per-section face geometry, so the same quantity is
## measured live -- two horizontal probes out to the walls give the local
## half-width, and half of that is the quarter-width the original uses.
func _measure_half_width(path_right: Vector3) -> void:
	_half_width_timer -= _ai_delta
	if _half_width_timer > 0.0:
		return
	_half_width_timer = HALF_WIDTH_PROBE_INTERVAL
	var world := get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return
	var half := HALF_WIDTH_PROBE_RANGE
	for side in [1.0, -1.0]:
		var query := PhysicsRayQueryParameters3D.create(
			global_position, global_position + path_right * side * HALF_WIDTH_PROBE_RANGE)
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.has("position"):
			half = minf(half, global_position.distance_to(hit["position"]))
	_half_width = half


func _lane_offset_magnitude() -> float:
	if lane_width > 0.0:
		return lane_width
	if _half_width <= 0.0:
		return lane_width_fallback
	return clampf(_half_width * 0.5, 1.0, lane_width_max)


## How far off line the ship gives up on its lane and heads back to the middle.
## The original has no such rule; it exists here because a Godot remote can be
## bounced clean off the racing line by a wall or another ship.
func _recover_threshold() -> float:
	if _half_width <= 0.0:
		return recover_lateral
	return maxf(recover_lateral, _half_width * 0.8)


## ship_ai.c switches the offset vector instantly. Smoothing it is a Godot
## addition, so the rate has to be fast enough that a zig-zag still completes a
## full swing inside its 50/30 s half period, or the ship only ever wobbles.
func _lane_change_rate() -> float:
	if lane_change_speed > 0.0:
		return lane_change_speed
	return maxf(2.0 * _lane_offset_magnitude() / (50.0 / 30.0) * 1.2, 1.0)


## baked_length / point_count, cached. The Curve3D is rebuilt from its JSON in
## the CenterLine's _ready(), which can land after this ship's own _ready(), so
## the cache is keyed on the curve *and* its point count rather than resolved
## once at configure time.
func _section_length_meters() -> float:
	var curve: Curve3D = center_line.curve if center_line != null else null
	if curve == null:
		return SECTION_LENGTH_FALLBACK
	if curve != _section_length_curve or curve.point_count != _section_length_points:
		_section_length_curve = curve
		_section_length_points = curve.point_count
		var length := curve.get_baked_length()
		if curve.point_count > 0 and length > 0.0:
			_section_length = length / float(curve.point_count)
		else:
			_section_length = SECTION_LENGTH_FALLBACK
	return _section_length


func _wall_avoidance_steer() -> float:
	var left_close := wall_wing_left != null and wall_wing_left.is_colliding()
	var right_close := wall_wing_right != null and wall_wing_right.is_colliding()
	if left_close == right_close:
		return 0.0
	return wall_avoid_steer if left_close else -wall_avoid_steer


## Steady state of _apply_drive_forces(): thrust_mag settles where
## throttle * thrust_max == v / (resistance * max_resistance * resistance_k), so
## that ratio is the throttle which *holds* target_speed. Feeding it forward and
## closing the loop on the error only through speed_gain is what keeps the ship
## on its set point; the previous 1.0 / -0.35 bang-bang ignored the plant
## entirely and overshot the start burst to ~100 m/s before braking back.
func _throttle_for_target_speed() -> float:
	var drag_time := maxf(resistance * max_resistance * resistance_k, 0.001)
	var hold := target_speed / maxf(thrust_max * drag_time, 0.001)
	var correction := (target_speed - velocity.length()) * speed_gain / maxf(thrust_max, 0.001)
	return clampf(hold + correction, -1.0, 1.0)


func _lane_offset_for_strategy() -> float:
	var offset := _lane_offset_magnitude()
	match strategy:
		STRAT_HOLD_LEFT:
			return -offset
		STRAT_HOLD_RIGHT:
			return offset
		STRAT_BLOCK:
			return -offset if _player_on_left() else offset
		STRAT_AVOID:
			return offset if _player_on_left() else -offset
		STRAT_ZIG_ZAG:
			var update_count := int(update_timer * 30.0 / 50.0)
			return offset if (update_count % 2) == 1 else -offset
		_:
			return 0.0


func _player_on_left() -> bool:
	var player := _find_player()
	if player == null:
		return false
	return player.on_left_side


func _find_player() -> WipeoutShip:
	for node in get_tree().get_nodes_in_group(&"ships"):
		var ship := node as WipeoutShip
		if ship != null and ship.is_player_controlled:
			return ship
	return null


func _any_just_in_front() -> bool:
	for node in get_tree().get_nodes_in_group(&"ships"):
		var ship := node as WipeoutShip
		if ship != null and ship.just_in_front:
			return true
	return false


## ship_ai.c: if (cap > speed) speed += accel. A commanded speed already above
## its cap is left alone -- only the cornering bleed brings it back down.
func _accelerate_toward(cap: float, accel: float, delta: float) -> void:
	if cap > target_speed:
		target_speed = minf(target_speed + accel * delta, cap)


## ship_ai.c and ship_player.c both yank an electroed ship every 0.1 s, but not
## the same way: a remote is shaken out of position and loses half its commanded
## speed, where the player gets a yaw jolt and a thrust cut.
func _apply_electro_jolt() -> void:
	global_position += Vector3(
		randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * ELECTRO_SHAKE
	if randi_range(0, 9) == 0:
		target_speed *= 0.5


func _update_dpa(delta: float) -> void:
	just_in_front = false
	if airborne_time > 0.12:
		# Stand-in for the SHIP_FLYING branch: hold center and keep building
		# speed, without the DPA or the cornering bleed.
		strategy = STRAT_HOLD_CENTER
		_accelerate_toward(remote_speed_max, remote_thrust_accel, delta)
		return

	_update_dpa_ground(delta)

	# "General routines - Non decision based": bleed off speed as orientation
	# changes, on both the yaw and the pitch axis.
	target_speed -= absf(target_speed * yaw_velocity) * TURN_SPEED_BLEED * delta
	target_speed -= absf(target_speed * pitch_velocity) * TURN_SPEED_BLEED * delta
	target_speed = maxf(target_speed, 0.0)


func _update_dpa_ground(delta: float) -> void:
	var player := _find_player()
	var section_diff := 0.0
	if player != null:
		section_diff = (race_progress - player.race_progress) / _section_length_meters()

	# Accelerate remotes away at the start; start_accelerate_timer is an
	# exponential progression over the grid, set in configure_from_race().
	if start_accelerate_timer > 0.0:
		start_accelerate_timer -= delta
		update_timer = 0.0
		strategy = STRAT_AVOID
		_accelerate_toward(remote_speed_max + start_burst_bonus,
			remote_thrust_accel + START_BURST_ACCEL, delta)
		return

	# Ship has been left WELL BEHIND: avoid the others, and run a little over its
	# normal cap so it can make a challenge when the player fouls up.
	if section_diff < -10.0:
		update_timer = 0.0
		strategy = STRAT_AVOID
		_accelerate_toward(remote_speed_max + behind_speed_bonus, remote_thrust_accel, delta)
		return

	# Ship is JUST AHEAD.
	if section_diff <= 4.0 and section_diff > 0.0:
		just_in_front = true
		if update_timer <= 0.0:
			update_timer = UPDATE_TIME_JUST_FRONT
			_decide_just_in_front()
		update_timer -= delta
		if overtaken:
			# Just overtaken: hold it to a reasonable speed.
			_accelerate_toward(remote_speed_max + behind_speed_bonus, remote_thrust_accel, delta)
		else:
			_accelerate_toward(remote_speed_max + behind_speed_bonus * 0.5, remote_thrust_accel, delta)
		return

	# Ship is JUST BEHIND: decide if and how it should have a go back.
	if section_diff >= -10.0 and section_diff <= 0.0:
		if update_timer <= 0.0:
			update_timer = UPDATE_TIME_JUST_BEHIND
			_decide_just_behind()
		# If another ship is just in front, pass the fight on.
		if _any_just_in_front():
			strategy = STRAT_AVOID
			overtaken = false
		update_timer -= delta
		if overtaken:
			_accelerate_toward(remote_speed_max + overtaken_bonus, remote_thrust_accel * 2.0, delta)
		else:
			_accelerate_toward(remote_speed_max + behind_speed_bonus, remote_thrust_accel, delta)
		return

	# Ship is WELL AHEAD: slow it down to give the player a chance to catch up.
	if section_diff > float(NUM_PILOTS - position_rank) * 15.0 and section_diff < 150.0:
		target_speed = minf(target_speed + remote_thrust_accel * 0.5 * delta, remote_speed_max * 0.5)
		update_timer = 0.0
		strategy = STRAT_HOLD_CENTER
		return

	# Ship is TOO FAR AHEAD: let it continue.
	if section_diff >= 150.0:
		update_timer = 0.0
		strategy = STRAT_AVOID
		_accelerate_toward(remote_speed_max, remote_thrust_accel, delta)
		return

	# Ship is IN SIGHT.
	if section_diff <= 10.0 and section_diff > 4.0:
		if update_timer <= 0.0:
			update_timer = UPDATE_TIME_IN_SIGHT
			match randi_range(0, 4):
				0:
					strategy = STRAT_HOLD_CENTER
				1:
					strategy = STRAT_HOLD_LEFT
				2:
					strategy = STRAT_HOLD_RIGHT
				3:
					strategy = STRAT_BLOCK
				_:
					strategy = STRAT_ZIG_ZAG
		update_timer -= delta
		_accelerate_toward(remote_speed_max, remote_thrust_accel, delta)
		return

	# Ship is JUST OUT OF SIGHT.
	update_timer = 0.0
	strategy = STRAT_HOLD_CENTER
	_accelerate_toward(remote_speed_max, remote_thrust_accel, delta)


## The rand_int(0, 64) ladder of the JUST AHEAD branch: every outcome blocks, but
## the upper slices also drop mines in the player path or raise a shield.
func _decide_just_in_front() -> void:
	if not fight_back:
		# Let the first ships be easy to pass.
		strategy = STRAT_AVOID
		return
	strategy = STRAT_BLOCK
	if weapon_type == WipeoutWeapon.WeaponType.NONE:
		return
	var chance := randi_range(0, 63)
	if chance < 40:
		return
	if chance < 52:
		if not shield_active and is_racing:
			weapon_type = WipeoutWeapon.WeaponType.MINE
			fire_weapon_delayed(weapon_type)
	elif not shield_active:
		weapon_type = WipeoutWeapon.WeaponType.SHIELD
		fire_weapon(weapon_type)


## The rand_int(0, 64) ladder of the JUST BEHIND branch. An empty slot always
## falls back to avoid + SHIP_OVERTAKEN, which is what earns the +700 catch-up
## boost; with something to fire the ship either blocks or swings out and shoots.
func _decide_just_behind() -> void:
	if not fight_back:
		# Destined to be the tail-ender: slow it right down, for good.
		remote_speed_max = TAIL_ENDER_SPEED
		remote_thrust_accel = TAIL_ENDER_ACCEL
		target_speed = TAIL_ENDER_SPEED
		strategy = STRAT_AVOID
		overtaken = false
		return

	if weapon_type == WipeoutWeapon.WeaponType.NONE:
		strategy = STRAT_AVOID
		overtaken = true
		return

	var chance := randi_range(0, 63)
	if chance < 48:
		strategy = STRAT_BLOCK
		return

	strategy = STRAT_AVOID
	overtaken = false
	if shield_active or not is_racing:
		return
	var player := _find_player()
	if chance < 54:
		weapon_type = WipeoutWeapon.WeaponType.ROCKET
		fire_weapon_delayed(weapon_type)
	elif chance < 60:
		weapon_type = WipeoutWeapon.WeaponType.MISSILE
		fire_weapon_delayed(weapon_type, player)
	else:
		weapon_type = WipeoutWeapon.WeaponType.EBOLT
		fire_weapon_delayed(weapon_type, player)

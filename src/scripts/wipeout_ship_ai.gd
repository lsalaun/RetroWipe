extends WipeoutShip
class_name WipeoutShipAI

## Port of ship_ai.c's DPA (Dynamic Play Adjustment) onto Godot path-following.
## Original remotes do not steer at an offset lookahead point: angular velocity
## follows the section tangent (next.center - section.center) while position is
## attracted onto a parallel ray (center + lane offset). Aiming the player-style
## steer axis at a laterally shifted point overshoots into the walls and bounce-
## zigzags. This controller keeps that split: heading = centerline tangent,
## lane = damped crosstrack, plus wall-probe avoidance.
## Weapons / junction coin-flips are intentionally not ported.

const UPDATE_TIME_JUST_FRONT := 150.0 / 30.0
const UPDATE_TIME_JUST_BEHIND := 200.0 / 30.0
const UPDATE_TIME_IN_SIGHT := 200.0 / 30.0
const NUM_PILOTS := 8
## Godot stand-in for one TRACK.TRS section. DPA thresholds in ship_ai.c are in
## section counts; converting them through curve.point_count is unstable across
## TRS vs Blender-sampled paths, so a fixed meter length is used instead.
const SECTION_LENGTH := 8.0
const SPEED_SCALE := 46.0 / 2600.0

const STRAT_HOLD_CENTER := &"hold_center"
const STRAT_HOLD_LEFT := &"hold_left"
const STRAT_HOLD_RIGHT := &"hold_right"
const STRAT_BLOCK := &"block"
const STRAT_AVOID := &"avoid"
const STRAT_AVOID_OTHER := &"avoid_other"
const STRAT_ZIG_ZAG := &"zig_zag"

@export var lane_offset: float = 0.0 # unused by DPA; kept so existing scene exports still load
@export var lane_width: float = 1.6
@export var lookahead_distance: float = 8.0
@export var target_speed: float = 46.0
@export var steer_gain: float = 1.05
@export var yaw_damp_gain: float = 0.18
@export var crosstrack_gain: float = 2.8
@export var lane_change_speed: float = 1.8
@export var wall_avoid_steer: float = 0.55
@export var recover_lateral: float = 3.2
@export var path_attract: float = 6.0

var fight_back: bool = true
var start_accelerate_timer: float = 0.0
var update_timer: float = 0.0
var strategy: StringName = STRAT_HOLD_CENTER
var overtaken: bool = false
var remote_speed_max: float = 46.0
var behind_speed_bonus: float = 6.0
var start_burst_bonus: float = 1200.0 * SPEED_SCALE
var overtaken_bonus: float = 700.0 * SPEED_SCALE
var inv_start_rank: int = 1
var current_lane: float = 0.0
var _ai_delta: float = 1.0 / 60.0


func configure_from_race(settings: Dictionary, circuit: Dictionary, start_rank_inv: int) -> void:
	inv_start_rank = start_rank_inv
	position_rank = NUM_PILOTS - start_rank_inv
	var psx_max := float(settings.get("thrust_max", 2600.0))
	remote_speed_max = psx_max * SPEED_SCALE
	target_speed = remote_speed_max
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

	if center_line == null or center_line.curve == null or center_line.curve.point_count < 2:
		return result

	var curve := center_line.curve
	var local_pos := center_line.to_local(global_position)
	var offset := curve.get_closest_offset(local_pos)
	var closest_local := curve.sample_baked(offset, true)
	var ahead_local := curve.sample_baked(offset + lookahead_distance, true)
	var path_dir := ahead_local - closest_local
	path_dir.y = 0.0
	if path_dir.length_squared() < 0.0001:
		return result
	path_dir = path_dir.normalized()
	var path_right := path_dir.cross(Vector3.UP)
	if path_right.length_squared() < 0.0001:
		return result
	path_right = path_right.normalized()

	var closest_global := center_line.to_global(closest_local)
	var lateral := global_position - closest_global
	lateral.y = 0.0
	var center_error := lateral.dot(path_right)
	var desired_lane := _lane_offset_for_strategy()
	if absf(center_error) > recover_lateral:
		desired_lane = 0.0
	current_lane = move_toward(current_lane, desired_lane, lane_change_speed * _ai_delta)
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
	var speed := maxf(velocity.length(), 6.0)
	var yaw_damp := clampf(yaw_velocity * yaw_damp_gain, -0.5, 0.5)
	var lane_steer := clampf(-atan(crosstrack_gain * crosstrack / speed), -0.85, 0.85)
	var wall_steer := _wall_avoidance_steer()
	if absf(crosstrack) > recover_lateral:
		wall_steer = 0.0
	result.steer = clampf(-heading_error * steer_gain + lane_steer + yaw_damp + wall_steer, -1.0, 1.0)
	var throttle := _throttle_for_target_speed()
	if absf(heading_error) > 0.7:
		throttle = minf(throttle, 0.45)
	result.throttle = throttle
	return result


## ship_ai.c adds 0.5 * (best_path - position) into acceleration so remotes
## stay glued to the section ray. Steering-only cannot recover after a wall
## bounce: heading already matches the tangent, so the ship flies parallel
## to the track outside the lane.
func _pull_to_racing_line(delta: float) -> void:
	if center_line == null or center_line.curve == null or center_line.curve.point_count < 2:
		return
	var curve := center_line.curve
	var offset := curve.get_closest_offset(center_line.to_local(global_position))
	var closest_local := curve.sample_baked(offset, true)
	var ahead_local := curve.sample_baked(offset + 1.0, true)
	var path_dir := ahead_local - closest_local
	path_dir.y = 0.0
	if path_dir.length_squared() < 0.0001:
		return
	path_dir = path_dir.normalized()
	var path_right := path_dir.cross(Vector3.UP)
	if path_right.length_squared() < 0.0001:
		return
	path_right = path_right.normalized()

	var closest_global := center_line.to_global(closest_local)
	var lateral := global_position - closest_global
	lateral.y = 0.0
	var crosstrack := lateral.dot(path_right) - current_lane
	var lateral_vel := velocity.dot(path_right)
	var desired_lat_vel := -crosstrack * path_attract
	velocity += path_right * (desired_lat_vel - lateral_vel) * minf(1.0, 8.0 * delta)

	if absf(crosstrack) > recover_lateral * 2.0:
		global_position -= path_right * crosstrack * minf(1.0, 4.0 * delta)
		var outward := velocity.dot(path_right) * signf(crosstrack)
		if outward > 0.0:
			velocity -= path_right * signf(crosstrack) * outward


func _wall_avoidance_steer() -> float:
	var left_close := wall_wing_left != null and wall_wing_left.is_colliding()
	var right_close := wall_wing_right != null and wall_wing_right.is_colliding()
	if left_close == right_close:
		return 0.0
	return wall_avoid_steer if left_close else -wall_avoid_steer


func _throttle_for_target_speed() -> float:
	var speed := velocity.length()
	if speed < target_speed:
		return 1.0
	if speed > target_speed + 2.0:
		return -0.35
	return clampf((target_speed - speed) * 0.35 + 0.45, 0.0, 1.0)


func _lane_offset_for_strategy() -> float:
	match strategy:
		STRAT_HOLD_LEFT:
			return -lane_width
		STRAT_HOLD_RIGHT:
			return lane_width
		STRAT_BLOCK:
			return -lane_width if _player_on_left() else lane_width
		STRAT_AVOID:
			return lane_width if _player_on_left() else -lane_width
		STRAT_AVOID_OTHER:
			return _avoid_other_lane()
		STRAT_ZIG_ZAG:
			var update_count := int(update_timer * 30.0 / 50.0)
			return lane_width if (update_count % 2) == 1 else -lane_width
		_:
			return 0.0


func _avoid_other_lane() -> float:
	var avoid: WipeoutShip = null
	var best_diff := 100.0
	for node in get_tree().get_nodes_in_group(&"ships"):
		var other := node as WipeoutShip
		if other == null or other == self:
			continue
		var diff := (other.race_progress - race_progress) / SECTION_LENGTH
		if diff < best_diff:
			best_diff = diff
			avoid = other
	if avoid != null and best_diff < 10.0 and best_diff > -2.0:
		return lane_width if avoid.on_left_side else -lane_width
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


func _update_dpa(delta: float) -> void:
	just_in_front = false
	if airborne_time > 0.12:
		strategy = STRAT_HOLD_CENTER
		target_speed = remote_speed_max
		return

	var player := _find_player()
	var section_diff := 0.0
	if player != null:
		section_diff = (race_progress - player.race_progress) / SECTION_LENGTH

	if start_accelerate_timer > 0.0:
		start_accelerate_timer -= delta
		update_timer = 0.0
		strategy = STRAT_AVOID
		target_speed = remote_speed_max + start_burst_bonus
		return

	if section_diff < -10.0:
		update_timer = 0.0
		strategy = STRAT_AVOID
		target_speed = remote_speed_max + behind_speed_bonus
		return

	if section_diff <= 4.0 and section_diff > 0.0:
		just_in_front = true
		if update_timer <= 0.0:
			update_timer = UPDATE_TIME_JUST_FRONT
			strategy = STRAT_BLOCK if fight_back else STRAT_AVOID
		update_timer -= delta
		if overtaken:
			target_speed = remote_speed_max + behind_speed_bonus
		else:
			target_speed = remote_speed_max + behind_speed_bonus * 0.5
		return

	if section_diff >= -10.0 and section_diff <= 0.0:
		if update_timer <= 0.0:
			update_timer = UPDATE_TIME_JUST_BEHIND
			if fight_back:
				if randi_range(0, 63) < 48:
					strategy = STRAT_BLOCK
				else:
					strategy = STRAT_AVOID
					overtaken = false
			else:
				remote_speed_max = 2100.0 * SPEED_SCALE
				target_speed = remote_speed_max
				strategy = STRAT_AVOID
				overtaken = false
		if _any_just_in_front():
			strategy = STRAT_AVOID
			overtaken = false
		update_timer -= delta
		if overtaken:
			target_speed = remote_speed_max + overtaken_bonus
		else:
			target_speed = remote_speed_max + behind_speed_bonus
		return

	if section_diff > float(NUM_PILOTS - position_rank) * 15.0 and section_diff < 150.0:
		target_speed = remote_speed_max * 0.5
		update_timer = 0.0
		strategy = STRAT_HOLD_CENTER
		return

	if section_diff >= 150.0:
		update_timer = 0.0
		strategy = STRAT_AVOID
		target_speed = remote_speed_max
		return

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
		target_speed = remote_speed_max
		return

	update_timer = 0.0
	strategy = STRAT_HOLD_CENTER
	target_speed = remote_speed_max

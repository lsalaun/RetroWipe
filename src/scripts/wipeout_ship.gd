extends Node3D

class_name WipeoutShip


class HoverSample:
	var grounded: bool = false
	var normal: Vector3 = Vector3.UP
	var compression: float = 0.0
	var height: float = 0.0
	var nose_height: float = 0.0

# Wipeout-like defaults: strong track magnet, tight grip, quick yaw response,
# with a grounded hover behavior that keeps the ship glued to the track instead of
# behaving like a generic free-flying drone.
@export var hover_height: float = 2.2
@export var hover_force: float = 92.0 # stronger track magnet keeps the ship planted and more Wipeout-like on the rail
@export var hover_damping: float = 16.0
@export var bounce_restitution: float = 0.875 # ported from ship_player.c hard-bounce velocity reflection attenuation
@export var bounce_margin: float = 0.5 # height below which a soft floor push kicks in, ahead of the hard bounce at height <= 0
@export var nose_pitch_gain: float = 1.6 # ported from ship_player.c:370-377: pitch torque driven by nose/hull height difference
@export var nose_pitch_max: float = 2.25
@export var track_magnet: float = 1.1 # ported from SHIP_TRACK_MAGNET: inverse-height repulsion, pulls back down when above hover_height
@export var gravity: float = 34.0
@export var thrust_max: float = 72.0
@export var thrust_ramp: float = 42.0
@export var thrust_falloff: float = 20.0 # original ramps thrust down at half the ramp-up rate (SHIP_THRUST_FALLOFF = SHIP_THRUST_RATE / 2)
@export var resistance: float = 1.2 # ported from ship_player.c global drag: per-ship multiplier on acceleration -= velocity / resistance
@export var max_resistance: float = 18.0 # ground resistance baseline (higher = less drag), ported from SHIP_MAX_RESISTANCE
@export var min_resistance: float = 6.5 # air resistance baseline (lower = more drag), ported from SHIP_MIN_RESISTANCE
@export var resistance_brake_scale: float = 1.2 # ground resistance reduction per unit of brake input
@export var resistance_k: float = 1.0 # air resistance increase per unit of brake input, and ground resistance tuning multiplier
@export var skid: float = 0.12 # looser grip for quicker, more responsive directional changes
@export var airborne_lateral_friction: float = 0.9
@export var turn_accel: float = 12.5 # much snappier steering response to fix weak turning
@export var turn_reverse_boost: float = 2.8 # ported: counter-steering (opposing current yaw) accelerates at double rate for quick flick-turns
@export var turn_damping: float = 3.2 # less drag on the yaw axis so it responds immediately to input
@export var turn_max: float = 5.4 # higher yaw cap for a faster, more decisive Wipeout-style turn
@export var turn_air_control: float = 0.7
@export var airbrake_rate: float = 5.5
@export var airbrake_drag: float = 20.0
@export var airbrake_turn_factor: float = 0.06
@export var reverse_brake_drag: float = 26.0 # throttle < 0 acts as a brake (airbrake-like), not negative thrust
@export var roll_yaw_gain: float = 0.95 # ported from angular_acceleration.z += (angular_velocity.y - 0.5 * angular_velocity.z)
@export var roll_spring_damping: float = 3.4
@export var align_speed: float = 14.0 # faster orientation snap to match the sharper turn rate
@export var camera_distance: float = 11.0
@export var camera_height: float = 3.8
@export var camera_follow_speed: float = 6.0
@export var wall_push_speed: float = 18.0 # stronger Wipeout wall ejection while staying controlled enough to avoid instability
@export var wall_nose_hit_width: float = 0.58 # tighter nose threshold keeps wall-clips more pointy and Wipeout-like
@export var wall_nose_yaw_k1: float = 0.12 # stronger nose impact yaw magnitude = speed * k1 + k2
@export var wall_nose_yaw_k2: float = 0.85
@export var wall_wing_roll_k: float = 0.18 # stronger wing roll kick on outward wall impact
@export var wall_wing_extra_damping: float = 0.72 # extra velocity damping applied only on wing impacts
@export var wall_impact_cooldown_duration: float = 0.12 # shorter cooldown to keep impact cadence closer to Wipeout
@export var mass: float = 1.0 # ported from ship.c ship_collide_with_ship: mass-weighted velocity exchange between ships
@export var rescue_delay: float = 2.5
@export var rescue_height: float = 4.0
@export var rescue_look_back: float = 8.0 # distance behind the closest track point to re-drop the ship at, approximating the original's "last valid section"
@export var center_line: Path3D # track center line used to rescue the ship back onto the track
@export var is_player_controlled: bool = true
@export var handling: Resource

@onready var hover_points: Array[RayCast3D] = [
	$HoverFrontLeft,
	$HoverFrontRight,
	$HoverRearLeft,
	$HoverRearRight,
]
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var camera_rig: Node3D = $CameraRig
@onready var hull_area: Area3D = $HullArea

var thrust_mag: float = 0.0
var reverse_brake: float = 0.0
var brake_left: float = 0.0
var brake_right: float = 0.0
var yaw_velocity: float = 0.0
var pitch_velocity: float = 0.0
var airborne_time: float = 0.0
var visual_roll: float = 0.0
var roll_rate: float = 0.0
var visual_pitch: float = 0.0
var wall_impact_cooldown: float = 0.0
var desired_forward: Vector3 = Vector3.FORWARD
var last_ground_normal: Vector3 = Vector3.UP
var spawn_transform: Transform3D
var velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group(&"ships")
	if handling != null and handling.has_method("apply_to"):
		handling.call("apply_to", self)
	spawn_transform = global_transform
	desired_forward = -global_transform.basis.z
	last_ground_normal = Vector3.UP
	_snap_camera_to_ship()


## CameraRig has top_level = true so it doesn't inherit the ship's transform;
## without this it starts at the world origin and visibly lerps in over ~1s.
func _snap_camera_to_ship() -> void:
	var forward := -global_transform.basis.z
	camera_rig.global_position = global_position - forward * camera_distance + global_transform.basis.y * camera_height
	camera_rig.look_at(global_position + forward * 10.0 + global_transform.basis.y * 1.2, Vector3.UP)


func _physics_process(delta: float) -> void:
	if _wants_reset() or global_position.y < -25.0:
		_reset_to_spawn()
		return

	var inputs := _gather_inputs()
	var throttle: float = inputs.throttle
	var steer: float = inputs.steer
	var pitch_input: float = inputs.pitch
	var wants_left_brake: bool = inputs.brake_left
	var wants_right_brake: bool = inputs.brake_right

	_update_drive_inputs(throttle, wants_left_brake, wants_right_brake, delta)

	var hover: HoverSample = _sample_hover()
	var grounded: bool = hover.grounded
	var up: Vector3 = hover.normal if grounded else last_ground_normal.slerp(Vector3.UP, min(1.0, airborne_time * 1.5))

	if grounded:
		airborne_time = 0.0
		last_ground_normal = hover.normal
	else:
		airborne_time += delta

	_apply_hover_forces(hover, up, grounded, delta)
	_apply_drive_forces(up, steer, pitch_input, grounded, delta)

	global_position += velocity * delta
	_handle_wall_collisions(up, delta)
	_update_orientation(hover, up, pitch_input, grounded, delta)
	_update_visuals(steer, pitch_input, grounded, delta)
	if is_player_controlled:
		_update_camera(up, delta)

	if airborne_time > rescue_delay:
		_rescue_to_track()


## Returns the frame's control inputs as a Dictionary with keys:
## throttle, steer, pitch, brake_left, brake_right.
## Overridden by AI ships to drive the same physics from path-following logic
## instead of the Input singleton.
func _gather_inputs() -> Dictionary:
	return {
		"throttle": Input.get_axis(&"ship_reverse", &"ship_thrust"),
		"steer": Input.get_axis(&"ship_steer_left", &"ship_steer_right"),
		"pitch": Input.get_axis(&"ship_pitch_down", &"ship_pitch_up"),
		"brake_left": Input.is_action_pressed(&"ship_airbrake_left"),
		"brake_right": Input.is_action_pressed(&"ship_airbrake_right"),
	}


func _update_drive_inputs(throttle: float, wants_left_brake: bool, wants_right_brake: bool, delta: float) -> void:
	if throttle > 0.0:
		thrust_mag = move_toward(thrust_mag, throttle * thrust_max, thrust_ramp * delta)
		reverse_brake = move_toward(reverse_brake, 0.0, airbrake_rate * delta)
	elif throttle < 0.0:
		# throttle < 0 is a brake input, not reverse thrust: ramp thrust down and ramp up a brake factor instead.
		thrust_mag = move_toward(thrust_mag, 0.0, (thrust_ramp + thrust_falloff) * delta)
		reverse_brake = move_toward(reverse_brake, -throttle, airbrake_rate * delta)
	else:
		thrust_mag = move_toward(thrust_mag, 0.0, thrust_falloff * delta)
		reverse_brake = move_toward(reverse_brake, 0.0, airbrake_rate * delta)
	thrust_mag = maxf(thrust_mag, 0.0)

	brake_left = move_toward(brake_left, 1.0 if wants_left_brake else 0.0, airbrake_rate * delta)
	brake_right = move_toward(brake_right, 1.0 if wants_right_brake else 0.0, airbrake_rate * delta)


func _sample_hover() -> HoverSample:
	var sample := HoverSample.new()
	var hit_count := 0
	var normal := Vector3.ZERO
	var compression_sum := 0.0
	var height_sum := 0.0
	var nose_hit_count := 0
	var nose_height_sum := 0.0

	for index in hover_points.size():
		var ray := hover_points[index]
		if not ray.is_colliding():
			continue

		hit_count += 1
		normal += ray.get_collision_normal()
		var hit_distance := ray.global_position.distance_to(ray.get_collision_point())
		height_sum += hit_distance
		compression_sum += clampf(1.0 - hit_distance / hover_height, -1.0, 1.0)

		if index < 2: # HoverFrontLeft / HoverFrontRight approximate the nose height
			nose_hit_count += 1
			nose_height_sum += hit_distance

	sample.grounded = hit_count >= 2
	if sample.grounded:
		normal = (normal / float(hit_count)).normalized()
	else:
		normal = Vector3.UP

	sample.normal = normal
	sample.compression = compression_sum / maxf(1.0, float(hit_count))
	sample.height = height_sum / maxf(1.0, float(hit_count))
	sample.nose_height = nose_height_sum / float(nose_hit_count) if nose_hit_count > 0 else sample.height
	return sample


func _apply_hover_forces(hover: HoverSample, up: Vector3, grounded: bool, delta: float) -> void:
	if grounded:
		# Ported from SHIP_TRACK_MAGNET: repulsion = magnet * (float_height / height - 1).
		# Grows sharply as height -> 0 and turns into a gentle downward pull above hover_height,
		# instead of the original hard clamp-based compression spring.
		var vertical_speed := velocity.dot(up)
		var height := maxf(hover.height, 0.05)
		var repulsion := clampf(track_magnet * (hover_height / height - 1.0) * hover_force, -hover_force * 2.0, hover_force * 6.0)
		velocity += up * repulsion * delta
		velocity -= up * vertical_speed * hover_damping * delta
		velocity += Vector3.DOWN * gravity * 0.35 * delta

		# Ported from ship_player.c: a hard bounce when the hull actually touches the floor,
		# plus a softer push while skimming just under bounce_margin.
		var floor_push_speed := hover_force * 0.5
		if hover.height <= 0.0:
			velocity = velocity.bounce(up) * bounce_restitution
			velocity -= up * (floor_push_speed * delta)
		elif hover.height < bounce_margin:
			velocity += up * (floor_push_speed * delta)
	else:
		velocity += Vector3.DOWN * gravity * delta


func _apply_drive_forces(up: Vector3, steer: float, pitch_input: float, grounded: bool, delta: float) -> void:
	var forward := _planar_forward(up)
	var right := _planar_right(up, forward)
	var planar_velocity := velocity.slide(up)

	var brake_bias := brake_left - brake_right
	var brake_sum := brake_left + brake_right

	# Ported from ship_player.c:365 — pulls velocity toward the ship's forward axis
	# (progressive skid/recovery) instead of just cancelling the lateral component.
	if grounded:
		var forward_velocity := forward * maxf(planar_velocity.dot(forward), 0.0)
		var grip_denominator := maxf(skid + brake_sum * 0.25, 0.001)
		velocity += (forward_velocity - velocity) / grip_denominator * delta
	else:
		var airborne_planar_velocity := velocity.slide(up)
		var airborne_lateral_speed := airborne_planar_velocity.dot(right)
		velocity -= right * airborne_lateral_speed * airborne_lateral_friction * delta

	velocity += forward * thrust_mag * delta

	# Ported from ship_player.c: acceleration -= velocity / resistance applied on all 3 axes
	# (replaces a planar-only drag). Resistance is higher on the ground (less drag) and lower
	# in the air (more drag), both eased by the current brake input (SHIP_MAX/MIN_RESISTANCE split).
	var resistance_effective: float
	if grounded:
		resistance_effective = resistance * (max_resistance - brake_sum * 0.125 * resistance_brake_scale) * resistance_k
	else:
		resistance_effective = min_resistance + brake_sum * resistance_k
	velocity -= velocity * (delta / maxf(resistance_effective, 0.001))

	var forward_speed := planar_velocity.dot(forward)

	if brake_sum > 0.0:
		velocity -= forward * minf(forward_speed, airbrake_drag * brake_sum * delta)
		yaw_velocity += brake_bias * maxf(planar_velocity.length(), 0.0) * airbrake_turn_factor * delta

	if reverse_brake > 0.0:
		velocity -= forward * clampf(forward_speed, 0.0, reverse_brake_drag * reverse_brake * delta)

	# Ported from ship_player.c: steering that opposes the current yaw rate (a quick
	# counter-steer flick) accelerates at double rate instead of the normal ramp.
	var steer_accel := turn_accel if grounded else turn_accel * turn_air_control
	if absf(steer) > 0.01:
		var opposing := (steer > 0.0 and yaw_velocity > 0.0) or (steer < 0.0 and yaw_velocity < 0.0)
		var accel_scale := turn_reverse_boost if opposing else 1.0
		yaw_velocity -= steer * steer_accel * accel_scale * delta
	yaw_velocity = clampf(yaw_velocity, -turn_max, turn_max)

	if absf(steer) < 0.01 and absf(brake_bias) < 0.01:
		yaw_velocity = move_toward(yaw_velocity, 0.0, turn_damping * delta)

	if not grounded and absf(pitch_input) > 0.01:
		velocity += global_transform.basis.y * pitch_input * 8.0 * delta


func _handle_wall_collisions(up: Vector3, delta: float) -> void:
	wall_impact_cooldown = maxf(wall_impact_cooldown - delta, 0.0)
	if wall_impact_cooldown > 0.0:
		return

	var forward := _planar_forward(up)
	var right := _planar_right(up, forward)
	var best_normal := Vector3.ZERO
	var best_contact_offset := Vector3.ZERO
	var best_lateral_offset := 0.0
	var found_hit := false

	for index in hover_points.size():
		var ray := hover_points[index]
		if not ray.is_colliding():
			continue

		var normal := ray.get_collision_normal()
		if absf(normal.y) > 0.45:
			continue

		var ray_contact_offset := ray.get_collision_point() - global_position
		var ray_lateral_offset := ray_contact_offset.dot(right)
		if not found_hit or absf(ray_lateral_offset) > absf(best_lateral_offset):
			best_normal = normal
			best_contact_offset = ray_contact_offset
			best_lateral_offset = ray_lateral_offset
			found_hit = true

	if not found_hit:
		return

	var speed := velocity.length()
	var lateral_offset := best_lateral_offset

	# Stronger Wipeout-style impact response: quick bounce, heavy loss of forward
	# momentum, and a deliberate push away from the wall to avoid sticking.
	var rebound_scale := 0.35
	velocity = velocity.bounce(best_normal) * rebound_scale
	velocity += best_normal * wall_push_speed
	velocity -= forward * clampf(speed * 0.12, 0.0, 18.0)

	if absf(lateral_offset) <= wall_nose_hit_width:
		# Nose hit: strong yaw kick, like a sharp clipping against the wall. The ship
		# snaps away from the side of the hit rather than just sliding along it.
		var yaw_magnitude := speed * wall_nose_yaw_k1 + wall_nose_yaw_k2
		yaw_velocity -= signf(best_normal.dot(right)) * yaw_magnitude
	else:
		# Wing hit: bigger roll and stronger speed loss, closer to Wipeout's wall clips.
		var impact_angle := best_contact_offset.angle_to(forward)
		var roll_magnitude := impact_angle * speed * wall_wing_roll_k
		roll_rate += signf(lateral_offset) * roll_magnitude
		velocity *= wall_wing_extra_damping
		velocity -= right * signf(lateral_offset) * minf(absf(lateral_offset) * 0.8, 8.0)

	wall_impact_cooldown = wall_impact_cooldown_duration


func _update_orientation(hover: HoverSample, up: Vector3, pitch_input: float, grounded: bool, delta: float) -> void:
	var forward := _planar_forward(up)
	desired_forward = forward.rotated(up, yaw_velocity * delta).normalized()

	if grounded:
		# Ported from ship_player.c:370-377: pitch torque driven by the nose/hull height
		# difference, so the nose leads the slope ahead of the generic slerp below.
		var nose_diff := hover.height - hover.nose_height
		pitch_velocity += nose_diff * nose_pitch_gain * delta
		pitch_velocity = clampf(pitch_velocity, -nose_pitch_max, nose_pitch_max)
		desired_forward = desired_forward.rotated(global_transform.basis.x, -pitch_velocity * delta).normalized()
	else:
		pitch_velocity = move_toward(pitch_velocity, 0.0, nose_pitch_gain * 4.0 * delta)
		if absf(pitch_input) > 0.01:
			desired_forward = desired_forward.rotated(global_transform.basis.x, -pitch_input * 0.7 * delta).normalized()

	var right := desired_forward.cross(up).normalized()
	var corrected_forward := up.cross(right).normalized()
	var target_basis := Basis(right, up, -corrected_forward).orthonormalized()
	var transform_copy := global_transform
	transform_copy.basis = transform_copy.basis.slerp(target_basis, minf(1.0, align_speed * delta)).orthonormalized()
	global_transform = transform_copy


func _update_visuals(steer: float, pitch_input: float, grounded: bool, delta: float) -> void:
	var brake_roll := (brake_left - brake_right) * 0.3
	var bank_target := clampf((-steer * 0.55) + brake_roll, -0.65, 0.65)
	var target_pitch := clampf((pitch_input * 0.12) - (velocity.length() * 0.0025), -0.2, 0.18)

	if not grounded:
		target_pitch -= 0.1

	# Spring-damped bank, ported from ship_player.c's roll model:
	# angular_acceleration.z += (angular_velocity.y - 0.5 * angular_velocity.z), then
	# angle.z self-levels back to 0 each frame. The direct steer/brake lean acts as the
	# spring's target and yaw_velocity adds the same automatic banking torque.
	var roll_accel := (bank_target - visual_roll) * 6.0 + roll_yaw_gain * yaw_velocity - roll_spring_damping * roll_rate
	roll_rate += roll_accel * delta
	visual_roll = clampf(visual_roll + roll_rate * delta, -0.75, 0.75)
	visual_pitch = lerpf(visual_pitch, target_pitch, minf(1.0, 4.0 * delta))
	body_mesh.rotation = Vector3(visual_pitch, 0.0, visual_roll)


func _update_camera(up: Vector3, delta: float) -> void:
	var forward := _planar_forward(Vector3.UP)
	var target_position := global_position - forward * camera_distance + up * camera_height
	camera_rig.global_position = camera_rig.global_position.lerp(target_position, minf(1.0, camera_follow_speed * delta))
	camera_rig.look_at(global_position + forward * 10.0 + up * 1.2, Vector3.UP)


func _planar_forward(up: Vector3) -> Vector3:
	var forward := (-global_transform.basis.z).slide(up)
	if forward.length_squared() < 0.0001:
		forward = desired_forward.slide(up)
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	return forward.normalized()


func _planar_right(up: Vector3, forward: Vector3) -> Vector3:
	var right := forward.cross(up)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	return right.normalized()


func _reset_to_spawn() -> void:
	global_transform = spawn_transform
	_reset_dynamic_state()
	desired_forward = -spawn_transform.basis.z


## Ported from the original's rescue: re-drop the ship on the track's center line
## instead of a full reset to spawn, at the closest valid point minus rescue_look_back
## (approximating "last valid section"). Falls back to _reset_to_spawn if there's no
## usable center_line for this track.
func _rescue_to_track() -> void:
	if center_line == null or center_line.curve == null or center_line.curve.point_count < 2:
		_reset_to_spawn()
		return

	var curve := center_line.curve
	var local_pos := center_line.to_local(global_position)
	var offset := maxf(curve.get_closest_offset(local_pos) - rescue_look_back, 0.0)
	var target_local := curve.sample_baked(offset, true)
	var ahead_local := curve.sample_baked(offset + 1.0, true)

	var forward := ahead_local - target_local
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	var target_position := center_line.to_global(target_local) + Vector3.UP * rescue_height

	global_transform = Transform3D(Basis(right, up, -forward).orthonormalized(), target_position)
	_reset_dynamic_state()
	desired_forward = forward


func _reset_dynamic_state() -> void:
	velocity = Vector3.ZERO
	thrust_mag = 0.0
	reverse_brake = 0.0
	brake_left = 0.0
	brake_right = 0.0
	yaw_velocity = 0.0
	roll_rate = 0.0
	visual_roll = 0.0
	wall_impact_cooldown = 0.0
	airborne_time = 0.0


func _get_axis(positive: Key, negative: Key) -> float:
	return float(Input.is_key_pressed(positive)) - float(Input.is_key_pressed(negative))


func _wants_reset() -> bool:
	return is_player_controlled and Input.is_action_pressed(&"ship_reset")
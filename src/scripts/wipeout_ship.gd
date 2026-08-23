extends CharacterBody3D

class_name WipeoutShip


class HoverSample:
	var grounded: bool = false
	var normal: Vector3 = Vector3.UP
	var compression: float = 0.0
	var height: float = 0.0

@export var hover_height: float = 2.2
@export var hover_force: float = 46.0
@export var hover_damping: float = 12.0
@export var track_magnet: float = 0.9 # ported from SHIP_TRACK_MAGNET: inverse-height repulsion, pulls back down when above hover_height
@export var gravity: float = 34.0
@export var thrust_max: float = 70.0
@export var thrust_ramp: float = 40.0
@export var thrust_falloff: float = 20.0 # original ramps thrust down at half the ramp-up rate (SHIP_THRUST_FALLOFF = SHIP_THRUST_RATE / 2)
@export var planar_drag: float = 0.075
@export var skid: float = 0.35 # ported from ship_player.c:365 grip term: relaxation time constant pulling velocity toward forward_velocity (smaller = stronger grip)
@export var airborne_lateral_friction: float = 0.7
@export var turn_accel: float = 5.8
@export var turn_reverse_boost: float = 2.0 # ported: counter-steering (opposing current yaw) accelerates at double rate for quick flick-turns
@export var turn_damping: float = 3.2
@export var turn_max: float = 3.8
@export var turn_air_control: float = 0.6
@export var airbrake_rate: float = 5.0
@export var airbrake_drag: float = 18.0
@export var airbrake_turn_factor: float = 0.028
@export var reverse_brake_drag: float = 22.0 # throttle < 0 acts as a brake (airbrake-like), not negative thrust
@export var roll_yaw_gain: float = 0.8 # ported from angular_acceleration.z += (angular_velocity.y - 0.5 * angular_velocity.z)
@export var roll_spring_damping: float = 3.0
@export var align_speed: float = 10.5
@export var camera_distance: float = 11.0
@export var camera_height: float = 3.8
@export var camera_follow_speed: float = 6.0
@export var wall_bounce_damping: float = 0.45
@export var wall_turn_kick: float = 0.9
@export var rescue_delay: float = 2.5
@export var rescue_height: float = 4.0
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

var thrust_mag: float = 0.0
var reverse_brake: float = 0.0
var brake_left: float = 0.0
var brake_right: float = 0.0
var yaw_velocity: float = 0.0
var airborne_time: float = 0.0
var visual_roll: float = 0.0
var roll_rate: float = 0.0
var visual_pitch: float = 0.0
var desired_forward: Vector3 = Vector3.FORWARD
var last_ground_normal: Vector3 = Vector3.UP
var spawn_transform: Transform3D


func _ready() -> void:
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

	move_and_slide()
	_handle_wall_collisions()
	_update_orientation(up, pitch_input, grounded, delta)
	_update_visuals(steer, pitch_input, grounded, delta)
	if is_player_controlled:
		_update_camera(up, delta)

	if airborne_time > rescue_delay:
		_reset_to_spawn()


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

	for ray in hover_points:
		if not ray.is_colliding():
			continue

		hit_count += 1
		normal += ray.get_collision_normal()
		var hit_distance := ray.global_position.distance_to(ray.get_collision_point())
		height_sum += hit_distance
		compression_sum += clampf(1.0 - hit_distance / hover_height, -1.0, 1.0)

	sample.grounded = hit_count >= 2
	if sample.grounded:
		normal = (normal / float(hit_count)).normalized()
	else:
		normal = Vector3.UP

	sample.normal = normal
	sample.compression = compression_sum / maxf(1.0, float(hit_count))
	sample.height = height_sum / maxf(1.0, float(hit_count))
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
	else:
		velocity += Vector3.DOWN * gravity * delta


func _apply_drive_forces(up: Vector3, steer: float, pitch_input: float, grounded: bool, delta: float) -> void:
	var forward := _planar_forward(up)
	var right := _planar_right(up, forward)

	velocity += forward * thrust_mag * delta

	var brake_bias := brake_left - brake_right
	var brake_sum := brake_left + brake_right

	# Ported from ship_player.c:365 — pulls velocity toward the ship's forward axis
	# (progressive skid/recovery) instead of just cancelling the lateral component.
	if grounded:
		var forward_velocity := forward * velocity.length()
		var grip_denominator := maxf(skid + brake_sum * 0.25, 0.001)
		velocity += (forward_velocity - velocity) / grip_denominator * delta
	else:
		var airborne_planar_velocity := velocity.slide(up)
		var airborne_lateral_speed := airborne_planar_velocity.dot(right)
		velocity -= right * airborne_lateral_speed * airborne_lateral_friction * delta

	var planar_velocity := velocity.slide(up)
	var forward_speed := planar_velocity.dot(forward)
	velocity -= planar_velocity * planar_drag * delta

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


func _handle_wall_collisions() -> void:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var normal := collision.get_normal()
		if absf(normal.y) > 0.45:
			continue

		velocity = velocity.bounce(normal) * wall_bounce_damping
		yaw_velocity -= signf(normal.dot(global_transform.basis.x)) * wall_turn_kick
		break


func _update_orientation(up: Vector3, pitch_input: float, grounded: bool, delta: float) -> void:
	var forward := _planar_forward(up)
	desired_forward = forward.rotated(up, yaw_velocity * delta).normalized()

	if not grounded and absf(pitch_input) > 0.01:
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
	velocity = Vector3.ZERO
	thrust_mag = 0.0
	reverse_brake = 0.0
	brake_left = 0.0
	brake_right = 0.0
	yaw_velocity = 0.0
	roll_rate = 0.0
	visual_roll = 0.0
	airborne_time = 0.0
	desired_forward = -spawn_transform.basis.z


func _get_axis(positive: Key, negative: Key) -> float:
	return float(Input.is_key_pressed(positive)) - float(Input.is_key_pressed(negative))


func _wants_reset() -> bool:
	return is_player_controlled and Input.is_action_pressed(&"ship_reset")
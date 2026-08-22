extends CharacterBody3D

class_name WipeoutShip


class HoverSample:
	var grounded: bool = false
	var normal: Vector3 = Vector3.UP
	var compression: float = 0.0
	var height: float = 0.0

@export var hover_height: float = 2.2
@export var hover_force: float = 54.0
@export var hover_damping: float = 10.0
@export var gravity: float = 34.0
@export var thrust_max: float = 70.0
@export var thrust_ramp: float = 40.0
@export var thrust_falloff: float = 28.0
@export var planar_drag: float = 0.075
@export var lateral_friction: float = 3.8
@export var airborne_lateral_friction: float = 0.6
@export var turn_accel: float = 3.1
@export var turn_damping: float = 4.0
@export var turn_max: float = 2.45
@export var turn_air_control: float = 0.4
@export var airbrake_rate: float = 5.0
@export var airbrake_drag: float = 18.0
@export var airbrake_turn_factor: float = 0.028
@export var align_speed: float = 7.5
@export var camera_distance: float = 11.0
@export var camera_height: float = 3.8
@export var camera_follow_speed: float = 6.0
@export var wall_bounce_damping: float = 0.45
@export var wall_turn_kick: float = 0.9
@export var rescue_delay: float = 2.5
@export var rescue_height: float = 4.0

@onready var hover_points: Array[RayCast3D] = [
	$HoverFrontLeft,
	$HoverFrontRight,
	$HoverRearLeft,
	$HoverRearRight,
]
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var camera_rig: Node3D = $CameraRig

var thrust_mag: float = 0.0
var brake_left: float = 0.0
var brake_right: float = 0.0
var yaw_velocity: float = 0.0
var airborne_time: float = 0.0
var visual_roll: float = 0.0
var visual_pitch: float = 0.0
var desired_forward: Vector3 = Vector3.FORWARD
var last_ground_normal: Vector3 = Vector3.UP
var spawn_transform: Transform3D


func _ready() -> void:
	spawn_transform = global_transform
	desired_forward = -global_transform.basis.z
	last_ground_normal = Vector3.UP


func _physics_process(delta: float) -> void:
	if _wants_reset() or global_position.y < -25.0:
		_reset_to_spawn()
		return

	var throttle := Input.get_axis(&"ship_reverse", &"ship_thrust")
	var steer := Input.get_axis(&"ship_steer_left", &"ship_steer_right")
	var pitch_input := Input.get_axis(&"ship_pitch_down", &"ship_pitch_up")
	var wants_left_brake := Input.is_action_pressed(&"ship_airbrake_left")
	var wants_right_brake := Input.is_action_pressed(&"ship_airbrake_right")

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
	_update_camera(up, delta)

	if airborne_time > rescue_delay:
		_reset_to_spawn()


func _update_drive_inputs(throttle: float, wants_left_brake: bool, wants_right_brake: bool, delta: float) -> void:
	if throttle > 0.0:
		thrust_mag = move_toward(thrust_mag, throttle * thrust_max, thrust_ramp * delta)
	elif throttle < 0.0:
		thrust_mag = move_toward(thrust_mag, 0.0, (thrust_ramp + thrust_falloff) * delta)
	else:
		thrust_mag = move_toward(thrust_mag, 0.0, thrust_falloff * delta)

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
		var vertical_speed := velocity.dot(up)
		var lift: float = hover.compression * hover_force - vertical_speed * hover_damping
		var height_error := hover_height * 0.55 - hover.height
		velocity += up * lift * delta
		velocity += up * height_error * hover_force * 0.45 * delta
		velocity += Vector3.DOWN * gravity * 0.35 * delta
	else:
		velocity += Vector3.DOWN * gravity * delta


func _apply_drive_forces(up: Vector3, steer: float, pitch_input: float, grounded: bool, delta: float) -> void:
	var forward := _planar_forward(up)
	var right := _planar_right(up, forward)

	velocity += forward * thrust_mag * delta

	var planar_velocity := velocity.slide(up)
	var forward_speed := planar_velocity.dot(forward)
	var lateral_speed := planar_velocity.dot(right)
	var lateral_grip := lateral_friction if grounded else airborne_lateral_friction

	velocity -= right * lateral_speed * lateral_grip * delta
	velocity -= planar_velocity * planar_drag * delta

	var brake_bias := brake_left - brake_right
	var brake_sum := brake_left + brake_right
	if brake_sum > 0.0:
		velocity -= forward * minf(forward_speed, airbrake_drag * brake_sum * delta)
		yaw_velocity += brake_bias * maxf(planar_velocity.length(), 0.0) * airbrake_turn_factor * delta

	var steer_accel := turn_accel if grounded else turn_accel * turn_air_control
	yaw_velocity += steer * steer_accel * delta
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
		yaw_velocity += signf(normal.dot(global_transform.basis.x)) * wall_turn_kick
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
	var brake_roll := (brake_right - brake_left) * 0.3
	var target_roll := clampf((-steer * 0.55) + brake_roll + yaw_velocity * -0.18, -0.65, 0.65)
	var target_pitch := clampf((pitch_input * 0.12) - (velocity.length() * 0.0025), -0.2, 0.18)

	if not grounded:
		target_pitch -= 0.1

	visual_roll = lerpf(visual_roll, target_roll, minf(1.0, 6.0 * delta))
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
	brake_left = 0.0
	brake_right = 0.0
	yaw_velocity = 0.0
	airborne_time = 0.0
	desired_forward = -spawn_transform.basis.z


func _get_axis(positive: Key, negative: Key) -> float:
	return float(Input.is_key_pressed(positive)) - float(Input.is_key_pressed(negative))


func _wants_reset() -> bool:
	return Input.is_action_pressed(&"ship_reset")
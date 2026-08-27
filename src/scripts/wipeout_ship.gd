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
# Tuning note: values here are hand-tuned for Godot's meter/variable-delta model, not a
# literal 1:1 conversion of the original's fixed-point/NTSC-30Hz constants (SHIP_TRACK_MAGNET,
# SHIP_MAX_RESISTANCE, etc.) — what's ported faithfully is the *ratio* between related
# constants (e.g. ground_gravity_scale = SHIP_ON_TRACK_GRAVITY / SHIP_FLYING_GRAVITY = 0.375),
# not their absolute magnitude.
@export var hover_height: float = 2.2
@export var hover_force: float = 92.0 # stronger track magnet keeps the ship planted and more Wipeout-like on the rail
@export var hover_damping: float = 16.0
@export var bounce_restitution: float = 0.875 # ported from ship_player.c hard-bounce velocity reflection attenuation
@export var bounce_margin: float = 0.5 # height below which a soft floor push kicks in, ahead of the hard bounce at height <= 0
@export var hover_min_normal_y: float = 0.5 # hover rays with a more horizontal normal are treated as a wall hit, not ground, and ignored
@export var wall_lateral_min: float = 0.45 # |normal · track_right| above this is a side wall. Wipeout edge shelves are ~40° ramps (lateral ~0.70), not vertical walls.
@export var wall_floor_align_min: float = 0.82 # |normal · center-line floor| above this is still the racing surface, even on a steep bank/pitch.
@export var grounded_coyote_time: float = 0.08 # grace period keeping `grounded` true across a single-frame drop to 1 hover hit, to avoid sol/air flicker at track edges/bumps
@export var nose_pitch_gain: float = 1.6 # ported from ship_player.c:370-377: pitch torque driven by nose/hull height difference
@export var nose_pitch_max: float = 2.25
@export var track_magnet: float = 1.1 # ported from SHIP_TRACK_MAGNET: inverse-height repulsion, pulls back down when above hover_height
@export var gravity: float = 34.0 # airborne gravity baseline, ported from SHIP_FLYING_GRAVITY
@export var ground_gravity_scale: float = 0.375 # on-track gravity is weaker than airborne gravity: SHIP_ON_TRACK_GRAVITY / SHIP_FLYING_GRAVITY = 30000/80000
@export var thrust_max: float = 72.0
@export var thrust_ramp: float = 42.0
@export var thrust_falloff: float = 20.0 # original ramps thrust down at half the ramp-up rate (SHIP_THRUST_FALLOFF = SHIP_THRUST_RATE / 2)
@export var resistance: float = 1.2 # ported from ship_player.c global drag: per-ship multiplier on acceleration -= velocity / resistance
@export var max_resistance: float = 18.0 # velocity drag baseline, ported from SHIP_MAX_RESISTANCE (used identically on ground and in the air)
@export var min_resistance: float = 6.5 # air grip divisor baseline, ported from SHIP_MIN_RESISTANCE: how strongly airborne velocity is pulled toward the forward axis
@export var resistance_brake_scale: float = 1.2 # ground/air drag reduction per unit of brake input
@export var resistance_k: float = 1.0 # global drag tuning multiplier
@export var skid: float = 0.12 # ground grip divisor: looser grip for quicker, more responsive directional changes
@export var turn_accel: float = 16.0 # much snappier steering response to fix weak turning
@export var turn_reverse_boost: float = 2.8 # ported: counter-steering (opposing current yaw) accelerates at double rate for quick flick-turns
@export var turn_damping: float = 3.2 # less drag on the yaw axis so it responds immediately to input
@export var turn_max: float = 7.0 # higher yaw cap for a faster, more decisive Wipeout-style turn
@export var turn_air_control: float = 0.9 # gameplay addition, not ported: the original applies the same steering accel on ground and in the air
@export var airbrake_rate: float = 5.5
@export var airbrake_drag: float = 20.0
@export var airbrake_turn_factor: float = 0.06
@export var reverse_brake_drag: float = 26.0 # throttle < 0 acts as a brake (airbrake-like), not negative thrust
@export var roll_yaw_gain: float = 0.95 # ported from angular_acceleration.z += (angular_velocity.y - 0.5 * angular_velocity.z)
@export var roll_spring_damping: float = 3.4
@export var align_speed: float = 14.0 # faster orientation snap to match the sharper turn rate
@export var camera_distance: float = 14.0 # bumped up from the placeholder-box tuning (11.0) to clear the real imported ship models (~8m long, see convert_ships.py)
@export var camera_height: float = 4.6
@export var camera_follow_speed: float = 6.0 # fallback lerp speed, used only when no center_line curve is assigned
@export var camera_spring_accel: float = 0.46875 # ported from camera.c camera_update_race_external: 0.015625 * 30
@export var camera_spring_damping: float = 3.75 # ported from camera.c camera_update_race_external: 0.125 * 30
@export var camera_track_probe: float = 10.0 # look-ahead distance (meters) along center_line, analogous to section->next in camera.c's track ray
@export var wall_push_speed: float = 18.0 # stronger Wipeout wall ejection while staying controlled enough to avoid instability
@export var wall_nose_hit_width: float = 0.58 # tighter nose threshold keeps wall-clips more pointy and Wipeout-like
@export var wall_nose_yaw_k1: float = 0.12 # stronger nose impact yaw magnitude = speed * k1 + k2
@export var wall_nose_yaw_k2: float = 0.85
@export var wall_wing_roll_k: float = 0.18 # stronger wing roll kick on outward wall impact
@export var wall_wing_extra_damping: float = 0.72 # extra velocity damping applied only on wing impacts
@export var wall_impact_cooldown_duration: float = 0.12 # shorter cooldown to keep impact cadence closer to Wipeout
@export var hull_unstick_speed: float = 6.0 # last-resort probe-based push-out if the hull still ends up embedded in geometry (thin wall tunnelled through at high speed); not a physics body, just a nudge along the contact normal
@export var wall_impact_sound: AudioStream # played through WallImpactSFX on a fresh (non-cooldown) wall hit
@export var ship_impact_sound: AudioStream # played through ShipImpactSFX on HullArea.area_entered
@export var ship_impact_cooldown_duration: float = 0.2 # ported from ship.c: last_impact_time > 0.2 gate before playing SFX_CRUNCH
@export var mass: float = 1.0 # ported from ship.c ship_collide_with_ship: mass-weighted velocity exchange between ships
@export var rescue_delay: float = 2.5
@export var rescue_height: float = 4.0
@export var rescue_look_back: float = 8.0 # distance behind the closest track point to re-drop the ship at, approximating the original's "last valid section"
@export var void_fall_margin: float = 25.0 # how far below the last grounded height counts as a fall into the void, not an absolute world Y
@export var center_line: Path3D # track center line used to rescue the ship back onto the track
@export var is_player_controlled: bool = true
@export var handling: Resource
@export var ship_model_scene: PackedScene # imported ship .glb (see tools/psx_track/convert_ships.py); null keeps the placeholder BodyMesh

@onready var hover_points: Array[RayCast3D] = [
	$HoverFrontLeft,
	$HoverFrontRight,
	$HoverRearLeft,
	$HoverRearRight,
]
# Lateral probes against the track trimesh (not hover rays). Order matches
# ship.c: nose first, then left/right wings.
@onready var wall_nose: RayCast3D = $WallNose
@onready var wall_wing_left: RayCast3D = $WallWingLeft
@onready var wall_wing_right: RayCast3D = $WallWingRight
@onready var hull_penetration_probe: ShapeCast3D = $HullPenetrationProbe
@onready var wall_impact_sfx: AudioStreamPlayer3D = $WallImpactSFX
@onready var ship_impact_sfx: AudioStreamPlayer3D = $ShipImpactSFX
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var camera_rig: Node3D = $CameraRig
@onready var hull_area: Area3D = $HullArea
@onready var ship_visual: Node3D = $ShipVisual

var thrust_mag: float = 0.0
var reverse_brake: float = 0.0
var brake_left: float = 0.0
var brake_right: float = 0.0
var yaw_velocity: float = 0.0
var brake_yaw_rate: float = 0.0 # transient heading contribution from differential brake steering, recomputed each frame (no inertia)
var pitch_velocity: float = 0.0
var airborne_time: float = 0.0
var visual_roll: float = 0.0
var roll_rate: float = 0.0
var visual_pitch: float = 0.0
var wall_impact_cooldown: float = 0.0
var ship_impact_cooldown: float = 0.0
var desired_forward: Vector3 = Vector3.FORWARD
var last_ground_normal: Vector3 = Vector3.UP
var last_ground_height: float = 0.0
var grounded_grace_timer: float = 0.0
var spawn_transform: Transform3D
var velocity: Vector3 = Vector3.ZERO
var camera_velocity: Vector3 = Vector3.ZERO # spring state, ported from camera_t.velocity
var race_progress: float = 0.0 # lap * curve_length + offset; analog of ship_t.total_section_num
var lap: int = 0
var on_left_side: bool = false
var just_in_front: bool = false
var position_rank: int = 8
var wall_hit_count: int = 0
var _last_curve_offset: float = -1.0
var _track_right_dir: Vector3 = Vector3.RIGHT # across-lane axis from the nearest center-line tangent and racing-surface normal
var _track_floor_normal: Vector3 = Vector3.UP # racing-surface normal under the center line; steep floors stay aligned with this, edge shelves do not


func _ready() -> void:
	add_to_group(&"ships")
	_apply_handling_profile()
	spawn_transform = global_transform
	desired_forward = -global_transform.basis.z
	last_ground_normal = Vector3.UP
	last_ground_height = global_position.y
	_snap_camera_to_ship()
	if ship_model_scene != null:
		set_ship_model(ship_model_scene)
	if hull_area != null:
		hull_area.area_entered.connect(_on_hull_area_entered)


## Godot-idiomatic stand-in for ship.c's `last_impact_time`-gated `sfx_play_at()`:
## triggered straight off HullArea's own `area_entered` signal instead of a
## polled per-frame timer, and played through a plain AudioStreamPlayer3D.
func _on_hull_area_entered(area: Area3D) -> void:
	if ship_impact_cooldown > 0.0:
		return
	if not (area.get_parent() is WipeoutShip):
		return
	ship_impact_cooldown = ship_impact_cooldown_duration
	_play_sfx(ship_impact_sfx, ship_impact_sound, global_position)


## Same idea for wall impacts: no `last_impact_time` port, just a plain
## AudioStreamPlayer3D triggered at the contact point.
func _play_sfx(player: AudioStreamPlayer3D, stream: AudioStream, at_position: Vector3) -> void:
	if player == null or stream == null:
		return
	player.global_position = at_position
	player.stream = stream
	player.play()


func _apply_handling_profile() -> void:
	if handling != null and handling.has_method("apply_to"):
		handling.call("apply_to", self)


## Overlay team stats from def.teams after the shared ShipHandlingProfile.
## Re-applies the handling resource first so calling this twice does not stack.
func apply_team_attributes(attributes: Resource) -> void:
	_apply_handling_profile()
	if attributes != null and attributes.has_method("apply_to"):
		attributes.call("apply_to", self)


## Swaps the visible hull for an imported ship model, hiding the placeholder
## BodyMesh. Pass null to revert to the placeholder.
func set_ship_model(model_scene: PackedScene) -> void:
	for child in ship_visual.get_children():
		child.queue_free()

	ship_model_scene = model_scene
	if model_scene == null:
		body_mesh.visible = true
		return

	body_mesh.visible = false
	var instance := model_scene.instantiate()
	# Source PRM ship models use +Z as the nose/forward direction (see
	# ship_nose() in ship.c: vec3(0, 0, 512) transformed by the ship's own
	# matrix), while Godot/WipeoutShip treat -Z as forward -- rotate 180°
	# around Y to match, otherwise the model faces backward on the track.
	instance.rotate_y(PI)
	ship_visual.add_child(instance)


## CameraRig has top_level = true so it doesn't inherit the ship's transform;
## without this it starts at the world origin and visibly lerps in over ~1s.
func _snap_camera_to_ship() -> void:
	camera_velocity = Vector3.ZERO
	var forward := -global_transform.basis.z
	camera_rig.global_position = global_position - forward * camera_distance + Vector3.UP * camera_height
	camera_rig.global_transform.basis = _camera_orientation_basis(forward)


## Repositions the ship (used when main.gd picks a track at runtime, after
## spawn_transform was already captured in _ready() with the scene's stale
## placeholder transform) so resets/rescues target the new spot, not the old one.
func respawn_at(new_transform: Transform3D) -> void:
	global_transform = new_transform
	spawn_transform = new_transform
	desired_forward = -new_transform.basis.z
	last_ground_normal = Vector3.UP
	last_ground_height = global_position.y
	_snap_camera_to_ship()


func _physics_process(delta: float) -> void:
	_refresh_track_axes()
	_update_race_progress()
	if _wants_reset() or global_position.y < last_ground_height - void_fall_margin:
		_reset_to_spawn()
		return

	var inputs := _gather_inputs()
	var throttle: float = inputs.throttle
	var steer: float = inputs.steer
	var pitch_input: float = inputs.pitch
	var wants_left_brake: bool = inputs.brake_left
	var wants_right_brake: bool = inputs.brake_right

	_update_drive_inputs(throttle, wants_left_brake, wants_right_brake, delta)

	var hover: HoverSample = _sample_hover(delta)
	var grounded: bool = hover.grounded
	var up: Vector3 = hover.normal if grounded else last_ground_normal.slerp(Vector3.UP, min(1.0, airborne_time * 1.5))

	if grounded:
		airborne_time = 0.0
		last_ground_normal = hover.normal
		last_ground_height = global_position.y
	else:
		airborne_time += delta

	_apply_hover_forces(hover, up, grounded, delta)
	_apply_drive_forces(up, steer, pitch_input, grounded, delta)

	ship_impact_cooldown = maxf(ship_impact_cooldown - delta, 0.0)
	global_position += velocity * delta
	_handle_wall_collisions(up, delta)
	_resolve_hull_penetration(delta)
	_update_orientation(hover, up, pitch_input, grounded, delta)
	_update_visuals(steer, pitch_input, grounded, delta)
	if is_player_controlled:
		_update_camera(delta)

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


func _sample_hover(delta: float) -> HoverSample:
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

		var collision_normal := ray.get_collision_normal()
		if _is_side_wall_normal(collision_normal):
			continue # edge shelf / side wall: hover must not treat this as a ramp to climb
		var matches_racing_surface := absf(collision_normal.dot(_track_floor_normal)) >= wall_floor_align_min
		if not matches_racing_surface and absf(collision_normal.y) < hover_min_normal_y:
			continue # too vertical to be ground/ceiling: this ray clipped a wall, not the track

		hit_count += 1
		normal += collision_normal
		var hit_distance := ray.global_position.distance_to(ray.get_collision_point())
		height_sum += hit_distance
		compression_sum += clampf(1.0 - hit_distance / hover_height, -1.0, 1.0)

		if index < 2: # HoverFrontLeft / HoverFrontRight approximate the nose height
			nose_hit_count += 1
			nose_height_sum += hit_distance

	var raw_grounded := hit_count >= 2
	if raw_grounded:
		grounded_grace_timer = grounded_coyote_time
	else:
		grounded_grace_timer = maxf(grounded_grace_timer - delta, 0.0)
	# A single remaining hit within the grace period still counts as grounded, smoothing out
	# the sol/air flicker that a hard hit_count >= 2 threshold would cause at track edges/bumps.
	sample.grounded = raw_grounded or (hit_count >= 1 and grounded_grace_timer > 0.0)
	if sample.grounded and hit_count > 0:
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
		velocity += Vector3.DOWN * gravity * ground_gravity_scale * delta

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
	var planar_velocity := velocity.slide(up)

	var brake_bias := brake_left - brake_right
	var brake_sum := brake_left + brake_right

	# Ported from ship_player.c:365 (ground) / :410 (air) — pulls velocity toward the ship's
	# forward axis. Ground uses the tight `skid` divisor; air uses the much looser
	# SHIP_MIN_RESISTANCE-based divisor, so grip is far weaker while airborne instead of a
	# separate hand-tuned lateral friction cancel.
	var forward_velocity := forward * maxf(planar_velocity.dot(forward), 0.0)
	var grip_denominator := maxf(skid + brake_sum * 0.25, 0.001) if grounded else maxf(min_resistance + brake_sum * 4.0, 0.001)
	velocity += (forward_velocity - velocity) / grip_denominator * delta

	velocity += forward * thrust_mag * delta

	# Ported from ship_player.c: acceleration -= velocity / resistance applied on all 3 axes.
	# The original reuses this same SHIP_MAX_RESISTANCE-based drag term on the ground and in
	# the air — SHIP_MIN_RESISTANCE only feeds the air grip divisor above, it does not replace
	# this drag term.
	var resistance_effective := resistance * (max_resistance - brake_sum * 0.125 * resistance_brake_scale) * resistance_k
	velocity -= velocity * (delta / maxf(resistance_effective, 0.001))

	var forward_speed := planar_velocity.dot(forward)

	# Ported from ship_player.c: angle.y += brake_dir * speed * k — brake steering is added
	# directly to the heading each frame (see _update_orientation), not accumulated as
	# persistent angular velocity/inertia like the steering input below.
	brake_yaw_rate = 0.0
	if brake_sum > 0.0:
		velocity -= forward * minf(forward_speed, airbrake_drag * brake_sum * delta)
		brake_yaw_rate = brake_bias * maxf(planar_velocity.length(), 0.0) * airbrake_turn_factor

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

	var hit := _sample_wall_probe()
	if hit.is_empty():
		return

	var forward := _planar_forward(up)
	var right := _planar_right(up, forward)
	var best_normal: Vector3 = _flatten_wall_normal(hit["normal"])
	var best_contact_offset: Vector3 = hit["point"] - global_position
	var is_nose: bool = hit["kind"] == &"nose"
	var lateral_offset := best_contact_offset.dot(right)
	var speed := velocity.length()
	var wing_sign := 0.0 if is_nose else (-1.0 if hit["kind"] == &"wing_left" else 1.0)

	# Stronger Wipeout-style impact response: quick bounce, heavy loss of forward
	# momentum, and a deliberate push away from the wall to avoid sticking. This
	# ejection always resolves, cooldown or not, so a thin wall can't be clipped
	# through while the cooldown is active; only the rotational kick below (and
	# any future impact SFX) is throttled by it.
	var rebound_scale := 0.35
	velocity = velocity.bounce(best_normal) * rebound_scale
	velocity += best_normal * wall_push_speed
	velocity -= forward * clampf(speed * 0.12, 0.0, 18.0)
	if not is_nose:
		velocity *= wall_wing_extra_damping
		velocity -= right * wing_sign * minf(absf(lateral_offset) * 0.8, 8.0)

	if wall_impact_cooldown > 0.0:
		return

	wall_hit_count += 1
	_play_sfx(wall_impact_sfx, wall_impact_sound, hit["point"])

	if is_nose:
		var yaw_magnitude := speed * wall_nose_yaw_k1 + wall_nose_yaw_k2
		yaw_velocity -= signf(best_normal.dot(right)) * yaw_magnitude
	else:
		var impact_angle := best_contact_offset.angle_to(forward)
		var roll_magnitude := impact_angle * speed * wall_wing_roll_k
		roll_rate += wing_sign * roll_magnitude

	wall_impact_cooldown = wall_impact_cooldown_duration


## Écart 3 (audit collisions) safety net: the hull's CollisionShape3D is
## intentionally inert (no PhysicsBody3D, so the wipeout feel doesn't get
## reshaped by a generic move_and_slide). If the wall probes above still let
## the hull tunnel into geometry in one frame (thin wall, high speed), nudge
## it back out along the overlapping contact normal instead of switching to
## CharacterBody3D.
func _resolve_hull_penetration(delta: float) -> void:
	if hull_penetration_probe == null:
		return

	hull_penetration_probe.force_shapecast_update()
	if not hull_penetration_probe.is_colliding():
		return

	var push := Vector3.ZERO
	for i in hull_penetration_probe.get_collision_count():
		var n := hull_penetration_probe.get_collision_normal(i)
		if _is_side_wall_normal(n):
			n = _flatten_wall_normal(n)
		push += n
	if push.is_zero_approx():
		return
	push = push.normalized()

	global_position += push * hull_unstick_speed * delta
	var inward := velocity.dot(push)
	if inward < 0.0:
		velocity -= push * inward


## Nose first, then wings — same priority as ship_collide_with_track().
## Hover rays are a fallback: Wipeout side walls are sloped shelves, so a
## purely horizontal probe can miss them while a downward hover ray already
## clipped the ramp.
func _sample_wall_probe() -> Dictionary:
	var nose := _wall_hit_if_side(wall_nose)
	if not nose.is_empty():
		nose["kind"] = &"nose"
		return nose
	var left := _wall_hit_if_side(wall_wing_left)
	if not left.is_empty():
		left["kind"] = &"wing_left"
		return left
	var right := _wall_hit_if_side(wall_wing_right)
	if not right.is_empty():
		right["kind"] = &"wing_right"
		return right
	for index in hover_points.size():
		var hover_hit := _wall_hit_if_side(hover_points[index])
		if hover_hit.is_empty():
			continue
		hover_hit["kind"] = &"wing_left" if index % 2 == 0 else &"wing_right"
		return hover_hit
	return {}


func _wall_hit_if_side(ray: RayCast3D) -> Dictionary:
	if ray == null or not ray.is_colliding():
		return {}
	var normal := ray.get_collision_normal()
	if not _is_side_wall_normal(normal):
		return {}
	return {"normal": normal, "point": ray.get_collision_point()}


## Wipeout track sides are FACE_TRACK_BASE neighbours, not "vertical enough"
## triangles. A steep/banked racing surface still matches the center-line
## floor normal; edge shelves point across the lane instead (~0.70 lateral).
func _is_side_wall_normal(normal: Vector3) -> bool:
	if normal.length_squared() < 0.0001:
		return false
	var n := normal.normalized()
	if absf(n.dot(_track_floor_normal)) >= wall_floor_align_min:
		return false
	if _track_right_dir.length_squared() < 0.0001:
		return absf(n.y) <= 0.45
	return absf(n.dot(_track_right_dir)) >= wall_lateral_min


## Bounce/eject along the lane, not up the shelf, so a 40° edge does not
## become a ramp.
func _flatten_wall_normal(normal: Vector3) -> Vector3:
	if _track_right_dir.length_squared() >= 0.0001:
		var lateral := normal.dot(_track_right_dir)
		if absf(lateral) >= 0.0001:
			return _track_right_dir * signf(lateral)
	var flat := Vector3(normal.x, 0.0, normal.z)
	if flat.length_squared() >= 0.0001:
		return flat.normalized()
	return normal


func _refresh_track_axes() -> void:
	_track_right_dir = _planar_right(Vector3.UP, _planar_forward(Vector3.UP))
	if center_line == null or center_line.curve == null or center_line.curve.point_count < 2:
		return
	var curve := center_line.curve
	var offset := curve.get_closest_offset(center_line.to_local(global_position))
	var closest_local := curve.sample_baked(offset, true)
	var path_dir := curve.sample_baked(offset + 0.5, true) - closest_local
	if path_dir.length_squared() < 0.0001:
		return
	path_dir = path_dir.normalized()
	var floor_n := _sample_centerline_floor_normal(center_line.to_global(closest_local))
	if floor_n.length_squared() >= 0.0001:
		_track_floor_normal = floor_n.normalized()
	var right := path_dir.cross(_track_floor_normal)
	if right.length_squared() < 0.0001:
		right = path_dir.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		return
	_track_right_dir = right.normalized()


func _sample_centerline_floor_normal(world_point: Vector3) -> Vector3:
	if not is_inside_tree():
		return Vector3.ZERO
	var space := get_world_3d().direct_space_state
	if space == null:
		return Vector3.ZERO
	var from := world_point + Vector3.UP * 3.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 16.0)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Vector3.ZERO
	var n: Vector3 = hit["normal"]
	return n


func _update_orientation(hover: HoverSample, up: Vector3, pitch_input: float, grounded: bool, delta: float) -> void:
	var forward := _planar_forward(up)
	# brake_yaw_rate is a transient contribution (ported from ship_player.c's direct
	# angle.y += brake_dir * speed term) applied on top of the integrated yaw_velocity.
	desired_forward = forward.rotated(up, (yaw_velocity + brake_yaw_rate) * delta).normalized()

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


## Ported from camera.c's camera_update_race_external(): the camera's raw chase
## point (behind + above the ship, banking with roll) is pulled by a spring/damper
## toward the nearest point on the track's straight-line direction ray, giving the
## same loose, elastic correction feel as the original instead of a plain lerp.
func _camera_chase_position(delta: float) -> Vector3:
	var forward := -global_transform.basis.z
	var rolled_basis := global_transform.basis.rotated(forward, visual_roll)
	var raw_pos := global_position + rolled_basis * Vector3(0, 0, camera_distance) + Vector3.UP * camera_height

	if center_line == null or center_line.curve == null or center_line.curve.point_count < 2:
		if camera_follow_speed > 0.0:
			return camera_rig.global_position.lerp(raw_pos, minf(1.0, camera_follow_speed * delta))
		camera_velocity = Vector3.ZERO
		return raw_pos

	var curve := center_line.curve
	var offset := curve.get_closest_offset(center_line.to_local(raw_pos))
	var ahead_offset := minf(offset + camera_track_probe, curve.get_baked_length())
	var p_current := center_line.to_global(curve.sample_baked(offset, true))
	var p_ahead := center_line.to_global(curve.sample_baked(ahead_offset, true))

	# ported from vec3_project_to_ray(pos, next->center, camera->section->center)
	var target := p_current
	var ray := p_ahead - p_current
	if ray.length_squared() > 0.0001:
		ray = ray.normalized()
		target = p_current + ray * (raw_pos - p_current).dot(ray)

	var diff_from_center := raw_pos - target
	var accel := diff_from_center
	accel.y += diff_from_center.length() * 0.5
	camera_velocity -= accel * (camera_spring_accel * delta)
	camera_velocity -= camera_velocity * minf(1.0, camera_spring_damping * delta)
	return raw_pos + camera_velocity


## Ported from camera.c: camera->angle = vec3(ship->angle.x, ship->angle.y, 0) --
## builds an orientation directly from the ship's pitch/yaw forward vector (no roll),
## independent of the spring-lagged position so rotation tracks the ship instantly.
func _camera_orientation_basis(forward: Vector3) -> Basis:
	var right := forward.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = global_transform.basis.x
	right = right.normalized()
	var cam_up := right.cross(forward).normalized()
	return Basis(right, cam_up, -forward).orthonormalized()


func _update_camera(delta: float) -> void:
	camera_rig.global_position = _camera_chase_position(delta)
	camera_rig.global_transform.basis = _camera_orientation_basis(-global_transform.basis.z)


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
	last_ground_height = spawn_transform.origin.y


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
	last_ground_height = target_position.y


func _update_race_progress() -> void:
	if center_line == null or center_line.curve == null or center_line.curve.point_count < 2:
		return

	var curve := center_line.curve
	var curve_length := maxf(curve.get_baked_length(), 0.001)
	var local_pos := center_line.to_local(global_position)
	var offset := curve.get_closest_offset(local_pos)
	if _last_curve_offset >= 0.0:
		if _last_curve_offset > curve_length * 0.75 and offset < curve_length * 0.25:
			lap += 1
		elif _last_curve_offset < curve_length * 0.25 and offset > curve_length * 0.75:
			lap -= 1
	_last_curve_offset = offset
	race_progress = float(lap) * curve_length + offset

	var closest_local := curve.sample_baked(offset, true)
	var ahead_local := curve.sample_baked(offset + 0.5, true)
	var path_dir := ahead_local - closest_local
	path_dir.y = 0.0
	if path_dir.length_squared() < 0.0001:
		return
	var right := path_dir.normalized().cross(Vector3.UP)
	var lateral := global_position - center_line.to_global(closest_local)
	lateral.y = 0.0
	on_left_side = lateral.dot(right) < 0.0


func _reset_dynamic_state() -> void:
	velocity = Vector3.ZERO
	camera_velocity = Vector3.ZERO
	thrust_mag = 0.0
	reverse_brake = 0.0
	brake_left = 0.0
	brake_right = 0.0
	yaw_velocity = 0.0
	brake_yaw_rate = 0.0
	roll_rate = 0.0
	visual_roll = 0.0
	wall_impact_cooldown = 0.0
	ship_impact_cooldown = 0.0
	airborne_time = 0.0


func _get_axis(positive: Key, negative: Key) -> float:
	return float(Input.is_key_pressed(positive)) - float(Input.is_key_pressed(negative))


func _wants_reset() -> bool:
	return is_player_controlled and Input.is_action_pressed(&"ship_reset")
extends WipeoutShip
class_name WipeoutShipAI

## Ported from ship_ai.c's ship_ai_update_race(): follow the track's center
## line, offset laterally per the active strategy (hold_left/hold_right/
## hold_center), and steer toward a lookahead point projected onto the path.
## The rank/weapon/rubber-banding DPA logic from the original is out of scope;
## only the core path-following behavior is implemented here.

@export var center_line: Path3D
@export var lane_offset: float = 0.0 # lateral offset from the center line, mirrors hold_left/hold_right strategies
@export var lookahead_distance: float = 14.0
@export var target_speed: float = 46.0
@export var steer_gain: float = 2.4


func _ready() -> void:
	is_player_controlled = false
	super._ready()
	var cam := camera_rig.get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.current = false


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
	var target_local := curve.sample_baked(offset + lookahead_distance, true)

	if absf(lane_offset) > 0.001:
		var ahead_local := curve.sample_baked(offset + lookahead_distance + 0.5, true)
		var path_dir := ahead_local - target_local
		if path_dir.length_squared() > 0.0001:
			var side := path_dir.normalized().cross(Vector3.UP)
			target_local += side * lane_offset

	var target_global := center_line.to_global(target_local)
	var to_target := target_global - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return result

	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var signed_angle := forward.signed_angle_to(to_target.normalized(), Vector3.UP)
	result.steer = clampf(-signed_angle * steer_gain, -1.0, 1.0)
	result.throttle = 1.0 if velocity.length() < target_speed else 0.0
	return result

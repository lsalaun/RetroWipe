extends Resource
class_name ShipHandlingProfile

@export var hover_height: float = 2.2
@export var hover_force: float = 46.0
@export var hover_damping: float = 12.0
@export var track_magnet: float = 0.9
@export var gravity: float = 34.0
@export var thrust_max: float = 70.0
@export var thrust_ramp: float = 40.0
@export var thrust_falloff: float = 20.0
@export var planar_drag: float = 0.075
@export var lateral_friction: float = 4.5
@export var airborne_lateral_friction: float = 0.7
@export var turn_accel: float = 5.8
@export var turn_reverse_boost: float = 2.0
@export var turn_damping: float = 3.2
@export var turn_max: float = 3.8
@export var turn_air_control: float = 0.6
@export var airbrake_rate: float = 5.0
@export var airbrake_drag: float = 18.0
@export var airbrake_turn_factor: float = 0.028
@export var reverse_brake_drag: float = 22.0
@export var roll_yaw_gain: float = 0.8
@export var roll_spring_damping: float = 3.0
@export var align_speed: float = 10.5
@export var camera_distance: float = 11.0
@export var camera_height: float = 3.8
@export var camera_follow_speed: float = 6.0
@export var wall_bounce_damping: float = 0.45
@export var wall_turn_kick: float = 0.9
@export var rescue_delay: float = 2.5
@export var rescue_height: float = 4.0

func apply_to(ship: Node) -> void:
	if not ship:
		return
	ship.hover_height = hover_height
	ship.hover_force = hover_force
	ship.hover_damping = hover_damping
	ship.track_magnet = track_magnet
	ship.gravity = gravity
	ship.thrust_max = thrust_max
	ship.thrust_ramp = thrust_ramp
	ship.thrust_falloff = thrust_falloff
	ship.planar_drag = planar_drag
	ship.lateral_friction = lateral_friction
	ship.airborne_lateral_friction = airborne_lateral_friction
	ship.turn_accel = turn_accel
	ship.turn_reverse_boost = turn_reverse_boost
	ship.turn_damping = turn_damping
	ship.turn_max = turn_max
	ship.turn_air_control = turn_air_control
	ship.airbrake_rate = airbrake_rate
	ship.airbrake_drag = airbrake_drag
	ship.airbrake_turn_factor = airbrake_turn_factor
	ship.reverse_brake_drag = reverse_brake_drag
	ship.roll_yaw_gain = roll_yaw_gain
	ship.roll_spring_damping = roll_spring_damping
	ship.align_speed = align_speed
	ship.camera_distance = camera_distance
	ship.camera_height = camera_height
	ship.camera_follow_speed = camera_follow_speed
	ship.wall_bounce_damping = wall_bounce_damping
	ship.wall_turn_kick = wall_turn_kick
	ship.rescue_delay = rescue_delay
	ship.rescue_height = rescue_height

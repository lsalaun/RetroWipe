extends Resource
class_name TeamAttributes

## Per-team handling from src/wipeout/game.c `def.teams[*].attributes`.
## Values are the original PSX table (thrust/resistance/skid plus the integer
## arguments to TURN_ACCEL / TURN_VEL). They are not copied 1:1 onto
## WipeoutShip: Godot physics uses a different unit/delta model, so `apply_to`
## scales the already-applied ShipHandlingProfile relative to AG Systems Venom.

const REF_MASS := 150.0
const REF_THRUST_MAX := 790.0
const REF_RESISTANCE := 140.0
const REF_TURN_RATE := 160.0
const REF_TURN_RATE_MAX := 2560.0
const REF_SKID := 12.0

@export var team_name: String = ""
@export_enum("Venom:0", "Rapier:1") var race_class: int = 0
@export var mass: float = 150.0
@export var thrust_max: float = 790.0
@export var resistance: float = 140.0
## Argument to TURN_ACCEL() in game.c (not a Godot radian/s value).
@export var turn_rate: float = 160.0
## Argument to TURN_VEL() in game.c (not a Godot radian/s value).
@export var turn_rate_max: float = 2560.0
@export var skid: float = 12.0


func apply_to(ship: Node) -> void:
	if ship == null:
		return
	ship.mass = float(ship.mass) * _ratio(mass, REF_MASS)
	ship.thrust_max = float(ship.thrust_max) * _ratio(thrust_max, REF_THRUST_MAX)
	ship.resistance = float(ship.resistance) * _ratio(resistance, REF_RESISTANCE)
	ship.turn_accel = float(ship.turn_accel) * _ratio(turn_rate, REF_TURN_RATE)
	ship.turn_max = float(ship.turn_max) * _ratio(turn_rate_max, REF_TURN_RATE_MAX)
	ship.skid = float(ship.skid) * _ratio(skid, REF_SKID)


static func _ratio(value: float, reference: float) -> float:
	if reference == 0.0:
		return 1.0
	return value / reference

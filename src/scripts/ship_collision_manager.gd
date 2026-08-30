extends Node
class_name ShipCollisionManager

## Ported from ship.c's ship_collide_with_ship(): resolves every ship pair once per
## physics frame (race/scene-level, not per-ship) to avoid double-processing A<->B.

## Quick reject before the precise HullArea overlap test. Must clear the hull
## box's own full diagonal (4.23 x 1.05 x 8.45, see WipeoutShip.tscn's
## BoxShape3D_hull_area) or two ships approaching nose-to-tail could overlap
## before this check ever lets the Area3D test run.
@export var detection_distance: float = 9.6
## ship.c adds `res * 4` where res is the separation in PSX units. Velocity is in
## the same units, so once both sides are divided by the 106.5 units-per-metre
## scale the factor survives unchanged: 4 m/s of shove per metre of overlap.
@export var push_k: float = 4.0


func _physics_process(_delta: float) -> void:
	var ships := get_tree().get_nodes_in_group(&"ships")
	for i in ships.size():
		var ship_a: WipeoutShip = ships[i]
		if not is_instance_valid(ship_a) or ship_a.hull_area == null:
			continue
		for j in range(i + 1, ships.size()):
			var ship_b: WipeoutShip = ships[j]
			if not is_instance_valid(ship_b) or ship_b.hull_area == null:
				continue
			_resolve_pair(ship_a, ship_b)


func _resolve_pair(ship_a: WipeoutShip, ship_b: WipeoutShip) -> void:
	if ship_a.global_position.distance_squared_to(ship_b.global_position) > detection_distance * detection_distance:
		# ship.c clears SHIP_COLL on both ships in this early-out, so a pair that
		# drifts apart re-arms the crunch. The flag is per-ship and not per-pair in
		# the original, which means a distant pair also re-arms a ship still
		# grinding against a third one; kept as the original has it.
		ship_a.ship_colliding = false
		ship_b.ship_colliding = false
		return
	if not ship_a.hull_area.get_overlapping_areas().has(ship_b.hull_area):
		return

	# Mass-weighted common velocity, then each ship leaves at vc + (vc - v) * 0.5
	# -- past vc, not short of it. That overshoot is the bounce: a head-on pair at
	# +/-10 m/s comes away at -/+5, a restitution of 0.5. Moving them *toward* vc
	# instead (v + (vc - v) * 0.5) leaves both still travelling the way they came,
	# so they grind through each other rather than rebounding.
	var mass_a := maxf(ship_a.mass, 0.001)
	var mass_b := maxf(ship_b.mass, 0.001)
	var combined_velocity := (ship_a.velocity * mass_a + ship_b.velocity * mass_b) / (mass_a + mass_b)
	ship_a.velocity = combined_velocity + (combined_velocity - ship_a.velocity) * 0.5
	ship_b.velocity = combined_velocity + (combined_velocity - ship_b.velocity) * 0.5

	var separation := ship_a.global_position - ship_b.global_position
	ship_a.velocity += separation * push_k
	ship_b.velocity -= separation * push_k

	_play_pair_impact(ship_a, ship_b)


## ship.c:919 plays a single SFX_CRUNCH per pair, at the midpoint between the two
## hulls, and only on the frame contact begins: neither SHIP_COLL flag set, plus a
## 0.2 s gate on the first ship's own impact timer. Each ship used to trigger its
## own sound off HullArea.area_entered, so a collision was heard twice, at each
## hull rather than once between them.
func _play_pair_impact(ship_a: WipeoutShip, ship_b: WipeoutShip) -> void:
	if not ship_a.ship_colliding and not ship_b.ship_colliding \
			and ship_a.ship_impact_cooldown <= 0.0:
		ship_a.ship_impact_cooldown = ship_a.ship_impact_cooldown_duration
		ship_a.play_ship_impact((ship_a.global_position + ship_b.global_position) * 0.5)
	ship_a.ship_colliding = true
	ship_b.ship_colliding = true

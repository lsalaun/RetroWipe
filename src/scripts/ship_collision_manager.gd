extends Node
class_name ShipCollisionManager

## Ported from ship.c's ship_collide_with_ship(): resolves every ship pair once per
## physics frame (race/scene-level, not per-ship) to avoid double-processing A<->B.

@export var detection_distance: float = 6.0 # quick reject before the precise HullArea overlap test
@export var push_k: float = 2.5


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
		return
	if not ship_a.hull_area.get_overlapping_areas().has(ship_b.hull_area):
		return

	# Inelastic, mass-weighted velocity exchange: both ships move halfway toward the
	# shared post-collision velocity instead of a full swap.
	var mass_a := maxf(ship_a.mass, 0.001)
	var mass_b := maxf(ship_b.mass, 0.001)
	var combined_velocity := (ship_a.velocity * mass_a + ship_b.velocity * mass_b) / (mass_a + mass_b)
	ship_a.velocity += (combined_velocity - ship_a.velocity) * 0.5
	ship_b.velocity += (combined_velocity - ship_b.velocity) * 0.5

	var separation := ship_a.global_position - ship_b.global_position
	ship_a.velocity += separation * push_k
	ship_b.velocity -= separation * push_k

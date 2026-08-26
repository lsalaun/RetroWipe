extends Area3D
class_name TrackBoostPad

## Ported from ship_player.c's ship_player_update_race() boost handling:
## `if (face->flags & FACE_BOOST) velocity += track_direction * 30 * dt`. Continuous
## overlap push along the ship's own forward axis, applied every physics frame the
## ship is over the pad (not a one-shot impulse on entry), matching the original's
## per-frame accumulation while on a boost face -- adapted to Godot's meter/
## variable-delta ship model instead of the raw PSX track-section direction (see
## wipeout_ship.gd's tuning note on hand-tuned constants vs. literal PSX conversion).

@export var boost_accel: float = 160.0 # additive velocity along the ship's forward axis, m/s^2
@export var box_size: Vector3 = Vector3(6.0, 4.0, 6.0)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 64 # matches WipeoutShip's HullArea (see WipeoutShip.tscn)
	monitorable = false
	monitoring = true

	# No visual: the boost arrow is already baked into the track texture.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	add_child(shape)


func _physics_process(delta: float) -> void:
	for area in get_overlapping_areas():
		var ship := area.get_parent() as WipeoutShip
		if ship == null:
			continue
		ship.velocity += -ship.global_transform.basis.z * boost_accel * delta


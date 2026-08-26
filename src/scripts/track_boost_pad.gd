extends Area3D
class_name TrackBoostPad

## Ported from ship_player.c's ship_player_update_race() boost handling:
## `if (face->flags & FACE_BOOST) velocity += track_direction * 30 * dt`. Here
## adapted to a discrete trigger area instead of a per-frame track-face check:
## on entering, the ship's velocity gets a one-shot additive push along its
## own current forward axis (instead of the original's continuous per-frame
## nudge along the raw track-section direction, which doesn't map 1:1 to
## Godot's meter/variable-delta ship model -- see wipeout_ship.gd's tuning
## note on hand-tuned constants vs. literal PSX unit conversion).

@export var boost_speed: float = 24.0 # additive velocity along the ship's forward axis, m/s
@export var box_size: Vector3 = Vector3(6.0, 4.0, 6.0)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 64 # matches WipeoutShip's HullArea (see WipeoutShip.tscn)
	monitorable = false
	monitoring = true

	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	visual.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.95, 0.35, 0.7)
	material.emission_enabled = true
	material.emission = Color(0.15, 1.0, 0.2, 1.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visual.material_override = material
	add_child(visual)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	add_child(shape)

	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area3D) -> void:
	var ship := area.get_parent() as WipeoutShip
	if ship == null:
		return
	ship.velocity += -ship.global_transform.basis.z * boost_speed

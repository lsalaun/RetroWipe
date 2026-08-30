extends Area3D

class_name TrackWeaponPad

## Weapon pickup pad, spawned on every FACE_PICKUP_* face by
## track_gameplay_zones.gd. Driving over one fills the ship's empty weapon slot
## with weapon_get_random_type(), then the pad goes dark until it respawns.
##
## The original has no respawn timer -- pads are always live and the ship simply
## has to have an empty slot. `respawn_time` is a gameplay addition that stops a
## single pad from re-arming a ship that camps on it.

## Wider/longer/taller than the original 6x5x6, same reasoning (and same new
## size) as TrackBoostPad's box_size: the pad is spawned axis-aligned at the
## flagged face's centre (track_gameplay_zones.gd), not rotated to the
## track's local direction there, so a generous box is what keeps a ship
## travelling at speed (or hovering a bit high) from clipping past the pad
## without ever overlapping it.
@export var box_size: Vector3 = Vector3(10.0, 6.0, 10.0)
@export var weapon_class: int = 1 # WipeoutWeaponManager.WEAPON_CLASS_ANY
@export var respawn_time: float = 5.0
@export var pad_color: Color = Color(1.0, 0.84, 0.0)
@export var show_visual: bool = false

var _is_active: bool = true
var _visual: Node3D = null
var _material: StandardMaterial3D = null


func _ready() -> void:
	collision_layer = 0
	collision_mask = 64 # matches WipeoutShip's HullArea (see WipeoutShip.tscn)
	monitorable = false
	monitoring = true

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	add_child(shape)

	if show_visual:
		_create_visual()

	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area3D) -> void:
	if not _is_active:
		return
	# race.c only calls track_cycle_pickups() outside a time trial, so no face
	# ever gains FACE_PICKUP_ACTIVE there and no pad can arm anyone. The
	# per-lap turbo in ship.c is that mode's only weapon.
	if WipeoutShip.is_time_trial(get_tree()):
		return
	var ship := area.get_parent() as WipeoutShip
	if ship == null:
		return
	# The original only arms a ship whose slot is empty; a held weapon is never
	# overwritten by driving over another pad.
	if ship.weapon_type != WipeoutWeapon.WeaponType.NONE:
		return

	ship.weapon_type = ship.get_random_weapon(weapon_class)
	# ship.c gates SFX_POWERUP on `self->pilot == g.pilot`: only the player's own
	# pickup is heard, not the seven AI ships collecting theirs.
	if ship.is_player_controlled:
		WipeoutAudio.play_sfx(WipeoutAudio.SFX_POWERUP)
	_play_pickup_effect()
	_set_active(false)
	await get_tree().create_timer(respawn_time).timeout
	_set_active(true)


func _set_active(active: bool) -> void:
	_is_active = active
	if _material != null:
		_material.albedo_color = pad_color if active else pad_color.darkened(0.7)
		_material.emission_energy_multiplier = 0.8 if active else 0.05


func _play_pickup_effect() -> void:
	if _visual == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(_visual, "scale", Vector3(1.4, 1.4, 1.4), 0.1)
	tween.tween_property(_visual, "scale", Vector3.ONE, 0.1)


## Placeholder marker: the real pads are painted into the track texture, so this
## is only here to make pickup locations readable while the feature is young.
func _create_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	var cylinder := CylinderMesh.new()
	cylinder.height = 0.4
	cylinder.top_radius = 1.5
	cylinder.bottom_radius = 1.5
	mesh_instance.mesh = cylinder

	_material = StandardMaterial3D.new()
	_material.albedo_color = pad_color
	_material.emission_enabled = true
	_material.emission = pad_color
	_material.emission_energy_multiplier = 0.8
	mesh_instance.set_surface_override_material(0, _material)

	_visual.add_child(mesh_instance)

	var tween := create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(_visual, "position:y", 0.4, 1.0)
	tween.tween_property(_visual, "position:y", 0.0, 1.0)


func is_active() -> bool:
	return _is_active

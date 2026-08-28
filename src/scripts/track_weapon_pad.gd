extends Area3D

class_name TrackWeaponPad

## Weapon pickup pad on the track. When a ship drives over it, the ship
## receives a random weapon. Can only pick up a weapon once per contact.

# Weapon pad configuration
@export var box_size: Vector3 = Vector3(3.0, 2.0, 3.0)
@export var weapon_class: int = 1  # 1 = ANY, 2 = PROJECTILE_ONLY
@export var respawn_time: float = 5.0  # Time before the pad can give another weapon

# Visual properties
@export var pad_color: Color = Color.YELLOW
@export var show_visual: bool = true

# Internal state
var _ships_on_pad: Dictionary = {}  # Maps ship to time when they got the weapon
var _is_active: bool = true


func _ready() -> void:
	collision_layer = 0
	collision_mask = 64  # Matches WipeoutShip's HullArea
	monitorable = false
	monitoring = true

	# Create collision shape
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	add_child(shape)

	# Create visual indicator (optional)
	if show_visual:
		_create_visual()

	# Connect signals for better tracking
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _physics_process(delta: float) -> void:
	# Check if any ships on the pad should receive a weapon
	var ships_to_remove = []

	for ship in _ships_on_pad:
		if not is_instance_valid(ship):
			ships_to_remove.append(ship)
			continue

		var time_on_pad = _ships_on_pad[ship]
		# Only give weapon once per contact
		if time_on_pad == 0.0:
			_give_weapon_to_ship(ship)
			_ships_on_pad[ship] = delta
		else:
			_ships_on_pad[ship] += delta

	# Clean up invalid entries
	for ship in ships_to_remove:
		_ships_on_pad.erase(ship)


func _on_area_entered(area: Area3D) -> void:
	var ship = area.get_parent() as WipeoutShip
	if ship == null:
		return

	# Only if ship doesn't already have a weapon tracked
	if ship not in _ships_on_pad:
		_ships_on_pad[ship] = 0.0


func _on_area_exited(area: Area3D) -> void:
	var ship = area.get_parent() as WipeoutShip
	if ship == null:
		return

	if ship in _ships_on_pad:
		_ships_on_pad.erase(ship)


func _give_weapon_to_ship(ship: WipeoutShip) -> void:
	"""Give a random weapon to the ship"""
	if not _is_active:
		return

	# Get a random weapon from the weapon manager
	var weapon_type = ship.get_random_weapon(weapon_class)

	# Set the weapon on the ship
	ship.weapon_type = weapon_type

	# Play pickup effect/sound
	_play_pickup_effect(ship)

	# Deactivate the pad and schedule respawn
	_deactivate_pad()
	await get_tree().create_timer(respawn_time).timeout
	_activate_pad()


func _deactivate_pad() -> void:
	"""Deactivate the pad temporarily"""
	_is_active = false

	# Visual feedback - dim the visual
	_update_visual_brightness(0.3)


func _activate_pad() -> void:
	"""Reactivate the pad"""
	_is_active = true

	# Visual feedback - restore brightness
	_update_visual_brightness(1.0)


func _update_visual_brightness(brightness: float) -> void:
	"""Update the visual brightness of the pad"""
	var visual = get_node_or_null("Visual")
	if not visual:
		return

	var mesh_instance = visual.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not mesh_instance:
		return

	var material = mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	if material:
		var color = pad_color * brightness
		color.a = pad_color.a
		material.albedo_color = color
		material.emission_energy_multiplier = 0.8 * brightness


func _play_pickup_effect(ship: WipeoutShip) -> void:
	"""Play a visual/audio effect when weapon is picked up"""
	# Flash effect on visual
	var visual = get_node_or_null("Visual")
	if visual:
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(visual, "scale", Vector3(1.2, 1.2, 1.2), 0.1)
		tween.tween_property(visual, "scale", Vector3(1.0, 1.0, 1.0), 0.1)

	# TODO: Play pickup sound
	# if impact_sound:
	#     impact_sound.global_position = global_position
	#     impact_sound.play()


func _create_visual() -> void:
	"""Create a visual representation of the weapon pad"""
	var visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)

	# Create a simple cylinder mesh to represent the pad
	var mesh_instance = MeshInstance3D.new()
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.height = 0.5
	cylinder_mesh.radius = 1.5
	mesh_instance.mesh = cylinder_mesh

	# Create material
	var material = StandardMaterial3D.new()
	material.albedo_color = pad_color
	material.emission_enabled = true
	material.emission = pad_color
	material.emission_energy_multiplier = 0.8
	mesh_instance.set_surface_override_material(0, material)

	visual.add_child(mesh_instance)

	# Add animation to the visual
	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(visual, "position:y", 0.3, 1.0)
	tween.tween_property(visual, "position:y", 0.0, 1.0)


func is_active() -> bool:
	"""Check if the pad is currently active"""
	return _is_active


func get_weapon_class() -> int:
	"""Get the weapon class this pad provides"""
	return weapon_class


func set_weapon_class(new_class: int) -> void:
	"""Set the weapon class this pad provides"""
	weapon_class = new_class

extends Node3D

class_name WipeoutWeapon

# Weapon types matching the C implementation
enum WeaponType {
	NONE = 0,
	MINE = 1,
	MISSILE = 2,
	ROCKET = 3,
	SPECIAL = 4,
	EBOLT = 5,
	FLARE = 6,
	REV_CON = 7,
	SHIELD = 8,
	TURBO = 9,
}

# Hit types
enum HitType {
	NONE = 0,
	SHIP = 1,
	TRACK = 2,
}

# Weapon durations (in seconds, converted from NTSC frames)
const MINE_DURATION = 450.0 / 30.0
const ROCKET_DURATION = 200.0 / 30.0
const EBOLT_DURATION = 140.0 / 30.0
const REV_CON_DURATION = 60.0 / 30.0
const MISSILE_DURATION = 200.0 / 30.0
const SHIELD_DURATION = 200.0 / 30.0
const FLARE_DURATION = 200.0 / 30.0
const SPECIAL_DURATION = 400.0 / 30.0
const MINE_RELEASE_RATE = 3.0 / 30.0
const WEAPON_DELAY = 40.0 / 30.0
const MINE_COUNT = 5

# Weapon configuration
const WEAPON_PARTICLE_SPAWN_RATE = 0.011
const AI_DELAY = 1.1

# Collision detection
const SHIP_COLLISION_RADIUS = 0.5  # Godot units
const MIN_TRACK_HEIGHT = 2.0  # Godot units
const TARGET_PUSH_HEIGHT = 0.2  # Godot units

# Weapon model paths
const WEAPON_MODELS = {
	WeaponType.ROCKET: "res://src/assets/weapons/rocket.glb",
	WeaponType.MINE: "res://src/assets/weapons/mine.glb",
	WeaponType.MISSILE: "res://src/assets/weapons/missile.glb",
	WeaponType.SHIELD: "res://src/assets/weapons/shield.glb",
	WeaponType.EBOLT: "res://src/assets/weapons/ebolt.glb",
}

# Properties
var owner_ship: WipeoutShip
var target_ship: WipeoutShip
var weapon_type: WeaponType = WeaponType.NONE
var timer: float = 0.0
var active: bool = false
var mine_count: int = 0  # For multi-mine weapons

# Physics properties
var velocity: Vector3 = Vector3.ZERO
var acceleration: Vector3 = Vector3.ZERO
var drag: float = 0.0
var trail_spawn_timer: float = 0.0

# Visual properties
var model: Node3D
var trail_particles: Array[Node3D] = []

# Audio
var impact_sound: AudioStreamPlayer3D

# For delayed firing (mines)
var release_timer: float = 0.0
var is_waiting_for_release: bool = false


func _ready() -> void:
	add_to_group(&"weapons")
	impact_sound = AudioStreamPlayer3D.new()
	add_child(impact_sound)


func _physics_process(delta: float) -> void:
	if not active:
		return

	timer -= delta

	# Handle delayed mine release
	if is_waiting_for_release:
		release_timer -= delta
		if release_timer <= 0:
			_initialize_mine()
		return

	# Check if weapon has expired
	if timer <= 0:
		_deactivate()
		return

	# Handle projectiles with velocity and acceleration
	if acceleration != Vector3.ZERO or velocity != Vector3.ZERO:
		# Apply acceleration
		if acceleration != Vector3.ZERO:
			velocity += acceleration * delta

		# Apply drag
		if drag > 0:
			velocity *= (1.0 - drag * delta * 30.0)

		# Update position
		global_position += velocity * delta * 30.0

	# Update animations/effects
	match weapon_type:
		WeaponType.MINE:
			if model:
				model.rotation.y += delta * 2.0  # Spin animation
		WeaponType.SHIELD:
			if model:
				model.global_position = owner_ship.global_position
				model.global_rotation = owner_ship.global_rotation

	# Follow target for guided weapons
	if target_ship and weapon_type in [WeaponType.MISSILE, WeaponType.EBOLT]:
		_follow_target()

	# Check for collisions
	if _check_track_collision():
		_on_track_hit()
	else:
		var hit_ship = _check_ship_collision()
		if hit_ship:
			_on_ship_hit(hit_ship)


func fire(ship: WipeoutShip, wtype: WeaponType, target: WipeoutShip = null) -> void:
	"""Fire a weapon from a ship"""
	owner_ship = ship
	target_ship = target
	weapon_type = wtype
	active = true
	global_position = ship.global_position
	global_rotation = ship.global_rotation

	match wtype:
		WeaponType.MINE:
			_fire_mine()
		WeaponType.MISSILE:
			_fire_missile()
		WeaponType.ROCKET:
			_fire_rocket()
		WeaponType.EBOLT:
			_fire_ebolt()
		WeaponType.SHIELD:
			_fire_shield()
		WeaponType.TURBO:
			_fire_turbo()


func _fire_mine() -> void:
	"""Drop a mine - waits before activating"""
	is_waiting_for_release = true
	release_timer = MINE_RELEASE_RATE
	timer = MINE_DURATION
	_load_model(WeaponType.MINE)


func _initialize_mine() -> void:
	"""Initialize the mine after release timer"""
	is_waiting_for_release = false
	if model:
		model.visible = true


func _fire_missile() -> void:
	"""Fire a guided missile"""
	timer = MISSILE_DURATION
	drag = 0.25
	_set_trajectory()
	_load_model(WeaponType.MISSILE)


func _fire_rocket() -> void:
	"""Fire a fast rocket"""
	timer = ROCKET_DURATION
	drag = 0.03125
	_set_trajectory()
	_load_model(WeaponType.ROCKET)


func _fire_ebolt() -> void:
	"""Fire an electric bolt"""
	timer = EBOLT_DURATION
	drag = 0.25
	_set_trajectory()
	_load_model(WeaponType.EBOLT)


func _fire_shield() -> void:
	"""Apply a shield to the ship"""
	timer = SHIELD_DURATION
	_load_model(WeaponType.SHIELD)
	owner_ship.apply_shield()


func _fire_turbo() -> void:
	"""Apply turbo boost to the ship"""
	var forward = -owner_ship.global_transform.basis.z
	owner_ship.velocity += forward * 39321.0 / 1024.0  # Adjusted for Godot scale
	_deactivate()


func _set_trajectory() -> void:
	"""Set initial trajectory from ship"""
	var ship = owner_ship
	var forward = -ship.global_transform.basis.z

	# Set acceleration to move forward from the ship
	acceleration = forward * 256.0
	velocity = ship.velocity * 0.015625


func _follow_target() -> void:
	"""Make weapon follow the target"""
	if not target_ship:
		return

	var direction = (target_ship.global_position - global_position).normalized()

	# Update rotation to face target
	var target_rotation_y = -atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation_y, 0.25)

	# Update acceleration to move toward target
	acceleration = direction * 256.0


func _load_model(wtype: WeaponType) -> void:
	"""Load the 3D model for the weapon"""
	if wtype not in WEAPON_MODELS:
		return

	# Remove old model if it exists
	if model and is_instance_valid(model):
		model.queue_free()

	var model_path = WEAPON_MODELS[wtype]
	var scene = load(model_path) as PackedScene
	if scene:
		model = scene.instantiate()
		add_child(model)

		# For mines, initially hide until released
		if wtype == WeaponType.MINE:
			model.visible = false


func _check_ship_collision() -> WipeoutShip:
	"""Check for collision with other ships"""
	for ship in get_tree().get_nodes_in_group("ships"):
		if ship == owner_ship:
			continue

		var distance = global_position.distance_to(ship.global_position)
		if distance < SHIP_COLLISION_RADIUS:
			return ship

	return null


func _check_track_collision() -> bool:
	"""Check for collision with track using raycast"""
	# TODO: Implement track collision detection using raycasts
	# For now, assume no track collision
	return false


func _on_ship_hit(ship: WipeoutShip) -> void:
	"""Handle weapon hitting a ship"""
	# Play impact sound
	_play_impact_sound(global_position)

	match weapon_type:
		WeaponType.MINE:
			_mine_hit_ship(ship)
		WeaponType.MISSILE:
			_missile_hit_ship(ship)
		WeaponType.ROCKET:
			_rocket_hit_ship(ship)
		WeaponType.EBOLT:
			_ebolt_hit_ship(ship)

	_deactivate()


func _on_track_hit() -> void:
	"""Handle weapon hitting the track"""
	_play_impact_sound(global_position)
	_deactivate()


func _mine_hit_ship(ship: WipeoutShip) -> void:
	"""Mine impact effect: slow down significantly"""
	if not ship.has_shield():
		ship.velocity *= 0.125


func _missile_hit_ship(ship: WipeoutShip) -> void:
	"""Missile impact effect: heavy damage"""
	if not ship.has_shield():
		ship.velocity *= 0.03125
		ship.velocity.y += randf_range(-0.2, 0.2)


func _rocket_hit_ship(ship: WipeoutShip) -> void:
	"""Rocket impact effect: moderate damage"""
	if not ship.has_shield():
		ship.velocity *= 0.25


func _ebolt_hit_ship(ship: WipeoutShip) -> void:
	"""Electric bolt impact effect: disable controls"""
	if not ship.has_shield():
		ship.apply_electro_effect(EBOLT_DURATION)


func _play_impact_sound(position: Vector3) -> void:
	"""Play impact sound at position"""
	if impact_sound and impact_sound.stream:
		impact_sound.global_position = position
		impact_sound.play()


func _deactivate() -> void:
	"""Deactivate and remove the weapon"""
	active = false

	# Remove shield effect if applicable
	if weapon_type == WeaponType.SHIELD and owner_ship:
		owner_ship.remove_shield()

	queue_free()

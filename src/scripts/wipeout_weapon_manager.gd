extends Node

class_name WipeoutWeaponManager

## Singleton manager for all active weapons in the race
## Handles weapon spawning, updates, and weapon type selection

signal weapon_fired(ship: WipeoutShip, weapon_type: WipeoutWeapon.WeaponType)

const MAX_WEAPONS = 64
const WEAPON_CLASS_ANY = 1
const WEAPON_CLASS_PROJECTILE = 2

# Weapon probability tables for random drops
const WEAPON_PROBABILITIES_ANY = {
	WipeoutWeapon.WeaponType.ROCKET: 0.26,      # 17/65
	WipeoutWeapon.WeaponType.MINE: 0.28,        # 18/65
	WipeoutWeapon.WeaponType.SHIELD: 0.15,      # 10/65
	WipeoutWeapon.WeaponType.MISSILE: 0.12,     # 8/65
	WipeoutWeapon.WeaponType.TURBO: 0.09,       # 6/65
	WipeoutWeapon.WeaponType.EBOLT: 0.10,       # 6/65
}

const WEAPON_PROBABILITIES_PROJECTILE = {
	WipeoutWeapon.WeaponType.ROCKET: 0.45,      # 27/60
	WipeoutWeapon.WeaponType.MISSILE: 0.22,     # 13/60
	WipeoutWeapon.WeaponType.TURBO: 0.17,       # 10/60
	WipeoutWeapon.WeaponType.EBOLT: 0.16,       # 10/60
}

var weapons: Array[WipeoutWeapon] = []
var weapon_scene: PackedScene
var ship_weapons: Dictionary = {}  # Maps ship node to their current weapon
var weapon_fire_delays: Dictionary = {}  # For delayed weapon firing


func _ready() -> void:
	set_process(true)

	# Load the weapon scene
	weapon_scene = load("res://scenes/wipeout_weapon.tscn")


func _process(_delta: float) -> void:
	# Update weapon fire delays
	var keys_to_remove = []
	for ship in weapon_fire_delays:
		weapon_fire_delays[ship] -= _delta
		if weapon_fire_delays[ship] <= 0:
			keys_to_remove.append(ship)

	for ship in keys_to_remove:
		weapon_fire_delays.erase(ship)


func fire_weapon(ship: WipeoutShip, weapon_type: WipeoutWeapon.WeaponType, target: WipeoutShip = null) -> WipeoutWeapon:
	"""Fire a weapon from a ship"""
	# Special case for mines: create multiple weapons with delays
	if weapon_type == WipeoutWeapon.WeaponType.MINE:
		var last_weapon: WipeoutWeapon = null
		var timer = 0.0
		for i in range(WipeoutWeapon.MINE_COUNT):
			if weapons.size() >= MAX_WEAPONS:
				break
			timer += WipeoutWeapon.MINE_RELEASE_RATE
			var weapon = _create_mine_weapon(ship, timer)
			if weapon:
				weapons.append(weapon)
				last_weapon = weapon
		weapon_fired.emit(ship, weapon_type)
		return last_weapon

	if weapons.size() >= MAX_WEAPONS:
		return null

	var weapon = _create_weapon(ship, weapon_type, target)
	if weapon:
		weapons.append(weapon)
		weapon_fired.emit(ship, weapon_type)

	return weapon


func fire_weapon_delayed(ship: WipeoutShip, weapon_type: WipeoutWeapon.WeaponType, target: WipeoutShip = null) -> void:
	"""Fire a weapon with a delay (for AI)"""
	weapon_fire_delays[ship] = WipeoutWeapon.AI_DELAY
	await get_tree().create_timer(WipeoutWeapon.AI_DELAY).timeout
	fire_weapon(ship, weapon_type, target)


func get_random_weapon(weapon_class: int = WEAPON_CLASS_ANY) -> WipeoutWeapon.WeaponType:
	"""Get a random weapon type based on probability tables"""
	var probabilities = WEAPON_PROBABILITIES_ANY if weapon_class == WEAPON_CLASS_ANY else WEAPON_PROBABILITIES_PROJECTILE
	var rand = randf()
	var cumulative = 0.0

	for weapon_type in probabilities:
		cumulative += probabilities[weapon_type]
		if rand < cumulative:
			return weapon_type

	return WipeoutWeapon.WeaponType.ROCKET


func _create_weapon(ship: WipeoutShip, weapon_type: WipeoutWeapon.WeaponType, target: WipeoutShip = null) -> WipeoutWeapon:
	"""Create and initialize a new weapon"""
	var weapon: WipeoutWeapon

	if weapon_scene:
		weapon = weapon_scene.instantiate() as WipeoutWeapon
	else:
		weapon = WipeoutWeapon.new()

	get_tree().root.add_child(weapon)
	weapon.fire(ship, weapon_type, target)

	return weapon


func _create_mine_weapon(ship: WipeoutShip, timer: float) -> WipeoutWeapon:
	"""Create a mine weapon with a specific release timer"""
	var weapon: WipeoutWeapon

	if weapon_scene:
		weapon = weapon_scene.instantiate() as WipeoutWeapon
	else:
		weapon = WipeoutWeapon.new()

	get_tree().root.add_child(weapon)
	weapon.owner_ship = ship
	weapon.weapon_type = WipeoutWeapon.WeaponType.MINE
	weapon.active = true
	weapon.global_position = ship.global_position
	weapon.global_rotation = ship.global_rotation
	weapon.is_waiting_for_release = true
	weapon.release_timer = timer
	weapon.timer = WipeoutWeapon.MINE_DURATION
	weapon._load_model(WipeoutWeapon.WeaponType.MINE)

	return weapon


func clear_all_weapons() -> void:
	"""Remove all active weapons from the scene"""
	for weapon in weapons:
		if is_instance_valid(weapon):
			weapon.queue_free()
	weapons.clear()


func get_active_weapons_count() -> int:
	"""Get the count of active weapons"""
	return weapons.size()

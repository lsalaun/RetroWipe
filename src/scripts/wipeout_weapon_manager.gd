extends Node

class_name WipeoutWeaponManager

## Autoloaded singleton (`WeaponManager`) owning every live weapon, ported from
## weapon.c's flat `weapons[WEAPONS_MAX]` array plus `weapons_fire()` /
## `weapons_update()`. Because it is an autoload it survives scene changes, so
## `clear_all_weapons()` stands in for `weapons_init()` at the start of a race.

signal weapon_fired(ship: WipeoutShip, weapon_type: WipeoutWeapon.WeaponType)

const MAX_WEAPONS = 64
const WEAPON_CLASS_ANY = 1
const WEAPON_CLASS_PROJECTILE = 2

## Cumulative weights straight from weapon_get_random_type()'s `rand_int(0, 65)`
## ladder, kept as raw slice widths so the table reads like the C source.
const WEAPON_WEIGHTS_ANY = [
	[WipeoutWeapon.WeaponType.ROCKET, 17],
	[WipeoutWeapon.WeaponType.MINE, 18],
	[WipeoutWeapon.WeaponType.SHIELD, 10],
	[WipeoutWeapon.WeaponType.MISSILE, 8],
	[WipeoutWeapon.WeaponType.TURBO, 6],
	[WipeoutWeapon.WeaponType.EBOLT, 6],
]

## The `rand_int(0, 60)` ladder from the same function.
const WEAPON_WEIGHTS_PROJECTILE = [
	[WipeoutWeapon.WeaponType.ROCKET, 27],
	[WipeoutWeapon.WeaponType.MISSILE, 13],
	[WipeoutWeapon.WeaponType.TURBO, 10],
	[WipeoutWeapon.WeaponType.EBOLT, 10],
]

var weapons: Array[WipeoutWeapon] = []
var weapon_scene: PackedScene

static var _fallback: WipeoutWeaponManager = null


## Resolves the `WeaponManager` autoload *without* naming it as a global
## identifier. The `validate_*.gd` tools run under `--script`, which boots a bare
## SceneTree with no autoloads registered, and a direct `WeaponManager.…`
## reference fails to **compile** there -- taking every validator down with it,
## not just the weapon ones. Looking the node up by path keeps those runs
## compiling, and the fallback keeps them exercising the weapon path.
static func instance(tree: SceneTree) -> WipeoutWeaponManager:
	if tree == null:
		return null
	var node := tree.root.get_node_or_null(^"WeaponManager")
	if node is WipeoutWeaponManager:
		return node
	if _fallback != null and is_instance_valid(_fallback):
		return _fallback
	_fallback = WipeoutWeaponManager.new()
	_fallback.name = "WeaponManager"
	tree.root.add_child(_fallback)
	return _fallback


func _ready() -> void:
	weapon_scene = load("res://scenes/wipeout_weapon.tscn") as PackedScene


func _process(_delta: float) -> void:
	# weapons_update() compacts its array by swapping the last entry over any
	# released weapon; here the weapon frees itself, so we just drop the stale
	# references it leaves behind.
	var live: Array[WipeoutWeapon] = []
	for weapon in weapons:
		if is_instance_valid(weapon) and weapon.active:
			live.append(weapon)
	weapons = live


func fire_weapon(ship: WipeoutShip, weapon_type: WipeoutWeapon.WeaponType, target: WipeoutShip = null) -> WipeoutWeapon:
	"""Fire a weapon from a ship. Mirrors weapons_fire()."""
	# weapon_fire_mine() queues WEAPON_MINE_COUNT weapons at once, each with its
	# own staggered release timer.
	if weapon_type == WipeoutWeapon.WeaponType.MINE:
		var last_weapon: WipeoutWeapon = null
		var release_timer := 0.0
		for i in WipeoutWeapon.MINE_COUNT:
			if weapons.size() >= MAX_WEAPONS:
				break
			release_timer += WipeoutWeapon.MINE_RELEASE_RATE
			var mine := _spawn_weapon()
			if mine == null:
				break
			mine.fire_mine_delayed(ship, release_timer)
			weapons.append(mine)
			last_weapon = mine
		weapon_fired.emit(ship, weapon_type)
		return last_weapon

	if weapons.size() >= MAX_WEAPONS:
		return null

	var weapon := _spawn_weapon()
	if weapon == null:
		return null
	weapon.fire(ship, weapon_type, target)
	weapons.append(weapon)
	weapon_fired.emit(ship, weapon_type)
	return weapon


func fire_weapon_delayed(ship: WipeoutShip, weapon_type: WipeoutWeapon.WeaponType, target: WipeoutShip = null) -> void:
	"""weapons_fire_delayed(): AI ships sit on a weapon for WEAPON_AI_DELAY first."""
	await get_tree().create_timer(WipeoutWeapon.AI_DELAY).timeout
	if not is_instance_valid(ship):
		return
	fire_weapon(ship, weapon_type, target)


func get_random_weapon(weapon_class: int = WEAPON_CLASS_ANY) -> WipeoutWeapon.WeaponType:
	"""weapon_get_random_type(): weighted pick over the class's ladder."""
	var weights := WEAPON_WEIGHTS_ANY if weapon_class == WEAPON_CLASS_ANY else WEAPON_WEIGHTS_PROJECTILE
	var total := 0
	for entry in weights:
		total += int(entry[1])

	var roll := randi() % total
	for entry in weights:
		roll -= int(entry[1])
		if roll < 0:
			return entry[0]
	return WipeoutWeapon.WeaponType.ROCKET


## Weapons parent to the running scene, not to this autoload, so leaving a race
## takes them with it.
func _spawn_weapon() -> WipeoutWeapon:
	# current_scene is null under `--script`, where the tools instance the scene
	# by hand; the tree root is the right owner there.
	var parent: Node = get_tree().current_scene
	if parent == null:
		parent = get_tree().root
	if parent == null:
		return null

	var weapon: WipeoutWeapon
	if weapon_scene != null:
		weapon = weapon_scene.instantiate() as WipeoutWeapon
	else:
		weapon = WipeoutWeapon.new()
	parent.add_child(weapon)
	return weapon


func clear_all_weapons() -> void:
	"""weapons_init(): drop everything still in flight before a new race."""
	for weapon in weapons:
		if is_instance_valid(weapon):
			weapon.queue_free()
	weapons.clear()


func get_active_weapons_count() -> int:
	return weapons.size()

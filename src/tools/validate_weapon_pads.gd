extends SceneTree

## Headless check of the weapon pickup chain: the track spawns pads, driving the
## player into one fills its empty weapon slot, firing spends the slot and puts a
## live weapon in the scene.

const WAIT_FRAMES := 240

var _main: Node3D = null
var _failures: Array[String] = []


func _initialize() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("main.tscn failed to load")
		quit(1)
		return
	_main = scene.instantiate() as Node3D
	root.add_child(_main)


func _process(_delta: float) -> bool:
	# One frame is enough for _ready() to run across the tree.
	_run_checks()
	_report()
	return true


func _run_checks() -> void:
	# 1. The weapon scene and its models resolve (res:// is godot/src, so a
	# "res://src/..." path would silently yield null here).
	if load("res://scenes/wipeout_weapon.tscn") == null:
		_failures.append("wipeout_weapon.tscn failed to load")
	for wtype in WipeoutWeapon.WEAPON_MODELS:
		var path: String = WipeoutWeapon.WEAPON_MODELS[wtype]
		if load(path) == null:
			_failures.append("weapon model missing: %s" % path)

	# 2. The manager resolves (autoload in game, fallback under --script).
	var manager := WipeoutWeaponManager.instance(self)
	if manager == null:
		_failures.append("weapon manager could not be resolved")
		return

	# 3. The random table only ever yields weapons the port implements.
	for i in 200:
		var picked: int = manager.get_random_weapon(manager.WEAPON_CLASS_ANY)
		if WipeoutWeapon.weapon_name(picked).is_empty():
			_failures.append("get_random_weapon returned unimplemented type %d" % picked)
			break

	# 4. The track actually spawned pads.
	var pads := _find_pads(_main)
	if pads.is_empty():
		_failures.append("no TrackWeaponPad spawned on the track")

	# 5. A ship parked on a pad picks a weapon up, and only while its slot is empty.
	var player := _find_player()
	if player == null:
		_failures.append("no player ship found")
		return
	if not pads.is_empty():
		var pad: Area3D = pads[0]
		player.weapon_type = WipeoutWeapon.WeaponType.NONE
		pad._on_area_entered(player.get_node("HullArea"))
		if player.weapon_type == WipeoutWeapon.WeaponType.NONE:
			_failures.append("driving onto a pad did not arm the ship")
		# A pad must never overwrite a weapon the ship is already holding.
		var held := player.weapon_type
		player.weapon_type = WipeoutWeapon.WeaponType.ROCKET
		pad._on_area_entered(player.get_node("HullArea"))
		if player.weapon_type != WipeoutWeapon.WeaponType.ROCKET:
			_failures.append("pad overwrote a weapon the ship was already holding")
		print("  pads=%d  first pickup=%s" % [pads.size(), WipeoutWeapon.weapon_name(held)])

	# 6. Firing spends the slot and puts a weapon in the scene.
	player.weapon_type = WipeoutWeapon.WeaponType.ROCKET
	player.weapon_fire_cooldown = 0.0
	player.fire_held_weapon()
	if player.weapon_type != WipeoutWeapon.WeaponType.NONE:
		_failures.append("firing did not clear the weapon slot")
	if manager.get_active_weapons_count() == 0:
		_failures.append("firing did not spawn a weapon")


func _find_pads(node: Node) -> Array[Area3D]:
	var found: Array[Area3D] = []
	if node is TrackWeaponPad:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_pads(child))
	return found


func _find_player() -> WipeoutShip:
	for node in get_nodes_in_group(&"ships"):
		var ship := node as WipeoutShip
		if ship != null and ship.is_player_controlled:
			return ship
	return null


func _report() -> void:
	if _failures.is_empty():
		print("OK: weapon pickup chain works")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
		print("FAIL: %s" % failure)
	quit(1)

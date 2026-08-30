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

	# 1b. The fire action exists. Without it the player can never spend a weapon,
	# so the first pickup sticks forever and every later pad refuses to re-arm a
	# full slot -- which reads as "the pads only ever give one weapon".
	if not InputMap.has_action(&"ship_fire"):
		_failures.append("input action 'ship_fire' is not registered")
	else:
		var events := InputMap.action_get_events(&"ship_fire")
		print("  ship_fire bound to %d event(s)" % events.size())
		if events.is_empty():
			_failures.append("input action 'ship_fire' has no events bound")

	# 2. The manager resolves (autoload in game, fallback under --script).
	var manager := WipeoutWeaponManager.instance(self)
	if manager == null:
		_failures.append("weapon manager could not be resolved")
		return

	# 3. The random table yields every implemented type, in the proportions
	# weapon_get_random_type() uses. A table that collapses onto one weapon still
	# "works" from every other angle, so the distribution itself is the check.
	var counts := {}
	const SAMPLES := 6000
	for i in SAMPLES:
		var picked: int = manager.get_random_weapon(manager.WEAPON_CLASS_ANY)
		if WipeoutWeapon.weapon_name(picked).is_empty():
			_failures.append("get_random_weapon returned unimplemented type %d" % picked)
			break
		counts[picked] = int(counts.get(picked, 0)) + 1

	var total_weight := 0
	for entry in manager.WEAPON_WEIGHTS_ANY:
		total_weight += int(entry[1])
	for entry in manager.WEAPON_WEIGHTS_ANY:
		var wtype: int = entry[0]
		var expected := float(entry[1]) / float(total_weight)
		var actual := float(counts.get(wtype, 0)) / float(SAMPLES)
		print("  %-8s expected %5.1f%%  actual %5.1f%%" % [
			WipeoutWeapon.weapon_name(wtype), expected * 100.0, actual * 100.0
		])
		# Generous band: this catches a collapsed or mis-indexed table, not noise.
		if absf(actual - expected) > 0.06:
			_failures.append("%s drawn %.1f%% of the time, expected %.1f%%" % [
				WipeoutWeapon.weapon_name(wtype), actual * 100.0, expected * 100.0
			])

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

		# Walk every pad with an empty slot: what the player actually receives
		# should vary, not collapse onto one type.
		var via_pads := {}
		var hull := player.get_node("HullArea")
		for p in pads:
			p._is_active = true
			player.weapon_type = WipeoutWeapon.WeaponType.NONE
			p._on_area_entered(hull)
			var got := WipeoutWeapon.weapon_name(player.weapon_type)
			via_pads[got] = int(via_pads.get(got, 0)) + 1
		print("  via pads over %d pickups: %s" % [pads.size(), via_pads])
		if via_pads.size() == 1:
			_failures.append("every pad handed out the same weapon: %s" % via_pads.keys())

	# 5b. The shield bubble must stay see-through, or it hides the ship it is
	# protecting (weapon_update_shield draws it at alpha 48/255).
	player.weapon_type = WipeoutWeapon.WeaponType.SHIELD
	player.fire_held_weapon()
	var shield: WipeoutWeapon = null
	for w in manager.weapons:
		if w.weapon_type == WipeoutWeapon.WeaponType.SHIELD:
			shield = w
			break
	if shield == null:
		_failures.append("firing a shield spawned no shield weapon")
	elif shield._shield_material == null:
		_failures.append("shield has no translucent material applied")
	else:
		var alpha := shield._shield_material.albedo_color.a
		print("  shield alpha=%.2f transparency=%d" % [alpha, shield._shield_material.transparency])
		if shield._shield_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED or alpha >= 0.9:
			_failures.append("shield material is opaque (alpha %.2f)" % alpha)
	player.remove_shield()

	# 6. Firing spends the slot and puts a weapon in the scene.
	player.weapon_type = WipeoutWeapon.WeaponType.ROCKET
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

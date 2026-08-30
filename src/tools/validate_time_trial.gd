extends SceneTree

## Headless check of the two things src/wipeout does differently in a time
## trial, both of which are visible in the HUD's weapon slot:
##
##   race.c:81   skips track_cycle_pickups(), so no face is ever
##               FACE_PICKUP_ACTIVE and no pad can arm the ship.
##   ship.c:508  grants WEAPON_TYPE_TURBO on every new lap instead, the
##               crossing at GO included.
##
## Together they mean the slot in a time trial only ever holds a turbo. The HUD's
## own time-trial guards (no POSITION, no lives) are plain race_type tests in
## _draw_position()/_draw_lives() and are checked visually.

var _main: Node3D = null
var _setup: Node = null
var _restore_race_type: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_setup = root.get_node_or_null("RaceSetup")
	if _setup == null:
		push_error("RaceSetup autoload not found")
		quit(1)
		return
	_restore_race_type = _setup.race_type
	# Set before main.tscn instantiates: the track builds its ship field off the
	# race type, and a time trial is meant to spawn the player alone.
	_setup.race_type = _setup.RACE_TYPE_TIME_TRIAL

	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("main.tscn failed to load")
		quit(1)
		return
	_main = scene.instantiate() as Node3D
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_run_checks()
	_setup.race_type = _restore_race_type
	_report()
	return true


func _run_checks() -> void:
	_check_is_time_trial()

	var ship := _find_player(_main)
	if ship == null:
		_failures.append("no player-controlled ship in main.tscn")
		return
	var pad := _find_pad(_main)
	if pad == null:
		_failures.append("no TrackWeaponPad in main.tscn")
		return
	var hull := ship.get_node_or_null("HullArea") as Area3D
	if hull == null:
		_failures.append("player ship has no HullArea")
		return

	_check_lap_turbo(ship)
	_check_pad_gating(ship, pad, hull)


## The helper both fixes route through. A wrong answer here silently disables
## both of them, so it is asserted on its own rather than only through them.
func _check_is_time_trial() -> void:
	for race_type in [_setup.RACE_TYPE_CHAMPIONSHIP, _setup.RACE_TYPE_SINGLE, _setup.RACE_TYPE_TIME_TRIAL]:
		_setup.race_type = race_type
		var expected: bool = race_type == _setup.RACE_TYPE_TIME_TRIAL
		var got := WipeoutShip.is_time_trial(self)
		if got != expected:
			_failures.append("is_time_trial() = %s for race_type %d, expected %s" % [got, race_type, expected])
	if WipeoutShip.is_time_trial(null):
		_failures.append("is_time_trial(null) should be false, not true")


## ship.c grants the turbo inside the `lap > max_lap` branch and *before* its own
## `lap > 0` guard, so the crossing at GO arms the player too. Both crossings are
## exercised: an unarmed lap 0 and an unarmed lap 1.
func _check_lap_turbo(ship: WipeoutShip) -> void:
	_setup.race_type = _setup.RACE_TYPE_TIME_TRIAL
	for start_lap in [-1, 0]:
		ship.lap = start_lap
		ship.max_lap = start_lap
		ship.weapon_type = WipeoutWeapon.WeaponType.NONE
		ship._cross_start_line()
		if ship.weapon_type != WipeoutWeapon.WeaponType.TURBO:
			_failures.append("time trial: crossing to lap %d left weapon %d, expected TURBO" % [
				start_lap + 1, ship.weapon_type])

	# A re-crossing that is not a new max lap changes nothing in the original --
	# the whole branch is skipped -- so it must not hand out a turbo either.
	ship.lap = 0
	ship.max_lap = 5
	ship.weapon_type = WipeoutWeapon.WeaponType.NONE
	ship._cross_start_line()
	if ship.weapon_type != WipeoutWeapon.WeaponType.NONE:
		_failures.append("time trial: re-crossing an already-run lap granted weapon %d" % ship.weapon_type)

	# Outside a time trial the grant must not fire at all, or every race would
	# hand the player a free turbo per lap.
	for race_type in [_setup.RACE_TYPE_CHAMPIONSHIP, _setup.RACE_TYPE_SINGLE]:
		_setup.race_type = race_type
		ship.lap = -1
		ship.max_lap = -1
		ship.weapon_type = WipeoutWeapon.WeaponType.NONE
		ship._cross_start_line()
		if ship.weapon_type != WipeoutWeapon.WeaponType.NONE:
			_failures.append("race_type %d: lap crossing granted weapon %d, expected none" % [
				race_type, ship.weapon_type])


func _check_pad_gating(ship: WipeoutShip, pad: TrackWeaponPad, hull: Area3D) -> void:
	_setup.race_type = _setup.RACE_TYPE_TIME_TRIAL
	ship.weapon_type = WipeoutWeapon.WeaponType.NONE
	pad._set_active(true)
	pad._on_area_entered(hull)
	if ship.weapon_type != WipeoutWeapon.WeaponType.NONE:
		_failures.append("time trial: a weapon pad armed the player with %d" % ship.weapon_type)
	if not pad.is_active():
		_failures.append("time trial: a weapon pad went dark despite arming nobody")

	# The same pad must still work in the modes that do cycle pickups, otherwise
	# the guard has simply broken pickups everywhere.
	for race_type in [_setup.RACE_TYPE_CHAMPIONSHIP, _setup.RACE_TYPE_SINGLE]:
		_setup.race_type = race_type
		ship.weapon_type = WipeoutWeapon.WeaponType.NONE
		pad._set_active(true)
		pad._on_area_entered(hull)
		if ship.weapon_type == WipeoutWeapon.WeaponType.NONE:
			_failures.append("race_type %d: weapon pad failed to arm the player" % race_type)
	ship.weapon_type = WipeoutWeapon.WeaponType.NONE


func _find_player(node: Node) -> WipeoutShip:
	var ship := node as WipeoutShip
	if ship != null and ship.is_player_controlled:
		return ship
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null


func _find_pad(node: Node) -> TrackWeaponPad:
	var pad := node as TrackWeaponPad
	if pad != null:
		return pad
	for child in node.get_children():
		var found := _find_pad(child)
		if found != null:
			return found
	return null


func _report() -> void:
	if _failures.is_empty():
		print("validate_time_trial: OK")
		quit(0)
		return
	for failure in _failures:
		printerr("  FAIL: %s" % failure)
	printerr("validate_time_trial: %d failure(s)" % _failures.size())
	quit(1)

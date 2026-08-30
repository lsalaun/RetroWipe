extends SceneTree

## Headless check of the weapon chain for AI ships -- the half validate_weapon_pads
## does not touch, since that one drives the player.
##
## ship_ai.c reaches for a weapon at two decision points, each a rand_int(0, 64)
## ladder guarded by fight_back / SHIP_SHIELDED / SHIP_RACING:
##
##   JUST IN FRONT (ship_ai.c:181)  block 40/64, mines 12/64, shield 12/64
##   JUST BEHIND   (ship_ai.c:239)  block 48/64, rocket 6/64, missile 6/64,
##                                  e-bolt 4/64
##
## The ladders are sampled rather than asserted once: a ladder that collapsed
## onto a single outcome would still "fire weapons" from every other angle, so
## the proportions are the check. Each decision is made distinguishable by
## seeding the slot with TURBO, a type neither ladder can ever produce.

const WAIT_FRAMES := 600
const SAMPLES := 3200
const TOLERANCE := 0.03
## 1.1 s of WEAPON_AI_DELAY at 60 Hz, with room to spare.
const DELAY_FRAMES := 150

var _main: Node3D = null
var _setup: Node = null
var _restore_race_type: int = 0
var _failures: Array[String] = []
var _frames := 0
var _stage := 0
var _delay_deadline := 0
var _weapons_before := 0
var _delay_ai: WipeoutShipAI = null


func _initialize() -> void:
	_setup = root.get_node_or_null("RaceSetup")
	if _setup == null:
		push_error("RaceSetup autoload not found")
		quit(1)
		return
	_restore_race_type = _setup.race_type
	# A time trial spawns no AI at all (race.c), so the field needs a championship.
	_setup.race_type = _setup.RACE_TYPE_CHAMPIONSHIP

	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		push_error("main.tscn failed to load")
		quit(1)
		return
	_main = scene.instantiate() as Node3D
	root.add_child(_main)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	# RaceDirector holds the grid for UPDATE_TIME_INITIAL before GO; the AI is
	# only meaningfully "racing" well after that.
	if _frames < WAIT_FRAMES:
		return false

	if _stage == 0:
		_run_checks()
		_stage = 1
		return false
	if _stage == 1 and _frames >= _delay_deadline:
		_check_delayed_arrival()
		_setup.race_type = _restore_race_type
		_report()
		return true
	return false


func _run_checks() -> void:
	var manager := WipeoutWeaponManager.instance(self)
	if manager == null:
		_failures.append("weapon manager could not be resolved")
		return

	var ai_ships := _find_ai_ships(_main)
	if ai_ships.is_empty():
		_failures.append("no AI ships in a championship race")
		return
	print("  AI ships in field: %d" % ai_ships.size())
	var player := _find_player(_main)
	if player == null:
		_failures.append("no player-controlled ship")
		return

	_check_ai_pickup(ai_ships[0])
	_check_player_pickup_class(player)
	_check_just_in_front_ladder(ai_ships[0])
	_check_just_behind_ladder(ai_ships[0])
	_purge_weapons(manager)
	_check_gates(ai_ships[0])
	_check_immediate_fire(manager, ai_ships[0])
	_check_no_fire_lockout(manager, player)
	_check_damage_table(manager, ai_ships[0], player)
	_start_delayed_fire(manager, ai_ships[1] if ai_ships.size() > 1 else ai_ships[0])


## ship.c:445 -- an AI driving over a live pad takes the `else` branch and gets
## weapon_type = 1, i.e. WEAPON_TYPE_MINE. The value barely matters (both ladders
## overwrite it before firing) but a *non-empty* slot is what unlocks them, so an
## AI that cannot arm from a pad is an AI that never fights back.
func _check_ai_pickup(ai: WipeoutShipAI) -> void:
	var pad := _find_pad(_main)
	if pad == null:
		_failures.append("no TrackWeaponPad in the track")
		return
	var hull := ai.get_node_or_null("HullArea") as Area3D
	if hull == null:
		_failures.append("AI ship has no HullArea, so no pad can ever reach it")
		return
	# Sampled rather than checked once: `= 1` is a constant in the original, so a
	# port that rolled a random type would still pass a single lucky draw.
	var seen := {}
	for i in 200:
		ai.weapon_type = WipeoutWeapon.WeaponType.NONE
		pad._set_active(true)
		pad._on_area_entered(hull)
		if ai.weapon_type == WipeoutWeapon.WeaponType.NONE:
			_failures.append("a weapon pad did not arm an AI ship")
			return
		seen[ai.weapon_type] = true
	if seen.size() != 1 or not seen.has(WipeoutWeapon.WeaponType.MINE):
		_failures.append("an AI pickup must always be MINE (ship.c `weapon_type = 1`), got %d distinct type(s)" % seen.size())
	else:
		print("  AI pad pickup -> always MINES, over 200 draws")


## ship.c:438 -- the player's draw is class-dependent: shielded restricts it to
## WEAPON_CLASS_PROJECTILE, which contains neither SHIELD nor MINE.
func _check_player_pickup_class(player: WipeoutShip) -> void:
	var pad := _find_pad(_main)
	var hull := player.get_node_or_null("HullArea") as Area3D
	if pad == null or hull == null:
		_failures.append("no pad/HullArea for the player pickup check")
		return

	var banned := [WipeoutWeapon.WeaponType.SHIELD, WipeoutWeapon.WeaponType.MINE]
	player.fire_weapon(WipeoutWeapon.WeaponType.SHIELD)
	if not player.has_shield():
		_failures.append("could not raise the player's shield for the pickup check")
		return
	var shielded := {}
	for i in 400:
		player.weapon_type = WipeoutWeapon.WeaponType.NONE
		pad._set_active(true)
		pad._on_area_entered(hull)
		shielded[player.weapon_type] = true
		if player.weapon_type in banned:
			_failures.append("a shielded player drew %s, which WEAPON_CLASS_PROJECTILE excludes" % (
				WipeoutWeapon.weapon_name(player.weapon_type)))
			break
	player.remove_shield()
	print("  shielded player draws: %d distinct type(s), none of them SHIELD/MINE" % shielded.size())

	# Unshielded, the full table is back -- otherwise the guard above would have
	# been "fixed" by simply narrowing every player pickup.
	var unshielded := {}
	for i in 800:
		player.weapon_type = WipeoutWeapon.WeaponType.NONE
		pad._set_active(true)
		pad._on_area_entered(hull)
		unshielded[player.weapon_type] = true
	for wtype in banned:
		if not unshielded.has(wtype):
			_failures.append("an unshielded player never drew %s; WEAPON_CLASS_ANY must still offer it" % (
				WipeoutWeapon.weapon_name(wtype)))
	player.weapon_type = WipeoutWeapon.WeaponType.NONE


func _check_just_in_front_ladder(ai: WipeoutShipAI) -> void:
	var counts := {"block": 0, "mine": 0, "shield": 0, "other": 0}
	for i in SAMPLES:
		_arm_for_sample(ai)
		ai._decide_just_in_front()
		match ai.weapon_type:
			WipeoutWeapon.WeaponType.TURBO: counts["block"] += 1
			WipeoutWeapon.WeaponType.MINE: counts["mine"] += 1
			# weapons_fire() clears the slot the moment the shield goes up.
			WipeoutWeapon.WeaponType.NONE: counts["shield"] += 1
			_: counts["other"] += 1
	_expect(counts, "JUST IN FRONT", {"block": 40.0 / 64.0, "mine": 12.0 / 64.0, "shield": 12.0 / 64.0})


func _check_just_behind_ladder(ai: WipeoutShipAI) -> void:
	var counts := {"block": 0, "rocket": 0, "missile": 0, "ebolt": 0, "other": 0}
	for i in SAMPLES:
		_arm_for_sample(ai)
		ai._decide_just_behind()
		match ai.weapon_type:
			WipeoutWeapon.WeaponType.TURBO: counts["block"] += 1
			WipeoutWeapon.WeaponType.ROCKET: counts["rocket"] += 1
			WipeoutWeapon.WeaponType.MISSILE: counts["missile"] += 1
			WipeoutWeapon.WeaponType.EBOLT: counts["ebolt"] += 1
			_: counts["other"] += 1
	_expect(counts, "JUST BEHIND", {
		"block": 48.0 / 64.0, "rocket": 6.0 / 64.0, "missile": 6.0 / 64.0, "ebolt": 4.0 / 64.0})


## TURBO is the seed because neither ladder can produce it: whatever comes out is
## unambiguously the decision, not the seed.
func _arm_for_sample(ai: WipeoutShipAI) -> void:
	ai.weapon_type = WipeoutWeapon.WeaponType.TURBO
	ai.fight_back = true
	ai.is_racing = true
	ai.shield_active = false


## The shield slice of the ladder fires ~600 real shields, and weapon.c caps the
## pool at WEAPONS_MAX. A race spreads those over minutes and the pool drains
## itself; compressed into one frame it saturates, and every later spawn would
## fail for that reason alone rather than because anything is broken.
func _purge_weapons(manager: Node) -> void:
	for weapon in manager.weapons:
		if is_instance_valid(weapon):
			weapon.queue_free()
	manager.weapons.clear()


func _expect(counts: Dictionary, label: String, expected: Dictionary) -> void:
	if int(counts.get("other", 0)) > 0:
		_failures.append("%s produced %d unexpected weapon type(s)" % [label, counts["other"]])
	for key in expected:
		var actual := float(counts[key]) / float(SAMPLES)
		var want: float = expected[key]
		print("  %-14s %-8s expected %5.1f%%  actual %5.1f%%" % [label, key, want * 100.0, actual * 100.0])
		if absf(actual - want) > TOLERANCE:
			_failures.append("%s %s = %.1f%%, expected %.1f%%" % [label, key, actual * 100.0, want * 100.0])


## The three guards that stop the ladders from firing. Each is checked on its own,
## because any one of them silently stuck would leave the other two looking fine.
func _check_gates(ai: WipeoutShipAI) -> void:
	# An empty slot: both branches fall through without ever arming anything.
	for i in 200:
		_arm_for_sample(ai)
		ai.weapon_type = WipeoutWeapon.WeaponType.NONE
		ai._decide_just_in_front()
		if ai.weapon_type != WipeoutWeapon.WeaponType.NONE:
			_failures.append("JUST IN FRONT armed %d from an empty slot" % ai.weapon_type)
			break
	for i in 200:
		_arm_for_sample(ai)
		ai.weapon_type = WipeoutWeapon.WeaponType.NONE
		ai._decide_just_behind()
		if ai.weapon_type != WipeoutWeapon.WeaponType.NONE:
			_failures.append("JUST BEHIND armed %d from an empty slot" % ai.weapon_type)
			break
		if not ai.overtaken:
			_failures.append("JUST BEHIND with an empty slot must set SHIP_OVERTAKEN")
			break

	# fight_back clear: the tail-enders never fight (ship.c:233).
	for i in 200:
		_arm_for_sample(ai)
		ai.fight_back = false
		ai._decide_just_in_front()
		ai._decide_just_behind()
		if ai.weapon_type != WipeoutWeapon.WeaponType.TURBO:
			_failures.append("a ship with fight_back clear fired (weapon %d)" % ai.weapon_type)
			break

	# Already shielded: ship_ai.c skips the mine drop and the whole JUST BEHIND
	# projectile ladder. The shield branch is skipped too, so nothing is armed.
	for i in 200:
		_arm_for_sample(ai)
		ai.shield_active = true
		ai._decide_just_in_front()
		ai._decide_just_behind()
		if ai.weapon_type != WipeoutWeapon.WeaponType.TURBO:
			_failures.append("a shielded ship armed %d" % ai.weapon_type)
			break

	# Not racing yet (countdown / finished): the mine and projectile branches are
	# gated on SHIP_RACING. The shield branch is deliberately not.
	for i in 200:
		_arm_for_sample(ai)
		ai.is_racing = false
		ai._decide_just_behind()
		if ai.weapon_type != WipeoutWeapon.WeaponType.TURBO:
			_failures.append("a ship that is not racing fired %d" % ai.weapon_type)
			break
	_arm_for_sample(ai)


## The shield branch uses weapons_fire(), not weapons_fire_delayed(): it must put
## a live weapon in the manager on the spot, owned by the AI that raised it.
func _check_immediate_fire(manager: Node, ai: WipeoutShipAI) -> void:
	var before: int = manager.weapons.size()
	ai.weapon_type = WipeoutWeapon.WeaponType.SHIELD
	ai.fire_weapon(WipeoutWeapon.WeaponType.SHIELD)
	if manager.weapons.size() <= before:
		_failures.append("an AI shield produced no weapon in the manager")
		return
	var weapon: WipeoutWeapon = manager.weapons[manager.weapons.size() - 1]
	if weapon.owner_ship != ai:
		_failures.append("the AI's shield is owned by the wrong ship")
	if ai.weapon_type != WipeoutWeapon.WeaponType.NONE:
		_failures.append("weapons_fire() must clear the AI's slot, left %d" % ai.weapon_type)
	print("  AI immediate fire -> %s owned by %s" % [
		WipeoutWeapon.weapon_name(weapon.weapon_type), ai.name])


## ship_player.c:276 gates firing on the button and a loaded slot, and on nothing
## else -- weapon.h declares WEAPON_DELAY and then never references it. So two
## shots fired back to back, with a pad refill in between, must both leave the
## barrel. A re-introduced cooldown would silently swallow the second, which is
## how the port behaved before: refill fast enough and the shot was eaten.
func _check_no_fire_lockout(manager: Node, player: WipeoutShip) -> void:
	player.remove_shield()
	var before: int = manager.weapons.size()
	for i in 2:
		player.weapon_type = WipeoutWeapon.WeaponType.ROCKET
		player.fire_held_weapon()
		if player.weapon_type != WipeoutWeapon.WeaponType.NONE:
			_failures.append("shot %d never left the slot -- a fire lockout is back" % (i + 1))
			return
	var fired: int = manager.weapons.size() - before
	if fired != 2:
		_failures.append("two back-to-back shots produced %d weapon(s), expected 2" % fired)
	else:
		print("  two back-to-back player shots both fired, no lockout")


## weapon.c's per-type velocity scaling, and the SHIP_SHIELDED bypass that makes a
## shielded target eat the hit for free. An AI hitting the player is the whole
## point of the ladders, so the effect is asserted rather than assumed.
func _check_damage_table(manager: Node, ai: WipeoutShipAI, player: WipeoutShip) -> void:
	var cases := {
		WipeoutWeapon.WeaponType.MINE: 0.125,
		WipeoutWeapon.WeaponType.ROCKET: 0.25,
		WipeoutWeapon.WeaponType.MISSILE: 0.03125,
	}
	for wtype in cases:
		var weapon := manager.fire_weapon(ai, wtype, player) as WipeoutWeapon
		if weapon == null:
			_failures.append("could not spawn %s for the damage check" % WipeoutWeapon.weapon_name(wtype))
			continue
		player.remove_shield()
		player.velocity = Vector3(0.0, 0.0, 100.0)
		weapon._on_ship_hit(player)
		var expected: float = 100.0 * float(cases[wtype])
		if absf(player.velocity.z - expected) > 0.01:
			_failures.append("%s left the target at %.3f m/s, expected %.3f" % [
				WipeoutWeapon.weapon_name(wtype), player.velocity.z, expected])

	# Shielded: same bang, no slowdown.
	var rocket := manager.fire_weapon(ai, WipeoutWeapon.WeaponType.ROCKET, player) as WipeoutWeapon
	if rocket != null:
		player.fire_weapon(WipeoutWeapon.WeaponType.SHIELD)
		if not player.has_shield():
			_failures.append("the player could not raise a shield for the bypass check")
		player.velocity = Vector3(0.0, 0.0, 100.0)
		rocket._on_ship_hit(player)
		if absf(player.velocity.z - 100.0) > 0.01:
			_failures.append("a shielded target lost speed (%.3f m/s), it should take no damage" % player.velocity.z)
		player.remove_shield()


## weapons_fire_delayed(): the AI sits on the weapon for WEAPON_AI_DELAY before it
## launches. Verified across frames rather than inline, since that delay is real.
func _start_delayed_fire(manager: Node, ai: WipeoutShipAI) -> void:
	_delay_ai = ai
	_weapons_before = manager.weapons.size()
	ai.weapon_type = WipeoutWeapon.WeaponType.ROCKET
	ai.fire_weapon_delayed(WipeoutWeapon.WeaponType.ROCKET)
	if manager.weapons.size() > _weapons_before:
		_failures.append("a delayed AI shot launched immediately, ignoring WEAPON_AI_DELAY")
	_delay_deadline = _frames + DELAY_FRAMES


func _check_delayed_arrival() -> void:
	var manager := WipeoutWeaponManager.instance(self)
	if manager == null:
		return
	if manager.weapons.size() <= _weapons_before:
		_failures.append("a delayed AI shot never launched after %d frames" % DELAY_FRAMES)
		return
	if _delay_ai != null and _delay_ai.weapon_type != WipeoutWeapon.WeaponType.NONE:
		_failures.append("a delayed AI shot left the slot loaded with %d" % _delay_ai.weapon_type)
	print("  AI delayed fire launched after WEAPON_AI_DELAY")


func _find_ai_ships(node: Node) -> Array[WipeoutShipAI]:
	var found: Array[WipeoutShipAI] = []
	var ai := node as WipeoutShipAI
	if ai != null:
		found.append(ai)
	for child in node.get_children():
		found.append_array(_find_ai_ships(child))
	return found


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
		print("validate_ai_weapons: OK")
		quit(0)
		return
	for failure in _failures:
		printerr("  FAIL: %s" % failure)
	printerr("validate_ai_weapons: %d failure(s)" % _failures.size())
	quit(1)

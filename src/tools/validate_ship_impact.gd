extends SceneTree

## Headless check of ship.c ship_collide_with_ship()'s *resolution*.
## validate_ship_collision.gd covers the other half -- that HullArea is sized off
## ALCOL.PRM and that two hulls register an overlap -- but nothing asserted what
## happens once they do, which is where the port had drifted:
##
##   ship.c:903-908  each ship leaves at vc + (vc - v) * 0.5, past the common
##                   velocity rather than short of it. That overshoot is the
##                   bounce; moving toward vc instead leaves both ships still
##                   travelling the way they came.
##   ship.c:913-916  a separation shove of res * 4, in PSX units on both sides,
##                   so 4 m/s per metre of overlap after the scale cancels.
##   ship.c:919-927  one SFX_CRUNCH per pair at the midpoint, on the frame
##                   contact begins -- not one per ship at each hull.
##
## Area3D overlap pairs are only current as of the last physics step, so the
## ships are placed one tick before the resolve is driven.

const SETTLE_FRAMES := 600
const HEAD_ON_SPEED := 10.0
const EPSILON := 0.001

var _main: Node3D = null
var _setup: Node = null
var _restore_race_type: int = 0
var _failures: Array[String] = []
var _frames := 0
var _ship_a: WipeoutShip = null
var _ship_b: WipeoutShip = null
var _manager: Node = null


func _initialize() -> void:
	_setup = root.get_node_or_null("RaceSetup")
	if _setup == null:
		push_error("RaceSetup autoload not found")
		quit(1)
		return
	_restore_race_type = _setup.race_type
	# A time trial spawns the player alone, so there is no pair to collide.
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
	if _frames < SETTLE_FRAMES:
		return false

	if _frames == SETTLE_FRAMES:
		var ships := get_nodes_in_group(&"ships")
		if ships.size() < 2:
			_failures.append("a championship race has fewer than two ships")
			_report()
			return true
		_ship_a = ships[0]
		_ship_b = ships[1]
		_manager = _main.get_node_or_null("ShipCollisionManager")
		if _manager == null:
			_failures.append("main.tscn has no ShipCollisionManager, so no pair is ever resolved")
			_report()
			return true
		# Overlap them so the Area3D pair is live on the next tick.
		_ship_a.global_position = Vector3(0.0, 50.0, 0.0)
		_ship_b.global_position = Vector3(0.5, 50.0, 0.0)
		return false

	_check_overlap_registered()
	_check_head_on_bounce()
	_check_separation_shove()
	_check_mass_weighting()
	_check_single_crunch()
	_setup.race_type = _restore_race_type
	_report()
	return true


func _check_overlap_registered() -> void:
	if not _ship_a.hull_area.get_overlapping_areas().has(_ship_b.hull_area):
		_failures.append("two ships half a metre apart do not register an overlap")


## The headline behaviour. Separation is put purely on X and the approach purely
## on Z, so the Z figures isolate the velocity term from the separation shove.
func _check_head_on_bounce() -> void:
	_arrange(Vector3(0.0, 0.0, HEAD_ON_SPEED), Vector3(0.0, 0.0, -HEAD_ON_SPEED))
	_manager._resolve_pair(_ship_a, _ship_b)

	# vc is zero for an equal-mass head-on pair, so ship.c's vc + (vc - v) * 0.5
	# is -v/2: each ship leaves at half speed, reversed.
	var expected := -HEAD_ON_SPEED * 0.5
	print("  head-on %.1f m/s -> a=%.3f  b=%.3f  (expected %.3f / %.3f)" % [
		HEAD_ON_SPEED, _ship_a.velocity.z, _ship_b.velocity.z, expected, -expected])
	if absf(_ship_a.velocity.z - expected) > EPSILON:
		_failures.append("head-on: ship A left at %.3f m/s, expected %.3f" % [
			_ship_a.velocity.z, expected])
	if absf(_ship_b.velocity.z + expected) > EPSILON:
		_failures.append("head-on: ship B left at %.3f m/s, expected %.3f" % [
			_ship_b.velocity.z, -expected])
	# The sign is the whole point, and it is what a "move toward vc" resolution
	# gets wrong while still looking like a plausible slowdown.
	if _ship_a.velocity.z > 0.0:
		_failures.append("head-on: ship A is still travelling forwards; the collision did not reverse it")


## res * 4 along the separation axis, which here is X alone.
func _check_separation_shove() -> void:
	_arrange(Vector3.ZERO, Vector3.ZERO)
	var separation := _ship_a.global_position.x - _ship_b.global_position.x
	_manager._resolve_pair(_ship_a, _ship_b)
	var expected := separation * 4.0
	print("  shove over %.2f m of overlap -> a.x=%.3f  (expected %.3f)" % [
		separation, _ship_a.velocity.x, expected])
	if absf(_ship_a.velocity.x - expected) > EPSILON:
		_failures.append("separation shove was %.3f m/s, expected %.3f (ship.c res * 4)" % [
			_ship_a.velocity.x, expected])
	if absf(_ship_b.velocity.x + expected) > EPSILON:
		_failures.append("the shove is not equal and opposite: B got %.3f" % _ship_b.velocity.x)


## A heavy ship should barely deviate while a light one is thrown clear: vc leans
## toward the heavier mass. Without the weighting both would mirror each other.
func _check_mass_weighting() -> void:
	_arrange(Vector3(0.0, 0.0, HEAD_ON_SPEED), Vector3(0.0, 0.0, -HEAD_ON_SPEED))
	_ship_a.mass = 900.0
	_ship_b.mass = 100.0
	var vc := (HEAD_ON_SPEED * 900.0 - HEAD_ON_SPEED * 100.0) / 1000.0
	var expected_a := vc + (vc - HEAD_ON_SPEED) * 0.5
	var expected_b := vc + (vc + HEAD_ON_SPEED) * 0.5
	_manager._resolve_pair(_ship_a, _ship_b)
	print("  9:1 masses -> heavy=%.3f  light=%.3f  (expected %.3f / %.3f)" % [
		_ship_a.velocity.z, _ship_b.velocity.z, expected_a, expected_b])
	if absf(_ship_a.velocity.z - expected_a) > EPSILON:
		_failures.append("mass weighting: heavy ship left at %.3f, expected %.3f" % [
			_ship_a.velocity.z, expected_a])
	if absf(_ship_b.velocity.z - expected_b) > EPSILON:
		_failures.append("mass weighting: light ship left at %.3f, expected %.3f" % [
			_ship_b.velocity.z, expected_b])
	if absf(_ship_a.velocity.z) >= absf(_ship_b.velocity.z):
		_failures.append("the heavy ship was deflected at least as much as the light one")
	_ship_a.mass = 1.0
	_ship_b.mass = 1.0


## One crunch for the pair on the frame contact begins, then silence while the
## two stay locked together. Counted through ship_impact_cooldown, which is what
## the manager arms when it plays.
func _check_single_crunch() -> void:
	_arrange(Vector3.ZERO, Vector3.ZERO)
	_ship_a.ship_colliding = false
	_ship_b.ship_colliding = false
	_ship_a.ship_impact_cooldown = 0.0

	_manager._resolve_pair(_ship_a, _ship_b)
	if _ship_a.ship_impact_cooldown <= 0.0:
		_failures.append("the first frame of contact played no crunch")
	if not _ship_a.ship_colliding or not _ship_b.ship_colliding:
		_failures.append("SHIP_COLL was not set on both ships after contact")

	# Sustained contact: the flags are set, so nothing more should fire even once
	# the 0.2 s timer has run out.
	_ship_a.ship_impact_cooldown = 0.0
	for i in 5:
		_manager._resolve_pair(_ship_a, _ship_b)
	if _ship_a.ship_impact_cooldown > 0.0:
		_failures.append("a crunch replayed while the pair was already in contact")

	# Driven apart, the flags clear and the next contact is audible again.
	var parked := _ship_b.global_position
	_ship_b.global_position = _ship_a.global_position + Vector3(100.0, 0.0, 0.0)
	_manager._resolve_pair(_ship_a, _ship_b)
	if _ship_a.ship_colliding or _ship_b.ship_colliding:
		_failures.append("SHIP_COLL survived the distance early-out")
	_ship_b.global_position = parked
	print("  crunch: once on contact, silent while held, re-armed once apart")


func _arrange(velocity_a: Vector3, velocity_b: Vector3) -> void:
	# Re-pinned every time: the hover step drifts the ships between resolves, and
	# a stray offset would leak into the separation term.
	_ship_a.global_position = Vector3(0.0, 50.0, 0.0)
	_ship_b.global_position = Vector3(0.5, 50.0, 0.0)
	_ship_a.velocity = velocity_a
	_ship_b.velocity = velocity_b
	_ship_a.mass = 1.0
	_ship_b.mass = 1.0


func _report() -> void:
	if _failures.is_empty():
		print("validate_ship_impact: OK")
		quit(0)
		return
	for failure in _failures:
		printerr("  FAIL: %s" % failure)
	printerr("validate_ship_impact: %d failure(s)" % _failures.size())
	quit(1)

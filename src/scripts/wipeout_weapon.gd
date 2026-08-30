extends Node3D

class_name WipeoutWeapon

## One live weapon, ported from weapon.c's `weapon_t` plus its per-type
## `update_func`. The manager (WipeoutWeaponManager, autoloaded as
## `WeaponManager`) owns the fleet; each instance frees itself when its timer
## runs out or it hits something.
##
## Tuning note, same convention as wipeout_ship.gd: the PSX source works in
## 1/106.5-metre units on a fixed 30 Hz step, so its raw constants (acceleration
## 256, collision distance 512) do not transfer as literals. What is ported
## faithfully is the *behaviour* -- which weapons home, how long each lives, and
## the relative severity of each hit -- with magnitudes expressed in m and m/s.

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

# Durations, converted straight from the NTSC frame counts in weapon.h.
const MINE_DURATION = 450.0 / 30.0
const ROCKET_DURATION = 200.0 / 30.0
const EBOLT_DURATION = 140.0 / 30.0
const MISSILE_DURATION = 200.0 / 30.0
const SHIELD_DURATION = 200.0 / 30.0
const MINE_RELEASE_RATE = 3.0 / 30.0
const WEAPON_DELAY = 40.0 / 30.0
const MINE_COUNT = 5
const AI_DELAY = 1.1

## 512 PSX units / 106.5 units-per-metre (the convert_ships.py scale).
const SHIP_COLLISION_RADIUS = 4.8
## Cruise speed for the three projectiles. The source accelerates against a drag
## term toward a terminal velocity; holding that terminal speed directly is
## equivalent over the weapon's short life and far steadier at variable delta.
const PROJECTILE_SPEED = 190.0
## How fast a homing weapon swings onto its target, rad/s.
const HOMING_TURN_RATE = 2.4
## weapon_update_shield()'s `const uint8_t shield_alpha = 48`, as a 0..1 alpha.
const SHIELD_ALPHA = 48.0 / 255.0

const WEAPON_MODELS = {
	WeaponType.ROCKET: "res://assets/weapons/rocket.glb",
	WeaponType.MINE: "res://assets/weapons/mine.glb",
	WeaponType.MISSILE: "res://assets/weapons/missile.glb",
	WeaponType.SHIELD: "res://assets/weapons/shield.glb",
	WeaponType.EBOLT: "res://assets/weapons/ebolt.glb",
}

## The three types that fly; everything else either sits still (mine) or acts on
## the owner directly (shield, turbo).
const PROJECTILES = [WeaponType.ROCKET, WeaponType.MISSILE, WeaponType.EBOLT]
## Of those, the two that steer toward weapon_target (weapon_follow_target()).
const HOMING = [WeaponType.MISSILE, WeaponType.EBOLT]

var owner_ship: WipeoutShip
var target_ship: WipeoutShip
var weapon_type: WeaponType = WeaponType.NONE
var timer: float = 0.0
var active: bool = false

var model: Node3D
var release_timer: float = 0.0
var is_waiting_for_release: bool = false
var _shield_material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group(&"weapons")


func _physics_process(delta: float) -> void:
	if not active:
		return

	timer -= delta

	# weapon_update_mine_wait_for_release(): the mine is inert until its slice of
	# the release stagger has elapsed.
	if is_waiting_for_release:
		release_timer -= delta
		if release_timer <= 0.0:
			_initialize_mine()
		return

	if timer <= 0.0:
		_deactivate()
		return

	match weapon_type:
		WeaponType.SHIELD:
			# weapon_update_shield(): the bubble rides the owner.
			if not is_instance_valid(owner_ship):
				_deactivate()
				return
			global_position = owner_ship.global_position
			global_rotation = owner_ship.global_rotation
			_animate_shield()
			return # a shield never collides with anything
		WeaponType.MINE:
			rotation.y += delta * 2.0 # "self->angle.y += system_tick()"

	if weapon_type in PROJECTILES:
		if weapon_type in HOMING:
			_follow_target(delta)
		global_position += -global_transform.basis.z * PROJECTILE_SPEED * delta

	var hit := _check_ship_collision()
	if hit != null:
		_on_ship_hit(hit)


## weapons_fire(): dispatch on type.
func fire(ship: WipeoutShip, wtype: WeaponType, target: WipeoutShip = null) -> void:
	owner_ship = ship
	target_ship = target
	weapon_type = wtype
	active = true
	global_position = ship.global_position
	global_rotation = ship.global_rotation

	match wtype:
		WeaponType.MINE:
			timer = MINE_DURATION
			is_waiting_for_release = true
			release_timer = MINE_RELEASE_RATE
			_load_model(wtype)
		WeaponType.MISSILE:
			timer = MISSILE_DURATION
			_load_model(wtype)
		WeaponType.ROCKET:
			timer = ROCKET_DURATION
			_load_model(wtype)
		WeaponType.EBOLT:
			timer = EBOLT_DURATION
			_load_model(wtype)
		WeaponType.SHIELD:
			timer = SHIELD_DURATION
			# The bubble copies the ship's transform each frame, so it has to run
			# *after* the ship has moved -- otherwise it trails a frame behind,
			# which at racing speed leaves it visibly off to one side.
			process_physics_priority = 100
			_load_model(wtype)
			ship.apply_shield()
		WeaponType.TURBO:
			_fire_turbo()


## weapon_fire_mine() drops WEAPON_MINE_COUNT mines in a row; each waits out its
## own slice of the stagger, then lands at the ship's *current* position, which
## is what strings them along the racing line.
func fire_mine_delayed(ship: WipeoutShip, delay: float) -> void:
	owner_ship = ship
	weapon_type = WeaponType.MINE
	active = true
	global_position = ship.global_position
	global_rotation = ship.global_rotation
	is_waiting_for_release = true
	release_timer = delay
	# timer runs during the wait too, so add the delay back to keep the mine's
	# armed lifetime at MINE_DURATION.
	timer = MINE_DURATION + delay
	_load_model(WeaponType.MINE)


func _initialize_mine() -> void:
	is_waiting_for_release = false
	if is_instance_valid(owner_ship):
		global_position = owner_ship.global_position
	rotation.y = randf_range(0.0, TAU)
	if model != null:
		model.visible = true


## weapon_fire_turbo(): a straight shove along the nose, no projectile at all.
func _fire_turbo() -> void:
	if is_instance_valid(owner_ship):
		owner_ship.velocity += -owner_ship.global_transform.basis.z * 60.0
	_deactivate()


## weapon_follow_target(): swing the nose toward the target, then fly along it.
func _follow_target(delta: float) -> void:
	if not is_instance_valid(target_ship):
		return
	var to_target := target_ship.global_position - global_position
	if to_target.length_squared() < 0.001:
		return

	var desired := Transform3D(global_transform.basis, global_position).looking_at(
		target_ship.global_position, Vector3.UP
	)
	global_transform.basis = global_transform.basis.slerp(
		desired.basis, minf(1.0, HOMING_TURN_RATE * delta)
	).orthonormalized()


## weapon_collides_with_ship(): plain radius test against every ship but the owner.
func _check_ship_collision() -> WipeoutShip:
	for node in get_tree().get_nodes_in_group(&"ships"):
		var ship := node as WipeoutShip
		if ship == null or ship == owner_ship:
			continue
		if global_position.distance_to(ship.global_position) < SHIP_COLLISION_RADIUS:
			return ship
	return null


func _on_ship_hit(ship: WipeoutShip) -> void:
	# flags_not(ship->flags, SHIP_SHIELDED): a shielded ship eats the hit with no
	# effect, but the weapon is still spent.
	if not ship.has_shield():
		match weapon_type:
			WeaponType.MINE:
				ship.velocity *= 0.125
			WeaponType.ROCKET:
				ship.velocity *= 0.25
			WeaponType.MISSILE:
				ship.velocity *= 0.03125
			WeaponType.EBOLT:
				ship.apply_electro_effect(EBOLT_DURATION)
	_deactivate()


func _load_model(wtype: WeaponType) -> void:
	if not WEAPON_MODELS.has(wtype):
		return
	if model != null and is_instance_valid(model):
		model.queue_free()

	var scene := load(WEAPON_MODELS[wtype]) as PackedScene
	if scene == null:
		return
	model = scene.instantiate()
	add_child(model)
	# A mine stays invisible until it is actually released.
	if wtype == WeaponType.MINE:
		model.visible = false
	elif wtype == WeaponType.SHIELD:
		_apply_shield_material()


## weapon_update_shield() rewrites the bubble's vertex colours every frame to
## rgba(col, col, 255, 48) -- a translucent blue that pulses. Per-vertex colours
## would need a custom shader here, so a single translucent material carries the
## same look while keeping the ship readable through it.
func _apply_shield_material() -> void:
	_shield_material = StandardMaterial3D.new()
	_shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_material.albedo_color = Color(0.55, 0.55, 1.0, SHIELD_ALPHA)
	_shield_material.emission_enabled = true
	_shield_material.emission = Color(0.45, 0.6, 1.0)
	_shield_material.emission_energy_multiplier = 0.7
	# The source keeps a second copy of the mesh with its polys swapped
	# (shield_internal) so the bubble is solid from inside the cockpit too;
	# drawing both faces covers both views from one mesh.
	_shield_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# A translucent bubble casting a hard shadow reads as a solid ball.
	_for_each_mesh(model, func(mesh_instance: MeshInstance3D) -> void:
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in mesh_instance.get_surface_override_material_count():
			mesh_instance.set_surface_override_material(surface, _shield_material)
	)


## Pulses the tint between blue and white, standing in for the per-vertex
## `sinf(color_timer * coords[v])` sweep in weapon_update_shield().
func _animate_shield() -> void:
	if _shield_material == null:
		return
	var pulse := sin(timer * 6.0) * 0.5 + 0.5
	_shield_material.albedo_color = Color(
		0.45 + 0.4 * pulse, 0.5 + 0.35 * pulse, 1.0, SHIELD_ALPHA
	)


func _for_each_mesh(node: Node, action: Callable) -> void:
	if node is MeshInstance3D:
		action.call(node)
	for child in node.get_children():
		_for_each_mesh(child, action)


func _deactivate() -> void:
	active = false
	if weapon_type == WeaponType.SHIELD and is_instance_valid(owner_ship):
		owner_ship.remove_shield()
	queue_free()


## Short diagnostic label (validate_weapon_pads.gd). race_hud.gd draws the real
## WICONS.CMP sprite instead of this for the in-race HUD.
static func weapon_name(wtype: WeaponType) -> String:
	match wtype:
		WeaponType.MINE: return "MINES"
		WeaponType.MISSILE: return "MISSILE"
		WeaponType.ROCKET: return "ROCKET"
		WeaponType.EBOLT: return "E-BOLT"
		WeaponType.SHIELD: return "SHIELD"
		WeaponType.TURBO: return "TURBO"
		_: return ""

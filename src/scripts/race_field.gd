extends Node
class_name RaceField

## Race-level AI field: 8-ship grid, opponent models, DPA settings and live
## ranking. Mirrors ships_init() / ships_update() in src/wipeout/ship.c without
## cloning the PSX section-based start stagger.

const NUM_PILOTS := 8
const NUM_AI_OPPONENTS := 7

## ships_init()'s stagger loop walks the section chain forward from ShipSpawn
## (TRACK.TRS index start_line_pos-15, the "BASE" section) building
## start_sections[0..7] = BASE + [0,2,3,5,6,8,9,11] (i%2==0 skips an extra
## section). It then hands roster slot i (0=pole..7=player, same convention
## this file already uses) start_sections[7-i] -- so ShipSpawn itself is
## exactly the *player's* (back-of-grid) section, and every other slot sits
## some number of sections *forward* of it, not behind:
##   grid slot:            0(pole) 1  2  3  4  5  6  7(player)
##   sections fwd of spawn: 11      9  8  6  5  3  2  0
## The previous table anchored pole at ShipSpawn and stepped the player 14 m
## *behind* it in fixed 2 m increments -- backwards on both counts, and far
## short of a real section (~14-17 m, see wipeout_ship_ai.gd's
## SECTION_LENGTH_FALLBACK comment). place_ship() below walks this many
## sections along the real (possibly curved) center line instead.
const GRID_SECTION_OFFSETS: Array[float] = [11.0, 9.0, 8.0, 6.0, 5.0, 3.0, 2.0, 0.0]
## Alternating left/right lane, matching ship_init()'s odd/even
## inv_start_rank face pick. Magnitude isn't derived from real per-section
## track-face geometry like the original; it's a plausible constant half-lane.
const GRID_LATERAL_OFFSET := 1.8
## Matches compute_ship_spawn.py's HOVER_CLEARANCE_M, added back in here since
## place_ship() samples the curve directly instead of reusing ShipSpawn's own
## (already hover-raised) Y.
const GRID_HOVER_CLEARANCE := 2.0

## Per-class opponent tables from game.c def.ai_settings. Index 0 is the
## weakest (inv_start_rank-1 == 0, i.e. the grid slot right in front of the
## player); index 6 is the strongest, handed to the pole-position AI.
const AI_SETTINGS: Dictionary = {
	0: [
		{"thrust_max": 2550.0, "thrust_magnitude": 44.0, "fight_back": true},
		{"thrust_max": 2600.0, "thrust_magnitude": 45.0, "fight_back": true},
		{"thrust_max": 2630.0, "thrust_magnitude": 45.0, "fight_back": true},
		{"thrust_max": 2660.0, "thrust_magnitude": 46.0, "fight_back": true},
		{"thrust_max": 2700.0, "thrust_magnitude": 47.0, "fight_back": true},
		{"thrust_max": 2720.0, "thrust_magnitude": 48.0, "fight_back": true},
		{"thrust_max": 2750.0, "thrust_magnitude": 49.0, "fight_back": true},
	],
	1: [
		{"thrust_max": 3750.0, "thrust_magnitude": 50.0, "fight_back": true},
		{"thrust_max": 3780.0, "thrust_magnitude": 53.0, "fight_back": true},
		{"thrust_max": 3800.0, "thrust_magnitude": 55.0, "fight_back": true},
		{"thrust_max": 3850.0, "thrust_magnitude": 57.0, "fight_back": true},
		{"thrust_max": 3900.0, "thrust_magnitude": 60.0, "fight_back": true},
		{"thrust_max": 3950.0, "thrust_magnitude": 62.0, "fight_back": true},
		{"thrust_max": 4000.0, "thrust_magnitude": 65.0, "fight_back": true},
	],
}

const CIRCUIT_SETTINGS: Dictionary = {
	"TERRAMAX": {
		0: {"behind_speed": 350.0, "spread_base": 60.0, "spread_factor": 11.0},
		1: {"behind_speed": 500.0, "spread_base": 10.0, "spread_factor": 8.0},
	},
	"ALTIMA VII": {
		0: {"behind_speed": 300.0, "spread_base": 80.0, "spread_factor": 20.0},
		1: {"behind_speed": 500.0, "spread_base": 80.0, "spread_factor": 11.0},
	},
	"KARBONIS V": {
		0: {"behind_speed": 200.0, "spread_base": 10.0, "spread_factor": 8.0},
		1: {"behind_speed": 500.0, "spread_base": 10.0, "spread_factor": 8.0},
	},
	"KORODERA": {
		0: {"behind_speed": 450.0, "spread_base": 40.0, "spread_factor": 11.0},
		1: {"behind_speed": 500.0, "spread_base": 30.0, "spread_factor": 11.0},
	},
	"ARRIDOS IV": {
		0: {"behind_speed": 350.0, "spread_base": 80.0, "spread_factor": 15.0},
		1: {"behind_speed": 450.0, "spread_base": 30.0, "spread_factor": 11.0},
	},
	"SILVERSTREAM": {
		0: {"behind_speed": 150.0, "spread_base": 10.0, "spread_factor": 8.0},
		1: {"behind_speed": 150.0, "spread_base": 10.0, "spread_factor": 8.0},
	},
	"FIRESTAR": {
		0: {"behind_speed": 200.0, "spread_base": 40.0, "spread_factor": 11.0},
		1: {"behind_speed": 500.0, "spread_base": 40.0, "spread_factor": 11.0},
	},
}


static func circuit_settings_for(track_name: String, race_class: int) -> Dictionary:
	var by_class: Dictionary = CIRCUIT_SETTINGS.get(track_name, CIRCUIT_SETTINGS["TERRAMAX"])
	return by_class.get(race_class, by_class[0])


static func ai_settings_for(race_class: int, inv_start_rank: int) -> Dictionary:
	var table: Array = AI_SETTINGS.get(race_class, AI_SETTINGS[0])
	var index := clampi(inv_start_rank - 1, 0, table.size() - 1)
	return table[index]


static func track_display_name() -> String:
	if TrackSelection.selected_track_scene == null:
		return "TERRAMAX"
	var path := TrackSelection.selected_track_scene.resource_path
	for track in TrackSelection.TRACKS:
		if track["scene"] == path:
			return str(track.get("circuit", track["name"]))
	return "TERRAMAX"


static func build_start_order(player_pilot: String) -> Array[Dictionary]:
	var roster: Array[Dictionary] = []
	for ship in ShipSelection.SHIPS:
		roster.append(ship)
	roster.shuffle()
	for i in roster.size():
		if str(roster[i].get("pilot", "")) == player_pilot:
			var player_entry: Dictionary = roster[i]
			roster.remove_at(i)
			roster.append(player_entry)
			break
	return roster


## `spawn_offset` is the ShipSpawn marker's own position expressed as a
## center_line curve offset (main.gd computes it once per race and passes it
## down, since it's the same for every ship). `center_line` may be null (or
## curve-less) for a track missing that data, in which case this falls back
## to a straight-line offset from the marker, like the old table did.
static func place_ship(ship: WipeoutShip, spawn: Marker3D, center_line: Path3D, spawn_offset: float, grid_index: int) -> void:
	if spawn == null or grid_index < 0 or grid_index >= GRID_SECTION_OFFSETS.size():
		return
	var lateral := -GRID_LATERAL_OFFSET if (grid_index % 2) == 0 else GRID_LATERAL_OFFSET
	if center_line == null or center_line.curve == null or center_line.curve.point_count < 2:
		ship.respawn_at(spawn.global_transform.translated_local(Vector3(lateral, 0.0, 0.0)))
		return

	var curve := center_line.curve
	var section_length := _section_length_meters(curve)
	var curve_length := maxf(curve.get_baked_length(), 0.001)
	var target_offset := fposmod(spawn_offset + GRID_SECTION_OFFSETS[grid_index] * section_length, curve_length)

	var target_local := curve.sample_baked(target_offset, true)
	var ahead_local := curve.sample_baked(fposmod(target_offset + 1.0, curve_length), true)
	var forward := ahead_local - target_local
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = -spawn.global_transform.basis.z
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = spawn.global_transform.basis.x
	right = right.normalized()
	var up := right.cross(forward).normalized()

	var target_position := center_line.to_global(target_local) + right * lateral + Vector3.UP * GRID_HOVER_CLEARANCE
	ship.respawn_at(Transform3D(Basis(right, up, -forward).orthonormalized(), target_position))


## baked_length / point_count: one TRACK.TRS section in meters, same
## derivation as wipeout_ship_ai.gd's _section_length_meters().
static func _section_length_meters(curve: Curve3D) -> float:
	if curve.point_count <= 0:
		return 15.0
	var length := curve.get_baked_length()
	if length <= 0.0:
		return 15.0
	return length / float(curve.point_count)


func _physics_process(_delta: float) -> void:
	_update_ranks()


func _update_ranks() -> void:
	var ships: Array = get_tree().get_nodes_in_group(&"ships")
	# ships_update() only re-ranks while the player still has SHIP_RACING, so
	# the final standings stay frozen on the results screen.
	for node in ships:
		var ship := node as WipeoutShip
		if ship != null and ship.is_player_controlled and not ship.is_racing:
			return
	ships.sort_custom(_compare_race_progress)
	for i in ships.size():
		var ship := ships[i] as WipeoutShip
		if ship != null:
			ship.position_rank = i + 1


func _compare_race_progress(a: Variant, b: Variant) -> bool:
	var ship_a := a as WipeoutShip
	var ship_b := b as WipeoutShip
	if ship_a == null or ship_b == null:
		return false
	return ship_a.race_progress > ship_b.race_progress

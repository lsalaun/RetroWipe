extends SceneTree

## Headless check that SFX_CRUNCH is assigned to both impact slots.

const CRUNCH := "res://assets/sfx/crunch.wav"
const IMPACT := "res://assets/sfx/impact.wav"
const SHIP_SCENE := "res://scenes/WipeoutShip.tscn"
const AI_SCENE := "res://scenes/WipeoutShipAI.tscn"
const MUSIC: Array[String] = [
	"res://assets/music/cairodrome.mp3",
	"res://assets/music/cardinal_dancer.mp3",
	"res://assets/music/cold_comfort.mp3",
	"res://assets/music/doh_t.mp3",
	"res://assets/music/messij.mp3",
	"res://assets/music/operatique.mp3",
	"res://assets/music/tentative.mp3",
	"res://assets/music/trancevaal.mp3",
	"res://assets/music/afro_ride.mp3",
	"res://assets/music/chemical_beats.mp3",
	"res://assets/music/wipeout.mp3",
]

var _frames := 0
var _player: Node = null
var _ai: Node = null
var _ready := false


func _initialize() -> void:
	if not _check_files():
		quit(1)
		return
	var ship_packed := load(SHIP_SCENE) as PackedScene
	var ai_packed := load(AI_SCENE) as PackedScene
	if ship_packed == null or ai_packed == null:
		push_error("validate_impact_sfx: failed to load ship scenes")
		quit(1)
		return
	_player = ship_packed.instantiate()
	_ai = ai_packed.instantiate()
	if _player == null or _ai == null:
		push_error("validate_impact_sfx: instantiate failed")
		quit(1)
		return
	_player.set("is_player_controlled", false)
	root.add_child(_player)
	root.add_child(_ai)
	_ready = true


func _physics_process(_delta: float) -> bool:
	if not _ready:
		return false
	_frames += 1
	if _frames < 3:
		return false
	if not _check_ship(_player, "WipeoutShip"):
		_cleanup()
		quit(1)
		return true
	if not _check_ship(_ai, "WipeoutShipAI"):
		_cleanup()
		quit(1)
		return true
	print("validate_impact_sfx: OK")
	_cleanup()
	quit(0)
	return true


func _cleanup() -> void:
	for node in [_player, _ai]:
		if node == null:
			continue
		if node.is_inside_tree():
			root.remove_child(node)
		node.free()
	_player = null
	_ai = null


func _check_files() -> bool:
	for path in [CRUNCH, IMPACT]:
		if not ResourceLoader.exists(path):
			push_error("validate_impact_sfx: missing %s" % path)
			return false
		var stream := load(path)
		if stream == null:
			push_error("validate_impact_sfx: failed to load %s" % path)
			return false
		if stream is AudioStreamWAV:
			var rate := int((stream as AudioStreamWAV).mix_rate)
			if rate != 22050:
				push_error("validate_impact_sfx: %s mix_rate %d != 22050" % [path, rate])
				return false
	for path in MUSIC:
		if not ResourceLoader.exists(path):
			push_error("validate_impact_sfx: missing %s" % path)
			return false
	return true


func _check_ship(ship: Node, label: String) -> bool:
	var wall: AudioStream = ship.get("wall_impact_sound")
	var hull: AudioStream = ship.get("ship_impact_sound")
	if wall == null or hull == null:
		push_error("validate_impact_sfx: %s missing impact streams" % label)
		return false
	# ship.c splits the two: SFX_IMPACT for the track (wing/nose/floor, in
	# ship_resolve_wing_collision()/ship_resolve_nose_collision()) and SFX_CRUNCH
	# only for ship-vs-ship, in ship_collide_with_ship().
	if wall.resource_path != IMPACT or hull.resource_path != CRUNCH:
		push_error("validate_impact_sfx: %s streams %s / %s" % [label, wall.resource_path, hull.resource_path])
		return false
	return true

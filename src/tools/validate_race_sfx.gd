extends SceneTree

## Headless check of the in-race sound effects ported from sfx.c's callers:
## ship_player.c's four reserved loops on the player and ship_ai.c's single
## positional SFX_ENGINE_REMOTE on every other ship, the volume/pitch curves
## ship_player_update_sfx() drives them with, and that every one-shot the port
## triggers (weapon launches, explosions, pickups, AI warnings) resolves to a
## real sample.
##
## Autoload names are not compile-time identifiers in --script mode, so the
## SFX API is reached through the WipeoutAudio class name, exactly as the game
## scripts under test do.

const SHIP_SCENE := "res://scenes/WipeoutShip.tscn"
const AI_SCENE := "res://scenes/WipeoutShipAI.tscn"

## Every path the port plays. sfx.h lists 30 sources; the ones left out here
## have no trigger in this port: SFX_EXPLOSION_2 (weapon-vs-track collision is
## not ported), SFX_TRACTOR (rescue droid), SFX_CROWD (trackside stands), plus
## SFX_SIREN / SFX_MENU_TRANSITION / SFX_ENGINE_RUMBLE / SFX_VOICE_REVCON /
## SFX_VOICE_SPECIAL, which the C original never plays either.
const EXPECTED_SAMPLES: Array[String] = [
	"res://assets/sfx/engine_thrust.wav",
	"res://assets/sfx/engine_intake.wav",
	"res://assets/sfx/engine_remote.wav",
	"res://assets/sfx/shield.wav",
	"res://assets/sfx/turbulence.wav",
	"res://assets/sfx/impact.wav",
	"res://assets/sfx/crunch.wav",
	"res://assets/sfx/powerup.wav",
	"res://assets/sfx/mine_drop.wav",
	"res://assets/sfx/missile_fire.wav",
	"res://assets/sfx/ebolt.wav",
	"res://assets/sfx/explosion_1.wav",
	"res://assets/sfx/voice_mines.wav",
	"res://assets/sfx/voice_missile.wav",
	"res://assets/sfx/voice_rockets.wav",
	"res://assets/sfx/voice_shockwave.wav",
]

var _failures: Array[String] = []
var _frames := 0
var _player: Node3D = null
var _ai: Node3D = null


func _initialize() -> void:
	var player_scene := load(SHIP_SCENE) as PackedScene
	var ai_scene := load(AI_SCENE) as PackedScene
	if player_scene == null or ai_scene == null:
		push_error("validate_race_sfx: failed to load ship scenes")
		quit(1)
		return
	_player = player_scene.instantiate()
	_ai = ai_scene.instantiate()
	root.add_child(_player)
	root.add_child(_ai)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	# One tick for _ready() across both ships, then a second so the lazy
	# _build_engine_sfx() in _update_engine_sfx() has run.
	if _frames < 3:
		return false

	_check_samples_exist()
	_check_loop_streams()
	_check_player_loops()
	_check_ai_loop()
	_check_player_curves()

	if _failures.is_empty():
		print("validate_race_sfx: OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("validate_race_sfx: %s" % failure)
		quit(1)
	return true


func _check_samples_exist() -> void:
	for path in EXPECTED_SAMPLES:
		_check("sample exists: %s" % path, ResourceLoader.exists(path))


## sfx_reserve_loop() runs its sample for the ship's whole race, but the WAVs
## import with looping off (every other caller wants a one-shot).
func _check_loop_streams() -> void:
	var looped := WipeoutAudio.looping_stream("res://assets/sfx/engine_thrust.wav")
	if looped == null:
		_check("looping_stream() returned a stream", false)
		return
	var wav := looped as AudioStreamWAV
	if wav == null:
		_check("looping_stream() returned an AudioStreamWAV", false)
		return
	_check("looping_stream() enables forward looping", wav.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	_check("looping_stream() loops the whole sample, not a zero-length window", wav.loop_end > wav.loop_begin)
	# The shared imported resource must not be mutated along the way, or every
	# one-shot use of the same WAV would start looping too.
	var shared := load("res://assets/sfx/engine_thrust.wav") as AudioStreamWAV
	_check("looping_stream() leaves the shared resource unlooped", shared.loop_mode == AudioStreamWAV.LOOP_DISABLED)


## ship_player.c reserves thrust, intake, shield and turbulence -- and nothing
## remote -- for the player's own craft.
func _check_player_loops() -> void:
	for node_name in ["EngineThrustSFX", "EngineIntakeSFX", "ShieldSFX", "TurbulenceSFX"]:
		var player := _player.get_node_or_null(node_name) as AudioStreamPlayer
		if player == null:
			_check("player has %s" % node_name, false)
			continue
		_check("%s plays on the SFX bus" % node_name, player.bus == "SFX")
		_check("%s is running (a reserved loop never stops)" % node_name, player.playing)
	_check("player has no remote engine loop", _player.get_node_or_null("EngineRemoteSFX") == null)


## ship_ai.c gives every remote one positional SFX_ENGINE_REMOTE instead.
func _check_ai_loop() -> void:
	var remote := _ai.get_node_or_null("EngineRemoteSFX") as AudioStreamPlayer3D
	if remote == null:
		_check("AI has EngineRemoteSFX", false)
		return
	_check("EngineRemoteSFX plays on the SFX bus", remote.bus == "SFX")
	_check("EngineRemoteSFX is running", remote.playing)
	_check("EngineRemoteSFX is positional over sfx_set_position()'s span", is_equal_approx(remote.max_distance, WipeoutAudio.SFX_3D_MAX_DISTANCE))
	_check("AI has no player-only intake loop", _ai.get_node_or_null("EngineIntakeSFX") == null)


## ship_player_update_sfx(): louder and higher-pitched with speed and thrust,
## silent shield until one is up. Absolute levels are the port's own; what is
## checked here is that each curve still moves the way the original's does.
func _check_player_curves() -> void:
	var intake := _player.get_node_or_null("EngineIntakeSFX") as AudioStreamPlayer
	var thrust := _player.get_node_or_null("EngineThrustSFX") as AudioStreamPlayer
	var shield := _player.get_node_or_null("ShieldSFX") as AudioStreamPlayer
	if intake == null or thrust == null or shield == null:
		return

	_player.is_racing = true
	_player.shield_active = false

	_player.velocity = Vector3.ZERO
	_player.thrust_mag = 0.0
	_player._update_engine_sfx()
	var idle_intake_pitch := intake.pitch_scale
	var idle_thrust_pitch := thrust.pitch_scale
	var idle_thrust_db := thrust.volume_db
	_check("intake is silent at a standstill", intake.volume_db <= -80.0)
	_check("shield is silent with no shield up", shield.volume_db <= -80.0)

	_player.velocity = Vector3(0.0, 0.0, -_player.SPEEDO_FULL_SPEED)
	_player.thrust_mag = _player.thrust_max
	_player._update_engine_sfx()
	_check("intake becomes audible with speed", intake.volume_db > -80.0)
	_check("intake pitch rises with speed", intake.pitch_scale > idle_intake_pitch)
	_check("thrust pitch rises with speed and throttle", thrust.pitch_scale > idle_thrust_pitch)
	_check("thrust gets louder under throttle", thrust.volume_db > idle_thrust_db)

	_player.shield_active = true
	_player._update_engine_sfx()
	_check("shield loop opens up while shielded", shield.volume_db > -80.0)

	# race_release_control() drops SHIP_RACING at the finish; the beds go with it.
	_player.is_racing = false
	_player._update_engine_sfx()
	_check("every loop mutes once the ship stops racing", intake.volume_db <= -80.0 and thrust.volume_db <= -80.0 and shield.volume_db <= -80.0)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures.append(what)

extends Node
class_name WipeoutAudio

## Menu SFX + random music, ported from menu.c / title.c / sfx.c.
##
## Autoloaded as `GameAudio`. In-race callers (wipeout_ship.gd, weapon and pad
## scripts) reach the SFX API through the `WipeoutAudio` class name and its
## static wrappers instead of that autoload identifier: those scripts are
## parse-time dependencies of the headless validators, which Godot compiles
## before any autoload exists, and an autoload name is not a compile-time
## identifier there.
## Impacts stay on WipeoutShip (SFX_CRUNCH). No HUD, engines, or weapons.

const SFX_MENU_MOVE := "res://assets/sfx/menu_move.wav"
const SFX_MENU_SELECT := "res://assets/sfx/menu_select.wav"

## In-race one-shots, one per sfx_play()/sfx_play_at() call site in ship.c,
## ship_player.c, weapon.c and ship_ai.c. Kept here (rather than next to each
## caller) so every SFX_* the port actually uses is listed in one place, like
## sfx.h's sfx_source_t.
const SFX_IMPACT := "res://assets/sfx/impact.wav" # ship vs. track: wing/nose/floor
const SFX_CRUNCH := "res://assets/sfx/crunch.wav" # ship vs. ship
const SFX_POWERUP := "res://assets/sfx/powerup.wav"
const SFX_MINE_DROP := "res://assets/sfx/mine_drop.wav"
const SFX_MISSILE_FIRE := "res://assets/sfx/missile_fire.wav" # missile, rocket and turbo
const SFX_EBOLT := "res://assets/sfx/ebolt.wav"
const SFX_EXPLOSION_1 := "res://assets/sfx/explosion_1.wav" # weapon hits a ship
const SFX_VOICE_MINES := "res://assets/sfx/voice_mines.wav"
const SFX_VOICE_MISSILE := "res://assets/sfx/voice_missile.wav"
const SFX_VOICE_ROCKETS := "res://assets/sfx/voice_rockets.wav"
const SFX_VOICE_SHOCKWAVE := "res://assets/sfx/voice_shockwave.wav"

## sfx.c's non-voice samples are 22 kHz played on a 44.1 kHz mixer, so its
## "unpitched" default is pitch 0.5 (sfx_get_node()). Godot imports every WAV at
## its own rate, so 1.0 is unpitched here and any literal C pitch has to be
## doubled to mean the same thing.
const C_PITCH_TO_GODOT := 2.0

## sfx_set_position()'s `clamp(scale(distance, 512, 32768, 1, 0), 0, 1)`: full
## volume within 512 PSX units and silent past 32768, i.e. 4.8 m and 307.7 m at
## convert_ships.py's 106.5 units/m. Godot has no linear 3D falloff, so the
## nearest model (inverse distance over the same span) is used instead.
const SFX_3D_UNIT_SIZE := 4.8
const SFX_3D_MAX_DISTANCE := 307.7

## Enough voices for a full grid's worth of overlapping impacts and explosions;
## sfx.c budgets SFX_MAX_ACTIVE = 16 for the same job.
const ONESHOT_VOICES := 16

const MUSIC_PATHS: Array[String] = [
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

## def.music names in MUSIC_PATHS order, listed by ingame_menus.c's MUSIC page.
const MUSIC_NAMES: Array[String] = [
	"CAIRODROME",
	"CARDINAL DANCER",
	"COLD COMFORT",
	"DOH T",
	"MESSIJ",
	"OPERATIQUE",
	"TENTATIVE",
	"TRANCEVAAL",
	"AFRO RIDE",
	"CHEMICAL BEATS",
	"WIPEOUT",
]

enum MusicMode { PAUSED, RANDOM, SEQUENTIAL, LOOP }

var music_mode: int = MusicMode.RANDOM
var track_index: int = -1
var skip_next_focus: bool = false

var _music: AudioStreamPlayer
var _sfx: AudioStreamPlayer
## Round-robin voices for play_sfx(); _sfx stays reserved for the menu beeps so
## a race one-shot can never cut one off (and vice versa).
var _oneshots: Array[AudioStreamPlayer] = []
var _next_oneshot: int = 0

## The running autoload, so the static wrappers below have something to play
## through. Null outside a running game (a validator that never starts the
## autoload), where every wrapper is a no-op.
static var _instance: WipeoutAudio = null


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = "Music"
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "Sfx"
	_sfx.bus = "SFX"
	_sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sfx)
	for i in ONESHOT_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "OneShot%d" % i
		voice.bus = "SFX"
		add_child(voice)
		_oneshots.append(voice)
	_music.finished.connect(_on_music_finished)


func _ready() -> void:
	_instance = self
	play_random_music()


func play_move() -> void:
	_play_oneshot(SFX_MENU_MOVE)


func play_select() -> void:
	_play_oneshot(SFX_MENU_SELECT)


func play_random_music() -> void:
	music_mode = MusicMode.RANDOM
	if MUSIC_PATHS.is_empty():
		return
	play_music(randi() % MUSIC_PATHS.size())


func play_music(index: int) -> void:
	if index < 0 or index >= MUSIC_PATHS.size():
		return
	if index == track_index and _music.stream != null:
		_music.play(0.0)
		return
	var path := MUSIC_PATHS[index]
	if not ResourceLoader.exists(path):
		push_warning("game_audio: missing %s" % path)
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	track_index = index
	_music.stream = stream
	_music.play()


# -----------------------------------------------------------------------------
# In-race SFX

## sfx_play(): a non-positional one-shot. `pitch` is in Godot terms (1.0 =
## unpitched); scale a literal from sfx.c by C_PITCH_TO_GODOT first.
static func play_sfx(path: String, pitch: float = 1.0) -> void:
	if _instance != null:
		_instance._play_sfx(path, pitch)


## sfx_play_at(): a one-shot at a point in the world, so it pans and attenuates
## against the camera the way sfx_set_position() does.
static func play_sfx_at(path: String, global_pos: Vector3, pitch: float = 1.0) -> void:
	if _instance != null:
		_instance._play_sfx_at(path, global_pos, pitch)


func _play_sfx(path: String, pitch: float = 1.0) -> void:
	var stream := _load_stream(path)
	if stream == null or _oneshots.is_empty():
		return
	var voice := _free_voice()
	voice.stream = stream
	voice.pitch_scale = maxf(pitch, 0.01)
	voice.play()


## The player outlives the node that triggered it (a weapon frees itself the
## moment it explodes), so it is parented to the running scene and frees itself
## when the sample ends.
func _play_sfx_at(path: String, global_pos: Vector3, pitch: float = 1.0) -> void:
	var stream := _load_stream(path)
	if stream == null:
		return
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene == null:
		_play_sfx(path, pitch)
		return
	var voice := AudioStreamPlayer3D.new()
	voice.stream = stream
	voice.pitch_scale = maxf(pitch, 0.01)
	voice.bus = "SFX"
	configure_3d_falloff(voice)
	scene.add_child(voice)
	voice.global_position = global_pos
	voice.finished.connect(voice.queue_free)
	voice.play()


## sfx_set_position()'s distance curve, shared by every positional player in the
## port so they all fade over the same span.
static func configure_3d_falloff(player: AudioStreamPlayer3D) -> void:
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.unit_size = SFX_3D_UNIT_SIZE
	player.max_distance = SFX_3D_MAX_DISTANCE


## sfx_reserve_loop(): the engine/shield/turbulence beds that run for a ship's
## whole race. The imported WAVs have looping off (every other caller wants them
## as one-shots), so the flag is flipped on a per-caller duplicate rather than on
## the shared resource.
static func looping_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("game_audio: missing %s" % path)
		return null
	var source := load(path) as AudioStreamWAV
	if source == null:
		return null
	var looped := source.duplicate() as AudioStreamWAV
	looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
	looped.loop_begin = 0
	# loop_end defaults to 0, which would loop a zero-length window; point it at
	# the real end of the sample instead.
	var frames := int(source.get_length() * float(source.mix_rate))
	if frames > 0:
		looped.loop_end = frames
	return looped


func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("game_audio: missing %s" % path)
		return null
	return load(path) as AudioStream


## The first idle voice, or the next in round-robin order when every one of them
## is busy (sfx_get_node() steals an unreserved node the same way).
func _free_voice() -> AudioStreamPlayer:
	for i in _oneshots.size():
		var index := (_next_oneshot + i) % _oneshots.size()
		if not _oneshots[index].playing:
			_next_oneshot = index
			return _oneshots[index]
	_next_oneshot = (_next_oneshot + 1) % _oneshots.size()
	return _oneshots[_next_oneshot]


# -----------------------------------------------------------------------------
# Menus

func prepare_focus() -> void:
	skip_next_focus = true


func hook_menu(root: Node) -> void:
	prepare_focus()
	_wire(root)
	call_deferred("_release_skip")


func _release_skip() -> void:
	skip_next_focus = false


func _wire(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		if not button.focus_entered.is_connected(_on_button_focus):
			button.focus_entered.connect(_on_button_focus)
		if not button.pressed.is_connected(_on_button_pressed):
			button.pressed.connect(_on_button_pressed)
	for child in node.get_children():
		_wire(child)


func _on_button_focus() -> void:
	if skip_next_focus:
		skip_next_focus = false
		return
	play_move()


func _on_button_pressed() -> void:
	play_select()


func _play_oneshot(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	_sfx.stream = stream
	_sfx.play()


func _on_music_finished() -> void:
	if music_mode == MusicMode.PAUSED:
		return
	if music_mode == MusicMode.LOOP:
		play_music(track_index)
		return
	if music_mode == MusicMode.SEQUENTIAL:
		play_music((track_index + 1) % MUSIC_PATHS.size())
		return
	play_random_music()

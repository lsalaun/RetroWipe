extends Node

## Menu SFX + random music, ported from menu.c / title.c / sfx.c.
## Impacts stay on WipeoutShip (SFX_CRUNCH). No HUD, engines, or weapons.

const SFX_MENU_MOVE := "res://assets/sfx/menu_move.wav"
const SFX_MENU_SELECT := "res://assets/sfx/menu_select.wav"
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


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "Sfx"
	_sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sfx)
	_music.finished.connect(_on_music_finished)


func _ready() -> void:
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

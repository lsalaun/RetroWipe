extends SceneTree

## Headless check that menu SFX + music autoload consume imported assets.

const GameAudioScript = preload("res://scripts/game_audio.gd")
const SFX_MOVE := "res://assets/sfx/menu_move.wav"
const SFX_SELECT := "res://assets/sfx/menu_select.wav"

var _frames := 0


func _initialize() -> void:
	if not _check_files():
		quit(1)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	if not _check_runtime():
		quit(1)
		return true
	print("validate_game_audio: OK")
	quit(0)
	return true


func _check_runtime() -> bool:
	var audio := root.get_node_or_null("GameAudio")
	if audio == null:
		push_error("validate_game_audio: GameAudio autoload missing")
		return false
	if GameAudioScript.MUSIC_PATHS.size() != 11:
		push_error("validate_game_audio: expected 11 music tracks")
		return false
	audio.call("play_select")
	var sfx := audio.get_node_or_null("Sfx") as AudioStreamPlayer
	var music := audio.get_node_or_null("Music") as AudioStreamPlayer
	if sfx == null or music == null:
		push_error("validate_game_audio: missing Music/Sfx players")
		return false
	if music.bus != "Music" or sfx.bus != "SFX":
		push_error("validate_game_audio: players not on independent buses (music=%s sfx=%s)" % [music.bus, sfx.bus])
		return false
	if sfx.stream == null or sfx.stream.resource_path != SFX_SELECT:
		push_error("validate_game_audio: select stream %s" % (sfx.stream.resource_path if sfx.stream else "null"))
		return false
	audio.call("play_move")
	if sfx.stream == null or sfx.stream.resource_path != SFX_MOVE:
		push_error("validate_game_audio: move stream mismatch")
		return false
	if music.stream == null:
		push_error("validate_game_audio: music not started")
		return false
	var music_path := str(music.stream.resource_path)
	if not music_path.begins_with("res://assets/music/"):
		push_error("validate_game_audio: unexpected music %s" % music_path)
		return false
	return true


func _check_files() -> bool:
	for path in GameAudioScript.MUSIC_PATHS:
		if not ResourceLoader.exists(path):
			push_error("validate_game_audio: missing %s" % path)
			return false
	if not ResourceLoader.exists(SFX_MOVE) or not ResourceLoader.exists(SFX_SELECT):
		push_error("validate_game_audio: missing menu wav")
		return false
	return true

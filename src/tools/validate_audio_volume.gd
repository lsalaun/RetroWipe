extends SceneTree

## Headless check for the independent MUSIC VOLUME / SOUND EFFECTS VOLUME
## sliders added to match src/wipeout/main_menu.c's page_options_audio_init()
## (toggle_music_volume()/toggle_sfx_volume(), each driving save.music_volume /
## save.sfx_volume independently in sfx_stereo_mix()): Settings creates a
## Music and an SFX bus, and each volume only moves its own bus.
##
## Autoload names are not compile-time identifiers in --script mode, so the
## live autoload is fetched off the root instead of being preloaded.

var _failures: Array[String] = []
var _frames := 0
var _settings: Node = null

## Restored at the end so running this validator never leaves the developer's
## real user://settings.cfg with scratch volume values.
var _orig_music_volume: float = 0.0
var _orig_sfx_volume: float = 0.0


func _initialize() -> void:
	_settings = root.get_node_or_null("Settings")
	if _settings == null:
		push_error("validate_audio_volume: Settings autoload missing")
		quit(1)
		return


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	_orig_music_volume = _settings.music_volume
	_orig_sfx_volume = _settings.sfx_volume

	_check_buses_exist()
	_check_defaults_match_save_t()
	_check_independent_volumes()
	_check_persistence_round_trip()

	_settings.set_music_volume(_orig_music_volume)
	_settings.set_sfx_volume(_orig_sfx_volume)

	if _failures.is_empty():
		print("validate_audio_volume: OK")
		quit(0)
	else:
		for failure in _failures:
			push_error("validate_audio_volume: %s" % failure)
		quit(1)
	return true


## _ensure_audio_buses() must have already run (Settings._ready(), ahead of
## GameAudio in project.godot's autoload order).
func _check_buses_exist() -> void:
	_check("Music bus exists", AudioServer.get_bus_index("Music") != -1)
	_check("SFX bus exists", AudioServer.get_bus_index("SFX") != -1)


## save_t's literal defaults: .sfx_volume = 0.6, .music_volume = 0.5.
func _check_defaults_match_save_t() -> void:
	# Reads whatever _ensure_audio_buses()/_load() left them at, before this
	# test starts mutating them below -- a fresh install has no settings.cfg.
	if not FileAccess.file_exists("user://settings.cfg"):
		_check("fresh install: music_volume defaults to 0.5", is_equal_approx(_orig_music_volume, 0.5))
		_check("fresh install: sfx_volume defaults to 0.6", is_equal_approx(_orig_sfx_volume, 0.6))


func _check_independent_volumes() -> void:
	var music_bus := AudioServer.get_bus_index("Music")
	var sfx_bus := AudioServer.get_bus_index("SFX")

	_settings.set_music_volume(1.0)
	_settings.set_sfx_volume(1.0)
	var music_db_loud := AudioServer.get_bus_volume_db(music_bus)
	var sfx_db_loud := AudioServer.get_bus_volume_db(sfx_bus)

	_settings.set_music_volume(0.1)
	var music_db_quiet := AudioServer.get_bus_volume_db(music_bus)
	var sfx_db_unchanged := AudioServer.get_bus_volume_db(sfx_bus)
	_check("lowering music_volume only moves the Music bus", music_db_quiet < music_db_loud)
	_check("lowering music_volume leaves the SFX bus alone", is_equal_approx(sfx_db_unchanged, sfx_db_loud))

	_settings.set_sfx_volume(0.1)
	var sfx_db_quiet := AudioServer.get_bus_volume_db(sfx_bus)
	var music_db_unchanged := AudioServer.get_bus_volume_db(music_bus)
	_check("lowering sfx_volume only moves the SFX bus", sfx_db_quiet < sfx_db_loud)
	_check("lowering sfx_volume leaves the Music bus alone", is_equal_approx(music_db_unchanged, music_db_quiet))


func _check_persistence_round_trip() -> void:
	_settings.set_music_volume(0.3)
	_settings.set_sfx_volume(0.9)

	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		_check("settings.cfg written after set_*_volume()", false)
		return
	_check("music_volume persisted", is_equal_approx(float(cfg.get_value("audio", "music_volume", -1.0)), 0.3))
	_check("sfx_volume persisted", is_equal_approx(float(cfg.get_value("audio", "sfx_volume", -1.0)), 0.9))


func _check(what: String, ok: bool) -> void:
	if not ok:
		_failures.append(what)

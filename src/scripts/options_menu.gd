extends WipeoutMenu

## Options root: src/wipeout/main_menu.c's page_options_init.
##
## The original's fourth entry, BEST TIMES, opens the highscore tables. This
## port only keeps lap records (Settings.lap_records), not the per-circuit
## highscore lists that page reads, so the entry is left out.

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const CONTROLS_MENU := "res://scenes/OptionsControlsMenu.tscn"
const VIDEO_MENU := "res://scenes/OptionsVideoMenu.tscn"
const AUDIO_MENU := "res://scenes/OptionsAudioMenu.tscn"


func _build() -> void:
	back_scene = MAIN_MENU

	var page := push_page("OPTIONS")
	page.layout_flags |= FIXED
	page.title_pos = Vector2(0.0, 30.0)
	page.title_anchor = TOP_CENTER
	page.items_pos = Vector2(0.0, -110.0)
	page.items_anchor = BOTTOM_CENTER

	page.add_button(0, "CONTROLS", _open.bind(CONTROLS_MENU))
	page.add_button(1, "VIDEO", _open.bind(VIDEO_MENU))
	page.add_button(2, "AUDIO", _open.bind(AUDIO_MENU))


## Callable.bind() appends its arguments, so the entry's data comes first and
## is ignored.
func _open(_data: int, scene: String) -> void:
	get_tree().change_scene_to_file(scene)

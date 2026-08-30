extends WipeoutMenu

## Options root: src/wipeout/main_menu.c's page_options_init.
##
## page_options_draw() spins a 3D model behind the highlighted entry: PAD1.PRM
## for CONTROLS, the rescue droid for VIDEO (the original's own comment on
## that line calls it a placeholder: "TODO: needs better model" -- droid.c's
## RESCU.PRM is reused as-is, not duplicated), and ALOPT.PRM's headphones for
## AUDIO.
##
## The original's fourth entry, BEST TIMES, opens the highscore tables. This
## port only keeps lap records (Settings.lap_records), not the per-circuit
## highscore lists that page reads, so the entry (and its ALOPT.PRM stopwatch
## model, shown instead on RaceTypeMenu.tscn's TIME TRIAL) is left out.

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const CONTROLS_MENU := "res://scenes/OptionsControlsMenu.tscn"
const VIDEO_MENU := "res://scenes/OptionsVideoMenu.tscn"
const AUDIO_MENU := "res://scenes/OptionsAudioMenu.tscn"

const PREVIEW_POS := Vector2(0.0, -40.0)
const PREVIEW_SIZE := Vector2(80.0, 80.0)

## page_options_draw()'s switch(data).
const MODEL_PATHS: Array[String] = [
	"res://assets/menu_models/controller/controller/controller.glb",
	"res://assets/droid/rescue_droid/rescue_droid.glb",
	"res://assets/menu_models/options/headphones/headphones.glb",
]

var _preview: MenuModelPreview


func _build() -> void:
	back_scene = MAIN_MENU
	_preview = _add_model_preview()

	var page := push_page("OPTIONS", _draw_model)
	page.layout_flags |= FIXED
	page.title_pos = Vector2(0.0, 30.0)
	page.title_anchor = TOP_CENTER
	page.items_pos = Vector2(0.0, -110.0)
	page.items_anchor = BOTTOM_CENTER

	page.add_button(0, "CONTROLS", _open.bind(CONTROLS_MENU))
	page.add_button(1, "VIDEO", _open.bind(VIDEO_MENU))
	page.add_button(2, "AUDIO", _open.bind(AUDIO_MENU))


func _draw_model(data: int, scale: float) -> void:
	if data < 0 or data >= MODEL_PATHS.size():
		return
	_preview.show_model(MODEL_PATHS[data])
	_draw_model_preview(_preview, MIDDLE_CENTER, PREVIEW_POS, PREVIEW_SIZE, scale)


## Callable.bind() appends its arguments, so the entry's data comes first and
## is ignored.
func _open(_data: int, scene: String) -> void:
	get_tree().change_scene_to_file(scene)

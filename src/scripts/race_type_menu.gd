extends WipeoutMenu

## Race type selection: src/wipeout/main_menu.c's page_race_type_init
## (CHAMPIONSHIP RACE / SINGLE RACE / TIME TRIAL).
##
## page_race_type_draw() spins a 3D model behind the highlighted entry:
## MSDOS.PRM's championship/single_race icons, and ALOPT.PRM's stopwatch for
## TIME TRIAL (the same model OptionsMenu.tscn's BEST TIMES would use).

const RACE_CLASS_MENU := "res://scenes/RaceClassMenu.tscn"
const TEAM_MENU := "res://scenes/TeamMenu.tscn"

const PREVIEW_POS := Vector2(0.0, -40.0)
const PREVIEW_SIZE := Vector2(80.0, 80.0)

## page_race_type_draw()'s switch(data), in RaceSetup.RACE_TYPE_* order.
const MODEL_PATHS: Array[String] = [
	"res://assets/menu_models/misc/championship/championship.glb",
	"res://assets/menu_models/misc/single_race/single_race.glb",
	"res://assets/menu_models/options/stopwatch/stopwatch.glb",
]

var _preview: MenuModelPreview


func _build() -> void:
	back_scene = RACE_CLASS_MENU
	_preview = _add_model_preview()

	var page := push_page("SELECT RACE TYPE", _draw_model)
	page.layout_flags |= FIXED
	page.title_pos = Vector2(0.0, 30.0)
	page.title_anchor = TOP_CENTER
	page.items_pos = Vector2(0.0, -110.0)
	page.items_anchor = BOTTOM_CENTER

	for i in RaceSetup.RACE_TYPES.size():
		page.add_button(i, RaceSetup.RACE_TYPES[i], _select_type)


func _draw_model(data: int, scale: float) -> void:
	if data < 0 or data >= MODEL_PATHS.size():
		return
	_preview.show_model(MODEL_PATHS[data])
	_draw_model_preview(_preview, MIDDLE_CENTER, PREVIEW_POS, PREVIEW_SIZE, scale)


func _select_type(data: int) -> void:
	RaceSetup.select_race_type(data)
	get_tree().change_scene_to_file(TEAM_MENU)

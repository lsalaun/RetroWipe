extends WipeoutMenu

## Race class selection: src/wipeout/main_menu.c's page_race_class_init
## (VENOM CLASS / RAPIER CLASS).
##
## page_race_class_init() leaves the page auto-centred and page_race_class_draw()
## adds MENU_FIXED with the top/bottom anchors on the first frame; the flags are
## set up front here since the result is the same from frame two onwards.
##
## page_race_class_draw() also spins the class's LEEG.PRM model between the
## title and the list (models.race_classes[data]); _draw_model swaps it per
## selection. RAPIER CLASS stays greyed out ("NOT AVAILABLE") and unselectable
## until Settings.has_rapier_class, set the first time a VENOM championship is
## completed (see Championship.complete_championship()).

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const RACE_TYPE_MENU := "res://scenes/RaceTypeMenu.tscn"

## page_race_class_draw(): draw_model(..., vec2(0, -0.2), vec3(0, 0, -350), ...).
const PREVIEW_POS := Vector2(0.0, -40.0)
const PREVIEW_SIZE := Vector2(96.0, 96.0)

## page->items_pos + (0, 32), same BOTTOM_CENTER anchor as the button list.
const NOT_AVAILABLE_POS := Vector2(0.0, -78.0)

## models.race_classes[], LEEG.PRM's load order, one glb per RACE_CLASS_* value.
const MODEL_PATHS: Array[String] = [
	"res://assets/menu_models/race_classes/venom/venom.glb",
	"res://assets/menu_models/race_classes/rapier/rapier.glb",
]

var _preview: MenuModelPreview


func _build() -> void:
	back_scene = MAIN_MENU
	_preview = _add_model_preview()

	var page := push_page("SELECT RACING CLASS", _draw_model)
	page.layout_flags |= FIXED
	page.title_pos = Vector2(0.0, 30.0)
	page.title_anchor = TOP_CENTER
	page.items_pos = Vector2(0.0, -110.0)
	page.items_anchor = BOTTOM_CENTER

	for i in RaceSetup.RACE_CLASSES.size():
		page.add_button(i, RaceSetup.RACE_CLASSES[i], _select_class)


func _draw_model(data: int, scale: float) -> void:
	if data < 0 or data >= MODEL_PATHS.size():
		return
	_preview.show_model(MODEL_PATHS[data])
	_draw_model_preview(_preview, MIDDLE_CENTER, PREVIEW_POS, PREVIEW_SIZE, scale)
	if data == RaceSetup.RACE_CLASS_RAPIER and not Settings.has_rapier_class:
		WipeoutUI.draw_text_centered(self, "NOT AVAILABLE", _anchored(BOTTOM_CENTER, NOT_AVAILABLE_POS, scale), WipeoutUI.SIZE_12, WipeoutUI.COLOR_ACCENT, scale)


func _select_class(data: int) -> void:
	if data == RaceSetup.RACE_CLASS_RAPIER and not Settings.has_rapier_class:
		return
	RaceSetup.select_race_class(data)
	get_tree().change_scene_to_file(RACE_TYPE_MENU)

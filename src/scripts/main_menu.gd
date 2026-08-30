extends WipeoutMenu

## Top-level menu: src/wipeout/main_menu.c's page_main_init
## (START GAME / OPTIONS / QUIT, with QUIT going through menu_confirm).
##
## The title really is "OPTIONS": page_main_init() passes that string to
## menu_push(), so the original draws it above START GAME too. It is kept here
## rather than corrected so the page matches the C build pixel for pixel.
##
## page_main_draw() spins a 3D model beside the highlighted entry: g.ships[0]
## (whichever ship happens to be loaded first -- nothing is picked yet at this
## point) for START GAME, and MSDOS.PRM's options/msdos icons for the other
## two entries.

const RACE_CLASS_MENU := "res://scenes/RaceClassMenu.tscn"
const OPTIONS_MENU := "res://scenes/OptionsMenu.tscn"

const PREVIEW_POS := Vector2(0.0, -40.0)
const PREVIEW_SIZE := Vector2(90.0, 90.0)

## page_main_draw()'s switch(data). Index 0 stands in for g.ships[0].model:
## any ship works since none is selected yet on this page.
const MODEL_PATHS: Array[String] = [
	"res://assets/ships/sophia/sophia.glb",
	"res://assets/menu_models/misc/options/options.glb",
	"res://assets/menu_models/misc/msdos/msdos.glb",
]

var _preview: MenuModelPreview


func _build() -> void:
	# menu_pop() at page 0 does nothing, so the main menu has nowhere to go back
	# to; the title screen is only ever reached forwards.
	back_scene = ""
	_preview = _add_model_preview()

	var page := push_page("OPTIONS", _draw_model)
	page.layout_flags |= FIXED
	page.title_pos = Vector2(0.0, 30.0)
	page.title_anchor = TOP_CENTER
	page.items_pos = Vector2(0.0, -110.0)
	page.items_anchor = BOTTOM_CENTER

	page.add_button(0, "START GAME", _start_game)
	page.add_button(1, "OPTIONS", _options)
	page.add_button(2, "QUIT", _quit)


func _draw_model(data: int, scale: float) -> void:
	if data < 0 or data >= MODEL_PATHS.size():
		return
	_preview.show_model(MODEL_PATHS[data])
	_draw_model_preview(_preview, MIDDLE_CENTER, PREVIEW_POS, PREVIEW_SIZE, scale)


func _start_game(_data: int) -> void:
	get_tree().change_scene_to_file(RACE_CLASS_MENU)


func _options(_data: int) -> void:
	get_tree().change_scene_to_file(OPTIONS_MENU)


func _quit(_data: int) -> void:
	push_confirm("ARE YOU SURE YOU", "WANT TO QUIT", "YES", "NO", _quit_confirm)


func _quit_confirm(data: int) -> void:
	if data:
		get_tree().quit()
	else:
		pop_page()

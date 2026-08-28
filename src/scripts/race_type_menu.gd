extends WipeoutMenu

## Race type selection: src/wipeout/main_menu.c's page_race_type_init
## (CHAMPIONSHIP RACE / SINGLE RACE / TIME TRIAL).
##
## The original spins a 3D model for the highlighted type; the menu models are
## not imported in this port.

const RACE_CLASS_MENU := "res://scenes/RaceClassMenu.tscn"
const TEAM_MENU := "res://scenes/TeamMenu.tscn"


func _build() -> void:
	back_scene = RACE_CLASS_MENU

	var page := push_page("SELECT RACE TYPE")
	page.layout_flags |= FIXED
	page.title_pos = Vector2(0.0, 30.0)
	page.title_anchor = TOP_CENTER
	page.items_pos = Vector2(0.0, -110.0)
	page.items_anchor = BOTTOM_CENTER

	for i in RaceSetup.RACE_TYPES.size():
		page.add_button(i, RaceSetup.RACE_TYPES[i], _select_type)


func _select_type(data: int) -> void:
	RaceSetup.select_race_type(data)
	get_tree().change_scene_to_file(TEAM_MENU)

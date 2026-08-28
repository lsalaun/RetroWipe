extends WipeoutMenu

## Race class selection: src/wipeout/main_menu.c's page_race_class_init
## (VENOM CLASS / RAPIER CLASS).
##
## page_race_class_init() leaves the page auto-centred and page_race_class_draw()
## adds MENU_FIXED with the top/bottom anchors on the first frame; the flags are
## set up front here since the result is the same from frame two onwards.
##
## The original also spins the class's 3D model between the title and the list,
## and greys out RAPIER CLASS until it is unlocked. Neither the menu models nor
## a save file with unlocks exist in this port.

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const RACE_TYPE_MENU := "res://scenes/RaceTypeMenu.tscn"


func _build() -> void:
	back_scene = MAIN_MENU

	var page := push_page("SELECT RACING CLASS")
	page.layout_flags |= FIXED
	page.title_pos = Vector2(0.0, 30.0)
	page.title_anchor = TOP_CENTER
	page.items_pos = Vector2(0.0, -110.0)
	page.items_anchor = BOTTOM_CENTER

	for i in RaceSetup.RACE_CLASSES.size():
		page.add_button(i, RaceSetup.RACE_CLASSES[i], _select_class)


func _select_class(data: int) -> void:
	RaceSetup.select_race_class(data)
	get_tree().change_scene_to_file(RACE_TYPE_MENU)

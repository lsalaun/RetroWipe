extends WipeoutMenu

## Team selection: src/wipeout/main_menu.c's page_team_init.
##
## The original spins the team logo and both of its ships above the list
## (page_team_draw); the menu models are not imported in this port.

const RACE_TYPE_MENU := "res://scenes/RaceTypeMenu.tscn"
const PILOT_MENU := "res://scenes/PilotMenu.tscn"


func _build() -> void:
	back_scene = RACE_TYPE_MENU

	var page := push_page("SELECT YOUR TEAM")
	page.layout_flags |= FIXED
	page.title_pos = Vector2(0.0, 30.0)
	page.title_anchor = TOP_CENTER
	page.items_pos = Vector2(0.0, -110.0)
	page.items_anchor = BOTTOM_CENTER

	for i in RaceSetup.TEAM_ORDER.size():
		page.add_button(i, RaceSetup.TEAM_ORDER[i], _select_team)


func _select_team(data: int) -> void:
	RaceSetup.select_team(RaceSetup.TEAM_ORDER[data])
	get_tree().change_scene_to_file(PILOT_MENU)

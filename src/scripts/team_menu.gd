extends WipeoutMenu

## Team selection: src/wipeout/main_menu.c's page_team_init.
##
## page_team_draw() spins the team's TEAMS.PRM logo centred above the list,
## plus both of the team's ships either side of it (def.teams[data].pilots[0]
## on the left, [1] on the right) -- the same ship GLBs ShipSelection and
## pilot_menu.gd already use. TEAMS.PRM's own object order is shifted by one
## team ("models in the prm are shifted by -1" per the original's comment);
## TEAM_LOGOS below is keyed by team name instead so that indirection only has
## to be resolved once, while the asset import pipeline was renaming the glbs.

const RACE_TYPE_MENU := "res://scenes/RaceTypeMenu.tscn"
const PILOT_MENU := "res://scenes/PilotMenu.tscn"

const LOGO_POS := Vector2(0.0, -50.0)
const LOGO_SIZE := Vector2(96.0, 96.0)
const SHIP_SIZE := Vector2(72.0, 72.0)
const SHIP_OFFSET_X := 70.0
const SHIP_POS_Y := -35.0

const TEAM_LOGOS: Dictionary = {
	"AG SYSTEMS": "res://assets/menu_models/teams/ag_systems/ag_systems.glb",
	"AURICOM": "res://assets/menu_models/teams/auricom/auricom.glb",
	"QIREX": "res://assets/menu_models/teams/qirex/qirex.glb",
	"FEISAR": "res://assets/menu_models/teams/feisar/feisar.glb",
}

var _logo_preview: MenuModelPreview
var _ship_previews: Array[MenuModelPreview] = []
var _shown_team := ""
var _team_ships: Array[Dictionary] = []


func _build() -> void:
	back_scene = RACE_TYPE_MENU
	_logo_preview = _add_model_preview()
	_ship_previews = [_add_model_preview(), _add_model_preview()]

	var page := push_page("SELECT YOUR TEAM", _draw_models)
	page.layout_flags |= FIXED
	page.title_pos = Vector2(0.0, 30.0)
	page.title_anchor = TOP_CENTER
	page.items_pos = Vector2(0.0, -110.0)
	page.items_anchor = BOTTOM_CENTER

	for i in RaceSetup.TEAM_ORDER.size():
		page.add_button(i, RaceSetup.TEAM_ORDER[i], _select_team)


func _draw_models(data: int, scale: float) -> void:
	if data < 0 or data >= RaceSetup.TEAM_ORDER.size():
		return
	var team: String = RaceSetup.TEAM_ORDER[data]
	if team != _shown_team:
		_shown_team = team
		_team_ships = RaceSetup.pilots_for_team(team)

	_logo_preview.show_model(str(TEAM_LOGOS.get(team, "")))
	_draw_model_preview(_logo_preview, MIDDLE_CENTER, LOGO_POS, LOGO_SIZE, scale)

	for i in mini(2, _team_ships.size()):
		var mesh_path := str(_team_ships[i].get("mesh", ""))
		var x := -SHIP_OFFSET_X if i == 0 else SHIP_OFFSET_X
		_ship_previews[i].show_model(mesh_path)
		_draw_model_preview(_ship_previews[i], MIDDLE_CENTER, Vector2(x, SHIP_POS_Y), SHIP_SIZE, scale)


func _select_team(data: int) -> void:
	RaceSetup.select_team(RaceSetup.TEAM_ORDER[data])
	get_tree().change_scene_to_file(PILOT_MENU)

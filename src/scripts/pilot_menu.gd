extends WipeoutMenu

## Pilot selection: src/wipeout/main_menu.c's page_pilot_init. Pilots are
## restricted to the team chosen on TeamMenu.tscn.
##
## page_pilot_draw() spins models.pilots[def.pilots[data].logo_model] above the
## list. PILOT.PRM objects keep their own dev names rather than the pilot's
## (Paul Jackson's is still named "leroy"), so PILOT_LOGO_MODEL below maps
## pilot name -> glb directly instead of re-deriving the logo_model indices.
## def.pilots[].portrait (the CMP portrait this page used to show as a
## stand-in) is drawn on the race HUD instead (see ingame_menus.c); it is not
## part of this page in the original either.

const TEAM_MENU := "res://scenes/TeamMenu.tscn"
const CIRCUIT_MENU := "res://scenes/CircuitMenu.tscn"

## page_pilot_draw(): draw_model(..., vec2(0, -0.2), vec3(0, 0, -10000), ...).
const PREVIEW_POS := Vector2(0.0, -45.0)
const PREVIEW_SIZE := Vector2(110.0, 110.0)

## def.pilots[].logo_model, resolved ahead of time to the PILOT.PRM object each
## index names.
const PILOT_LOGO_MODEL: Dictionary = {
	"John Dekka": "res://assets/menu_models/pilots/dekka/dekka.glb",
	"Daniel Chang": "res://assets/menu_models/pilots/chang/chang.glb",
	"Arial Tetsuo": "res://assets/menu_models/pilots/arial/arial.glb",
	"Anastasia Cherovoski": "res://assets/menu_models/pilots/anasta/anasta.glb",
	"Kel Solaar": "res://assets/menu_models/pilots/solaar/solaar.glb",
	"Arian Tetsuo": "res://assets/menu_models/pilots/arian/arian.glb",
	"Sofia De La Rente": "res://assets/menu_models/pilots/sophia/sophia.glb",
	"Paul Jackson": "res://assets/menu_models/pilots/leroy/leroy.glb",
}

var _pilots: Array[Dictionary] = []
var _preview: MenuModelPreview


func _build() -> void:
	back_scene = TEAM_MENU
	_preview = _add_model_preview()

	var page := push_page("CHOOSE YOUR PILOT", _draw_model)
	page.layout_flags |= FIXED
	page.title_pos = Vector2(0.0, 30.0)
	page.title_anchor = TOP_CENTER
	page.items_pos = Vector2(0.0, -110.0)
	page.items_anchor = BOTTOM_CENTER

	var team := RaceSetup.team_name
	if team == "":
		team = RaceSetup.TEAM_ORDER[0]

	_pilots = RaceSetup.pilots_for_team(team)
	for i in _pilots.size():
		var ship := _pilots[i]
		page.add_button(i, str(ship["pilot"]), _select_pilot)


## The PILOT.PRM glb shown for entry `index`, or "" when out of range.
func model_path_for(index: int) -> String:
	if index < 0 or index >= _pilots.size():
		return ""
	var pilot := str(_pilots[index].get("pilot", ""))
	return str(PILOT_LOGO_MODEL.get(pilot, ""))


func _draw_model(data: int, scale: float) -> void:
	_preview.show_model(model_path_for(data))
	_draw_model_preview(_preview, MIDDLE_CENTER, PREVIEW_POS, PREVIEW_SIZE, scale)


func _select_pilot(data: int) -> void:
	if data < 0 or data >= _pilots.size():
		return
	RaceSetup.select_pilot(_pilots[data])

	if RaceSetup.race_type == RaceSetup.RACE_TYPE_CHAMPIONSHIP:
		# button_pilot_select(): g.circuit = 0; game_reset_championship();
		# game_set_scene(GAME_SCENE_RACE); -- circuit 0 is CIRCUIT_ALTIMA_VII,
		# not TrackSelection.TRACKS[0] (TERRAMAX), and still needs the
		# class-correct variant, same as circuit_menu.gd's own selection.
		Championship.reset()
		var scene := TrackSelection.scene_for_circuit(Championship.current_circuit(), RaceSetup.race_class)
		TrackSelection.select_track(scene)
		TrackSelection.start_race(get_tree())
	else:
		get_tree().change_scene_to_file(CIRCUIT_MENU)

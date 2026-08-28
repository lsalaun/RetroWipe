extends WipeoutMenu

## Pilot selection: src/wipeout/main_menu.c's page_pilot_init. Pilots are
## restricted to the team chosen on TeamMenu.tscn.
##
## page_pilot_draw() spins the pilot's 3D logo model above the list. That model
## is not imported here, so the page shows the pilot's CMP portrait
## (def.pilots[].portrait, frame 0) in the same spot instead.

const TEAM_MENU := "res://scenes/TeamMenu.tscn"
const CIRCUIT_MENU := "res://scenes/CircuitMenu.tscn"

## Where page_circuit_draw() puts its artwork, reused for the portrait.
const PORTRAIT_POS := Vector2(0.0, -25.0)

var _pilots: Array[Dictionary] = []
var _portraits: Array[Texture2D] = []


func _build() -> void:
	back_scene = TEAM_MENU

	var page := push_page("CHOOSE YOUR PILOT", _draw_portrait)
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
		var path := str(ship.get("portrait", ""))
		if path != "" and ResourceLoader.exists(path):
			_portraits.append(load(path) as Texture2D)
		else:
			_portraits.append(null)


## The portrait shown for entry `index`, or null when the CMP export is missing.
func portrait_texture(index: int) -> Texture2D:
	if index < 0 or index >= _portraits.size():
		return null
	return _portraits[index]


func _draw_portrait(data: int, scale: float) -> void:
	var texture := portrait_texture(data)
	if texture == null:
		return
	var portrait_size := Vector2(texture.get_size())
	var top_left := _anchored(MIDDLE_CENTER, PORTRAIT_POS - portrait_size * 0.5, scale)
	draw_texture_rect(texture, Rect2(top_left, portrait_size * scale), false)


func _select_pilot(data: int) -> void:
	if data < 0 or data >= _pilots.size():
		return
	RaceSetup.select_pilot(_pilots[data])

	if RaceSetup.race_type == RaceSetup.RACE_TYPE_CHAMPIONSHIP:
		# Championships always start on the first available circuit.
		TrackSelection.select_track(TrackSelection.TRACKS[0]["scene"])
		TrackSelection.start_race(get_tree())
	else:
		get_tree().change_scene_to_file(CIRCUIT_MENU)

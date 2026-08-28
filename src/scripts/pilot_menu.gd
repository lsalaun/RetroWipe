extends Control

## Pilot selection: src/wipeout/main_menu.c's page_pilot_init. Pilots are
## restricted to the team chosen on TeamMenu.tscn. CMP portraits (frame 0)
## come from def.pilots[].portrait.

const MenuBackdrop := preload("res://scripts/menu_backdrop.gd")

@onready var portrait: TextureRect = $CenterContainer/HBoxContainer/Portrait
@onready var pilot_list: VBoxContainer = $CenterContainer/HBoxContainer/VBoxContainer/PilotList
@onready var back_button: Button = $CenterContainer/HBoxContainer/VBoxContainer/BackButton


func _ready() -> void:
	MenuBackdrop.attach(self)
	var team := RaceSetup.team_name
	if team == "":
		team = RaceSetup.TEAM_ORDER[0]
	var first_ship: Dictionary = {}
	for ship in RaceSetup.pilots_for_team(team):
		var button := Button.new()
		button.text = ship["pilot"]
		button.pressed.connect(_on_pilot_selected.bind(ship))
		button.focus_entered.connect(_show_portrait.bind(ship))
		pilot_list.add_child(button)
		if first_ship.is_empty():
			first_ship = ship
	back_button.pressed.connect(_on_back_pressed)
	if not first_ship.is_empty():
		_show_portrait(first_ship)
	GameAudio.hook_menu(self)
	if pilot_list.get_child_count() > 0:
		pilot_list.get_child(0).grab_focus()


func _show_portrait(ship: Dictionary) -> void:
	var path := str(ship.get("portrait", ""))
	if path == "" or not ResourceLoader.exists(path):
		return
	portrait.texture = load(path) as Texture2D


func _on_pilot_selected(ship: Dictionary) -> void:
	RaceSetup.select_pilot(ship)

	if RaceSetup.race_type == RaceSetup.RACE_TYPE_CHAMPIONSHIP:
		# Championships always start on the first available circuit.
		TrackSelection.select_track(TrackSelection.TRACKS[0]["scene"])
		TrackSelection.start_race(get_tree())
	else:
		get_tree().change_scene_to_file("res://scenes/CircuitMenu.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/TeamMenu.tscn")

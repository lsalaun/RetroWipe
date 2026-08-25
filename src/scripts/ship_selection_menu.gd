extends Control

## Populates a button per entry in ShipSelection.SHIPS and launches
## main.tscn with the chosen ship once pressed.

@onready var ship_list: VBoxContainer = $CenterContainer/VBoxContainer/ShipList


func _ready() -> void:
	for ship in ShipSelection.SHIPS:
		var button := Button.new()
		button.text = "%s (%s)" % [ship["pilot"], ship["team"]]
		button.pressed.connect(_on_ship_selected.bind(ship["mesh"]))
		ship_list.add_child(button)


func _on_ship_selected(mesh_path: String) -> void:
	ShipSelection.select_ship(mesh_path)
	get_tree().change_scene_to_file("res://scenes/main.tscn")

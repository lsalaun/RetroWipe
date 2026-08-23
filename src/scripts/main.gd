extends Node3D


func _ready() -> void:
	var center_line := $Track01/CenterLine as Path3D
	for child in get_children():
		if child is WipeoutShip:
			child.center_line = center_line

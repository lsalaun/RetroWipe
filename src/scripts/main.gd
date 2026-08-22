extends Node3D

const WipeoutShipAIScript := preload("res://scripts/wipeout_ship_ai.gd")


func _ready() -> void:
	var center_line := $Track01/CenterLine as Path3D
	for child in get_children():
		if child.get_script() == WipeoutShipAIScript:
			child.center_line = center_line

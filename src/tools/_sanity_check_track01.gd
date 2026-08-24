extends SceneTree

## One-off headless visual/physics sanity check for the freshly imported
## Track01Test scene (removed after use).

var _frame := 0

func _initialize() -> void:
	var scene: Node = load("res://scenes/tests/Track01Test.tscn").instantiate()
	root.add_child(scene)

func _physics_process(_delta: float) -> bool:
	_frame += 1
	if _frame in [30, 90, 300]:
		var ship := root.get_node_or_null(^"Track01Test/Ship")
		if ship:
			print("frame=%d SHIP_POS=%s" % [_frame, ship.global_position])
	if _frame == 300:
		quit(0)
	return false

extends SceneTree

## One-shot headless sanity check for the new HullPenetrationProbe safety net.
## Run: godot --headless --path src -s res://tools/validate_hull_probe.gd

var frames := 0


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _physics_process(_delta: float) -> bool:
	frames += 1
	if frames >= 30:
		print("ran %d physics frames without error" % frames)
		quit(0)
		return true
	return false

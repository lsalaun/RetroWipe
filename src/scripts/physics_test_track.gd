extends TrackMeshCollider
class_name PhysicsTestTrack

## Minimal standalone track (flat strip + bump + a wall segment) for exercising
## WipeoutShip phases 1-4 in isolation, without depending on Track01's Blender assets.

func _ready() -> void:
	super._ready()
	var ship := get_node_or_null(^"Ship")
	var center_line := get_node_or_null(^"CenterLine") as Path3D
	if ship and center_line:
		ship.center_line = center_line

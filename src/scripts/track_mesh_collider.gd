extends Node3D

class_name TrackMeshCollider


@export var track_mesh_path: NodePath = ^"TrackMesh"


func _ready() -> void:
	var track_mesh_root := get_node_or_null(track_mesh_path)
	if track_mesh_root == null:
		push_warning("TrackMeshCollider: missing track mesh node at %s" % track_mesh_path)
		return

	_ensure_colliders(track_mesh_root)


func _ensure_colliders(node: Node) -> void:
	if node is MeshInstance3D:
		_ensure_mesh_collider(node)
		_ensure_double_sided_material(node)

	for child in node.get_children():
		_ensure_colliders(child)


func _ensure_mesh_collider(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.mesh == null:
		return
	if mesh_instance.get_node_or_null(^"GeneratedCollisionBody") != null:
		return

	var shape := mesh_instance.mesh.create_trimesh_shape()
	if shape == null:
		return
	if shape is ConcavePolygonShape3D:
		shape.backface_collision = true

	var body := StaticBody3D.new()
	body.name = &"GeneratedCollisionBody"
	mesh_instance.add_child(body)

	var collider := CollisionShape3D.new()
	collider.name = &"GeneratedCollisionShape"
	collider.shape = shape
	body.add_child(collider)


## Track meshes exported from Blender are typically single-sided (only outward
## faces), so the default CULL_BACK renders thin walls as see-through holes
## when viewed from the inside of the track. Force double-sided rendering via
## a per-instance material override so the shared imported resource is untouched.
func _ensure_double_sided_material(mesh_instance: MeshInstance3D) -> void:
	var mesh := mesh_instance.mesh
	if mesh == null:
		return

	for i in range(mesh.get_surface_count()):
		var material := mesh_instance.get_surface_override_material(i)
		if material == null:
			material = mesh.surface_get_material(i)
		if not (material is BaseMaterial3D):
			continue
		if (material as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED:
			continue

		var doubled: BaseMaterial3D = material.duplicate()
		doubled.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_instance.set_surface_override_material(i, doubled)
extends Node3D

## Wraps a track's SKY.PRM dome around the camera, the way scene.c does.
##
## The dome is a small closed mesh -- ~366 m across and 240 m tall for TRACK01 --
## that the original re-centres on the camera every frame before drawing it, so
## it reads as an infinitely distant backdrop. Instanced as a plain GLB it
## instead sits at the track origin: the ship drives out of it and its faces cut
## through the scenery, which is the "sky buried in the hills" artefact.
##
## Drawing order and occlusion are handled by track_sky.gdshader; this script
## owns the per-frame re-centring and swapping the imported lit materials for it.

const SKY_SHADER: Shader = preload("res://shaders/track_sky.gdshader")

## Height of the dome above the camera, in metres.
##
## Ported from the per-circuit `sky_y_offset` of game.c's def.circuits, which is
## in raw PSX units with Y pointing down -- so the value set here is the C one
## negated and divided by the importer's 106.5 units per metre.
@export var sky_y_offset: float = 0.0


func _ready() -> void:
	# AttractCamera moves itself in _process(), so the dome has to re-centre
	# after it; otherwise the backdrop trails the camera by a frame and swims.
	process_priority = 1000
	# The dummy renderer has no shader compiler, so handing it a ShaderMaterial
	# makes it log "Parameter \"material\" is null" on every headless run
	# (tools/validate_*.gd). Nothing is drawn there anyway.
	if DisplayServer.get_name() == "headless":
		return
	for mesh_instance in find_children("*", "MeshInstance3D", true, false):
		_apply_backdrop_material(mesh_instance)


func _process(_delta: float) -> void:
	# Re-read the camera each frame rather than caching it: the race cuts between
	# the player's CameraRig and AttractCamera without reloading the track.
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	global_position = camera.global_position + Vector3(0.0, sky_y_offset, 0.0)


func _apply_backdrop_material(mesh_instance: MeshInstance3D) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	# A backdrop can neither cast nor catch a shadow. Left as imported, the dome
	# casts one from the Sun over the whole track.
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for surface in mesh.get_surface_count():
		var imported := mesh.surface_get_material(surface) as BaseMaterial3D
		var backdrop := ShaderMaterial.new()
		backdrop.shader = SKY_SHADER
		if imported != null:
			backdrop.set_shader_parameter("albedo_texture", imported.albedo_texture)
		mesh_instance.set_surface_override_material(surface, backdrop)

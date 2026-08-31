extends SubViewport
class_name MenuModelPreview

## Off-screen turntable for a menu's Object* model (main_menu.c's draw_model()):
## renders one glTF-imported COMMON PRM mesh (LEEG/TEAMS/PILOT/ALOPT/PAD1/MSDOS/
## RESCU) into a small transparent render target that a WipeoutMenu page blits
## with draw_texture_rect() from its draw_func, in place of the original's
## direct 3D draw call mixed into the 2D menu pass.
##
## draw_model() spins the model at `rotation == system_cycle_time()`, i.e. one
## radian per second of run time; ROTATION_SPEED mirrors that.

const PREVIEW_SIZE := 128
const MAX_RENDER_SIZE := 2048
const ROTATION_SPEED := 1.0
const FOV_DEGREES := 20.0
const FIT_MARGIN := 1.35

var _pivot: Node3D
var _camera: Camera3D
var _current_model: Node3D
var _current_path := ""


## Adds a preview viewport as a child of `root` (a menu Control) and returns it.
static func attach(root: Node) -> MenuModelPreview:
	var preview := MenuModelPreview.new()
	root.add_child(preview)
	return preview


func _init() -> void:
	size = Vector2i(PREVIEW_SIZE, PREVIEW_SIZE)
	transparent_bg = true
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Smooths the model silhouette, which a 1:1 blit would otherwise show raw.
	msaa_3d = Viewport.MSAA_4X

	_camera = Camera3D.new()
	_camera.fov = FOV_DEGREES
	add_child(_camera)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.2
	key.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0.0)
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.5
	fill.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(-150.0), 0.0)
	add_child(fill)

	_pivot = Node3D.new()
	add_child(_pivot)


func _process(delta: float) -> void:
	if _current_model != null:
		_pivot.rotation.y = wrapf(_pivot.rotation.y + delta * ROTATION_SPEED, 0.0, TAU)


## Swaps the previewed model. No-op if `path` ("" clears it) is already showing.
func show_model(path: String) -> void:
	if path == _current_path:
		return
	_current_path = path
	if _current_model != null:
		_current_model.queue_free()
		_current_model = null
	if path == "" or not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	_current_model = scene.instantiate() as Node3D
	if _current_model == null:
		return
	_pivot.add_child(_current_model)
	_frame_camera(_current_model)


## Resizes the render target to the on-screen size the menu blits it at, so the
## frame is sampled 1:1. The fixed 128x128 target used to be magnified ~6x by
## draw_texture_rect() under the project's nearest canvas filter, which is what
## made the spinning ship look blocky -- not the PSX textures themselves.
## Camera framing is resolution-independent, so only the sampling changes.
func set_render_size(pixels: Vector2i) -> void:
	var wanted := Vector2i(
		clampi(pixels.x, PREVIEW_SIZE, MAX_RENDER_SIZE),
		clampi(pixels.y, PREVIEW_SIZE, MAX_RENDER_SIZE)
	)
	if wanted != size:
		size = wanted


func _frame_camera(model: Node3D) -> void:
	var box := _combined_aabb(model)
	var radius := 1.0
	if box.size != Vector3.ZERO:
		model.position -= box.get_center()
		radius = box.size.length() * 0.5
	var half_fov := deg_to_rad(_camera.fov * 0.5)
	var distance := (radius * FIT_MARGIN) / sin(half_fov)
	_camera.position = Vector3(0.0, 0.0, distance)
	_camera.near = maxf(0.01, distance - radius * 4.0)
	_camera.far = distance + radius * 4.0


func _combined_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for instance in _visual_instances(node):
		var box: AABB = instance.global_transform * instance.get_aabb()
		if not found:
			result = box
			found = true
		else:
			result = result.merge(box)
	return result


func _visual_instances(node: Node) -> Array:
	var found: Array = []
	if node is VisualInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_visual_instances(child))
	return found

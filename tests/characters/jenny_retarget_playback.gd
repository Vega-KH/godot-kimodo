extends Node3D

const Baker := preload(
	"res://addons/kimodo_motion/retargeting/humanoid_character_baker.gd"
)
const SOURCE_SCENE := preload(
	"res://tests/retargeting/generated/soma77_walk_humanoid.tscn"
)
const JENNY_SCENE := preload("res://tests/characters/fixtures/Jenny03.glb")

const DEFAULT_YAW := 0.0
const DEFAULT_PITCH := 0.08
const DEFAULT_DISTANCE := 5.0

var _source_skeleton: Skeleton3D
var _source_player: AnimationPlayer
var _character_skeleton: Skeleton3D
var _character_player: AnimationPlayer
var _lines: MeshInstance3D
var _camera: Camera3D
var _yaw := DEFAULT_YAW
var _pitch := DEFAULT_PITCH
var _distance := DEFAULT_DISTANCE
var _orbiting := false
var _follow_root := true
var _capture_directory := ""
var _capture_frame := 0


func _ready() -> void:
	_capture_directory = _argument_value("--capture-dir")
	var source_scene := _scene_argument("--source-scene", SOURCE_SCENE)
	var source := source_scene.instantiate() as Node3D
	source.position.x = -0.85
	add_child(source)
	_source_skeleton = _find_first(source, "Skeleton3D") as Skeleton3D
	_source_player = _find_first(source, "AnimationPlayer") as AnimationPlayer
	_source_player.play("motion")

	var character := JENNY_SCENE.instantiate() as Node3D
	character.position.x = 0.85
	add_child(character)
	var motion: RefCounted = Baker.create_motion(source, character)
	_character_skeleton = motion.skeleton
	_character_player = motion.player
	if not _capture_directory.is_empty():
		_source_player.pause()
		_character_player.pause()

	_lines = MeshInstance3D.new()
	_lines.name = "HumanoidLines"
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	_lines.material_override = line_material
	add_child(_lines)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(12.0, 12.0)
	var floor1 := MeshInstance3D.new()
	floor1.name = "Floor"
	floor1.mesh = floor_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.12, 0.13, 0.16)
	floor1.material_override = floor_material
	add_child(floor1)

	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.045, 0.055, 0.075)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	add_child(environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)

	_camera = Camera3D.new()
	_camera.fov = 48.0
	add_child(_camera)
	_update_camera()

	var label := Label.new()
	label.text = "Jenny retarget · Drag: orbit · Wheel: zoom · F: follow root · R: reset"
	label.position = Vector2(16.0, 14.0)
	label.add_theme_font_size_override("font_size", 16)
	var layer := CanvasLayer.new()
	layer.add_child(label)
	add_child(layer)


func _process(_delta: float) -> void:
	_draw_source()
	_update_camera()
	_capture_frame_if_requested()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_orbiting = button.pressed
		elif button.pressed and button.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN
		]:
			_distance = clampf(
				_distance * (0.9 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1),
				2.0,
				12.0,
			)
	elif event is InputEventMouseMotion and _orbiting:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * 0.01
		_pitch = clampf(_pitch - motion.relative.y * 0.01, -1.1, 1.1)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			_follow_root = not _follow_root
		elif event.keycode == KEY_R:
			_yaw = DEFAULT_YAW
			_pitch = DEFAULT_PITCH
			_distance = DEFAULT_DISTANCE


func _draw_source() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for bone_index in _source_skeleton.get_bone_count():
		var parent_index := _source_skeleton.get_bone_parent(bone_index)
		if parent_index < 0:
			continue
		mesh.surface_set_color(Color(0.1, 0.85, 1.0))
		mesh.surface_add_vertex(
			_lines.to_local(
				_source_skeleton.to_global(
					_source_skeleton.get_bone_global_pose(parent_index).origin
				)
			)
		)
		mesh.surface_add_vertex(
			_lines.to_local(
				_source_skeleton.to_global(
					_source_skeleton.get_bone_global_pose(bone_index).origin
				)
			)
		)
	mesh.surface_end()
	_lines.mesh = mesh


func _update_camera() -> void:
	if _camera == null:
		return
	var target := Vector3(0.0, 1.0, 0.0)
	if _follow_root and _character_skeleton != null:
		var root_index := _character_skeleton.find_bone("Root")
		var root_world := _character_skeleton.to_global(
			_character_skeleton.get_bone_global_pose(root_index).origin
		)
		target.x = root_world.x - 0.85
		target.z = root_world.z
	var horizontal := cos(_pitch)
	var offset := Vector3(
		sin(_yaw) * horizontal,
		sin(_pitch),
		cos(_yaw) * horizontal,
	) * _distance
	_camera.look_at_from_position(target + offset, target)


func _capture_frame_if_requested() -> void:
	if _capture_directory.is_empty():
		return
	_capture_frame += 1
	var animation_length := _source_player.get_animation("motion").length
	var samples := {
		1: [0.0, 0.0, "jenny_front_start.png"],
		10: [animation_length * 0.5, 0.0, "jenny_front_mid.png"],
		19: [animation_length, 0.0, "jenny_front_end.png"],
		28: [animation_length * 0.5, PI / 2.0, "jenny_side_mid.png"],
	}
	if samples.has(_capture_frame):
		var sample: Array = samples[_capture_frame]
		_source_player.seek(sample[0], true)
		_character_player.seek(sample[0], true)
		_source_skeleton.force_update_all_bone_transforms()
		_character_skeleton.force_update_all_bone_transforms()
		_yaw = sample[1]
	# Allow two rendered frames after a seek/camera change so the viewport
	# texture and the line mesh represent the exact same paused sample.
	if samples.has(_capture_frame - 2):
		var sample: Array = samples[_capture_frame - 2]
		var image := get_viewport().get_texture().get_image()
		if image.save_png(_capture_directory.path_join(sample[2])) != OK:
			push_error("Could not save Jenny comparison frame")
	if _capture_frame >= 31:
		get_tree().quit()


func _argument_value(flag: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in arguments.size():
		if arguments[index] == flag and index + 1 < arguments.size():
			return arguments[index + 1]
	return ""


func _scene_argument(flag: String, fallback: PackedScene) -> PackedScene:
	var path := _argument_value(flag)
	if path.is_empty():
		return fallback
	return ResourceLoader.load(
		path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene


func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null

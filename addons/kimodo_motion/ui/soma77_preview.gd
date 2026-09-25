@tool
class_name Soma77Preview
extends SubViewportContainer

signal camera_view_changed(yaw: float, pitch: float, distance: float)

const DEFAULT_CAMERA_YAW := 0.588003
const DEFAULT_CAMERA_PITCH := 0.107385
const DEFAULT_CAMERA_DISTANCE := 3.263817
const CAMERA_TARGET_HEIGHT := 1.0
const MIN_CAMERA_DISTANCE := 1.25
const MAX_CAMERA_DISTANCE := 12.0
const MIN_CAMERA_PITCH := -1.2
const MAX_CAMERA_PITCH := 1.2

var _viewport: SubViewport
var _world_root: Node3D
var _camera: Camera3D
var _motion_scene: Node
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _lines: MeshInstance3D
var _animation_name: StringName
var _follow_bone_index := -1
var _looping := true
var _preview_name := "MotionPreview"
var _line_color := Color(0.25, 0.95, 0.65)
var _show_skeleton_lines := true
var _camera_yaw := DEFAULT_CAMERA_YAW
var _camera_pitch := DEFAULT_CAMERA_PITCH
var _camera_distance := DEFAULT_CAMERA_DISTANCE
var _camera_target := Vector3(0.0, CAMERA_TARGET_HEIGHT, 0.0)
var _follow_root := true
var _orbiting := false


func configure(
	preview_name: String,
	line_color: Color,
	show_skeleton_lines: bool = true,
) -> void:
	_preview_name = preview_name
	_line_color = line_color
	_show_skeleton_lines = show_skeleton_lines
	name = _preview_name
	if _lines != null:
		(_lines.material_override as StandardMaterial3D).albedo_color = _line_color


func _ready() -> void:
	name = _preview_name
	custom_minimum_size = Vector2(320.0, 250.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Left-drag to orbit. Use the mouse wheel to zoom."
	_build_viewport()
	set_process(true)


func set_motion(motion: RefCounted) -> bool:
	clear_motion()
	if motion == null or not is_instance_valid(motion.scene):
		return false
	_motion_scene = motion.scene
	motion.scene = null
	_world_root.add_child(_motion_scene)
	_skeleton = _find_first(_motion_scene, "Skeleton3D") as Skeleton3D
	_player = _find_first(_motion_scene, "AnimationPlayer") as AnimationPlayer
	_animation_name = motion.animation_name
	if _skeleton == null or _player == null or not _player.has_animation(_animation_name):
		clear_motion()
		return false
	_follow_bone_index = _skeleton.find_bone("Root")
	if _follow_bone_index < 0:
		_follow_bone_index = _skeleton.find_bone("Hips")
	_apply_looping()
	_player.play(_animation_name)
	return true


func clear_motion() -> void:
	_skeleton = null
	_player = null
	_animation_name = &""
	_follow_bone_index = -1
	if _motion_scene != null and is_instance_valid(_motion_scene):
		_motion_scene.free()
	_motion_scene = null
	if _lines != null:
		_lines.mesh = null


func release_motion_scene() -> Node:
	var released := _motion_scene
	if released != null and is_instance_valid(released) and released.get_parent() == _world_root:
		_world_root.remove_child(released)
	_motion_scene = null
	_skeleton = null
	_player = null
	_animation_name = &""
	_follow_bone_index = -1
	if _lines != null:
		_lines.mesh = null
	return released


func set_playing(playing: bool) -> void:
	if _player == null:
		return
	if playing:
		_player.play(_animation_name)
	else:
		_player.pause()


func is_playing() -> bool:
	return _player != null and _player.is_playing()


func set_looping(looping: bool) -> void:
	_looping = looping
	_apply_looping()


func has_motion() -> bool:
	return _motion_scene != null


func motion_scene() -> Node:
	return _motion_scene


func skeleton() -> Skeleton3D:
	return _skeleton


func animation_player() -> AnimationPlayer:
	return _player


func seek(time: float) -> void:
	if _player == null:
		return
	_player.seek(clampf(time, 0.0, animation_length()), true)


func current_position() -> float:
	return _player.current_animation_position if _player != null else 0.0


func animation_length() -> float:
	if _player == null or not _player.has_animation(_animation_name):
		return 0.0
	return _player.get_animation(_animation_name).length


func set_camera_follow_root(enabled: bool) -> void:
	_follow_root = enabled
	if not enabled:
		_camera_target = Vector3(0.0, CAMERA_TARGET_HEIGHT, 0.0)
	_update_camera()


func camera_follows_root() -> bool:
	return _follow_root


func set_camera_view(yaw: float, pitch: float, distance: float) -> void:
	_camera_yaw = yaw
	_camera_pitch = clampf(pitch, MIN_CAMERA_PITCH, MAX_CAMERA_PITCH)
	_camera_distance = clampf(distance, MIN_CAMERA_DISTANCE, MAX_CAMERA_DISTANCE)
	_update_camera()


func reset_camera_view() -> void:
	set_camera_view(DEFAULT_CAMERA_YAW, DEFAULT_CAMERA_PITCH, DEFAULT_CAMERA_DISTANCE)


func camera_view() -> Dictionary:
	return {
		"yaw": _camera_yaw,
		"pitch": _camera_pitch,
		"distance": _camera_distance,
	}


func camera_target() -> Vector3:
	return _camera_target


func camera_position() -> Vector3:
	return _camera.position if _camera != null else Vector3.ZERO


func _exit_tree() -> void:
	clear_motion()


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	_viewport.size = Vector2i(320, 250)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true
	add_child(_viewport)

	_world_root = Node3D.new()
	_world_root.name = "PreviewWorld"
	_viewport.add_child(_world_root)

	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.055, 0.065, 0.085)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	_world_root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.name = "PreviewLight"
	light.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	light.light_energy = 1.2
	_world_root.add_child(light)

	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.fov = 60.0
	_world_root.add_child(_camera)
	_update_camera()

	_lines = MeshInstance3D.new()
	_lines.name = "AnimatedSkeletonLines"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = _line_color
	material.vertex_color_use_as_albedo = true
	_lines.material_override = material
	_world_root.add_child(_lines)


func _process(_delta: float) -> void:
	_update_follow_target()
	_update_camera()
	if _skeleton == null or _lines == null or not _show_skeleton_lines:
		if _lines != null and not _show_skeleton_lines:
			_lines.mesh = null
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for bone_index in _skeleton.get_bone_count():
		var parent_index := _skeleton.get_bone_parent(bone_index)
		if parent_index < 0:
			continue
		var child_position := _lines.to_local(
			_skeleton.to_global(_skeleton.get_bone_global_pose(bone_index).origin)
		)
		var parent_position := _lines.to_local(
			_skeleton.to_global(_skeleton.get_bone_global_pose(parent_index).origin)
		)
		mesh.surface_set_color(_line_color)
		mesh.surface_add_vertex(parent_position)
		mesh.surface_add_vertex(child_position)
	mesh.surface_end()
	_lines.mesh = mesh


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_orbiting = button.pressed
			accept_event()
		elif button.pressed and button.button_index in [
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN
		]:
			var factor := 0.9 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1
			_camera_distance = clampf(
				_camera_distance * factor, MIN_CAMERA_DISTANCE, MAX_CAMERA_DISTANCE
			)
			_update_camera()
			camera_view_changed.emit(_camera_yaw, _camera_pitch, _camera_distance)
			accept_event()
	elif event is InputEventMouseMotion and _orbiting:
		var motion := event as InputEventMouseMotion
		_camera_yaw -= motion.relative.x * 0.01
		_camera_pitch = clampf(
			_camera_pitch - motion.relative.y * 0.01,
			MIN_CAMERA_PITCH,
			MAX_CAMERA_PITCH,
		)
		_update_camera()
		camera_view_changed.emit(_camera_yaw, _camera_pitch, _camera_distance)
		accept_event()


func _update_follow_target() -> void:
	if not _follow_root or _skeleton == null or _follow_bone_index < 0:
		return
	var root_world := _world_root.to_local(
		_skeleton.to_global(_skeleton.get_bone_global_pose(_follow_bone_index).origin)
	)
	_camera_target = Vector3(root_world.x, CAMERA_TARGET_HEIGHT, root_world.z)


func _update_camera() -> void:
	if _camera == null:
		return
	var horizontal := cos(_camera_pitch)
	var offset := Vector3(
		sin(_camera_yaw) * horizontal,
		sin(_camera_pitch),
		cos(_camera_yaw) * horizontal,
	) * _camera_distance
	_camera.look_at_from_position(_camera_target + offset, _camera_target)


func _apply_looping() -> void:
	if _player == null or not _player.has_animation(_animation_name):
		return
	var animation := _player.get_animation(_animation_name)
	animation.loop_mode = Animation.LOOP_LINEAR if _looping else Animation.LOOP_NONE


func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null

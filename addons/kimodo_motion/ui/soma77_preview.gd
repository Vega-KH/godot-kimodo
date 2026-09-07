@tool
class_name Soma77Preview
extends SubViewportContainer

var _viewport: SubViewport
var _world_root: Node3D
var _motion_scene: Node
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _lines: MeshInstance3D
var _animation_name: StringName
var _looping := true


func _ready() -> void:
	name = "MotionPreview"
	custom_minimum_size = Vector2(320.0, 250.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch = true
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
	_apply_looping()
	_player.play(_animation_name)
	return true


func clear_motion() -> void:
	_skeleton = null
	_player = null
	_animation_name = &""
	if _motion_scene != null and is_instance_valid(_motion_scene):
		_motion_scene.free()
	_motion_scene = null
	if _lines != null:
		_lines.mesh = null


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

	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.position = Vector3(1.8, 1.35, 2.7)
	camera.fov = 60.0
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.0, 0.0))
	_world_root.add_child(camera)

	_lines = MeshInstance3D.new()
	_lines.name = "AnimatedSkeletonLines"
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.25, 0.95, 0.65)
	material.vertex_color_use_as_albedo = true
	_lines.material_override = material
	_world_root.add_child(_lines)


func _process(_delta: float) -> void:
	if _skeleton == null or _lines == null:
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
		mesh.surface_set_color(Color(0.25, 0.95, 0.65))
		mesh.surface_add_vertex(parent_position)
		mesh.surface_add_vertex(child_position)
	mesh.surface_end()
	_lines.mesh = mesh


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

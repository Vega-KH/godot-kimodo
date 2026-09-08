extends Node3D

const SOURCE_SCENE := preload("res://tests/native/generated/soma77_walk.tscn")
const TARGET_SCENE := preload(
	"res://tests/retargeting/generated/soma77_walk_humanoid.tscn"
)

var _rigs: Array[Dictionary] = []
var _capture_directory := ""
var _capture_frame := 0


func _ready() -> void:
	_capture_directory = _argument_value("--capture-dir")
	_add_rig(SOURCE_SCENE.instantiate(), Vector3(-0.9, 0.0, 0.0), Color(0.1, 0.85, 1.0))
	_add_rig(TARGET_SCENE.instantiate(), Vector3(0.9, 0.0, 0.0), Color(1.0, 0.35, 0.8))

	var camera := Camera3D.new()
	camera.position = Vector3(3.1, 1.45, 4.8)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.05, 0.0))
	add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -25.0, 0.0)
	add_child(light)


func _process(_delta: float) -> void:
	for rig in _rigs:
		_draw_skeleton(rig["skeleton"], rig["lines"], rig["color"])
	if _capture_directory.is_empty():
		return
	_capture_frame += 1
	if _capture_frame in [1, 7, 13]:
		var sample_times := {1: 0.0, 7: 0.5, 13: 29.0 / 30.0}
		for rig in _rigs:
			(rig["player"] as AnimationPlayer).seek(sample_times[_capture_frame], true)
	if _capture_frame in [2, 8, 14]:
		var image := get_viewport().get_texture().get_image()
		var path := _capture_directory.path_join("retarget_%02d.png" % _capture_frame)
		if image.save_png(path) != OK:
			push_error("Could not save retarget comparison frame %d" % _capture_frame)
	if _capture_frame >= 15:
		get_tree().quit()


func _add_rig(instance: Node, offset: Vector3, color: Color) -> void:
	add_child(instance)
	(instance as Node3D).position = offset
	var skeleton := _find_first(instance, "Skeleton3D") as Skeleton3D
	var player := _find_first(instance, "AnimationPlayer") as AnimationPlayer
	if skeleton == null or player == null:
		push_error("Retarget comparison rig is incomplete")
		return
	var lines := MeshInstance3D.new()
	lines.name = "SkeletonLines"
	add_child(lines)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	lines.material_override = material
	var animation := player.get_animation("motion")
	animation.loop_mode = Animation.LOOP_LINEAR
	player.play("motion")
	_rigs.append({"skeleton": skeleton, "lines": lines, "color": color, "player": player})


func _draw_skeleton(skeleton: Skeleton3D, lines: MeshInstance3D, color: Color) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for bone_index in skeleton.get_bone_count():
		var parent_index := skeleton.get_bone_parent(bone_index)
		if parent_index < 0:
			continue
		var child_position := lines.to_local(
			skeleton.to_global(skeleton.get_bone_global_pose(bone_index).origin)
		)
		var parent_position := lines.to_local(
			skeleton.to_global(skeleton.get_bone_global_pose(parent_index).origin)
		)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(parent_position)
		mesh.surface_add_vertex(child_position)
	mesh.surface_end()
	lines.mesh = mesh


func _argument_value(flag: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	for index in arguments.size():
		if arguments[index] == flag and index + 1 < arguments.size():
			return arguments[index + 1]
	return ""


func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null

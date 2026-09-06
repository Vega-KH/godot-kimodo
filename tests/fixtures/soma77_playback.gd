extends Node3D

const FIXTURE_PATH := "res://tests/fixtures/soma77_mmcp_1_0.gltf"
const GltfLoader := preload("res://addons/kimodo_motion/transport/mmcp_gltf_loader.gd")

var _skeleton: Skeleton3D
var _lines: MeshInstance3D


func _ready() -> void:
	var data := FileAccess.get_file_as_bytes(FIXTURE_PATH)
	var imported: Node = GltfLoader.load_from_buffer(data)
	if imported == null:
		return
	add_child(imported)
	_skeleton = _find_first(imported, "Skeleton3D") as Skeleton3D
	var player := _find_first(imported, "AnimationPlayer") as AnimationPlayer
	if _skeleton == null or player == null:
		push_error("SOMA-77 fixture did not create a skeleton and animation player")
		return

	_lines = MeshInstance3D.new()
	_lines.name = "AnimatedSkeletonLines"
	add_child(_lines)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 0.85, 1.0)
	material.vertex_color_use_as_albedo = true
	_lines.material_override = material

	var camera := Camera3D.new()
	camera.position = Vector3(2.4, 1.4, 3.2)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.0, 0.0))
	add_child(camera)

	var animation_names := player.get_animation_list()
	if not animation_names.is_empty():
		player.get_animation(animation_names[0]).loop_mode = Animation.LOOP_LINEAR
		player.play(animation_names[0])


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
		mesh.surface_set_color(Color(0.2, 0.85, 1.0))
		mesh.surface_add_vertex(parent_position)
		mesh.surface_add_vertex(child_position)
	mesh.surface_end()
	_lines.mesh = mesh


func _find_first(root: Node, type_name: StringName) -> Node:
	if root.is_class(type_name):
		return root
	for child in root.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null

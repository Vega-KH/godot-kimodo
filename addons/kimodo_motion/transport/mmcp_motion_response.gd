class_name MmcpMotionResponse
extends RefCounted

const Contract := preload("res://addons/kimodo_motion/domain/soma77_contract.gd")
const GltfLoader := preload("res://addons/kimodo_motion/transport/mmcp_gltf_loader.gd")

class ParsedMotion extends RefCounted:
	var scene: Node
	var animation_name: StringName
	var duration_seconds: float
	var source_rotation_channels: int
	var source_translation_channels: int


static func parse(
	data: PackedByteArray,
	expected_frames: int,
	expected_fps: float,
	expected_skeleton: Dictionary = {},
) -> Dictionary:
	var parser := JSON.new()
	var json_error := parser.parse(data.get_string_from_utf8())
	if json_error != OK or not parser.data is Dictionary:
		return _error("invalid_gltf", "The server returned invalid glTF JSON.")
	var document: Dictionary = parser.data
	var source_result := _validate_source(document, expected_skeleton)
	if not source_result["ok"]:
		return source_result

	var state := GltfLoader.parse_from_buffer(data, "res://", false)
	if state == null:
		return _error("invalid_gltf", "Godot could not decode the generated glTF.")
	var scene := GLTFDocument.new().generate_scene(state)
	if scene == null:
		return _error("invalid_gltf", "Godot could not create the generated motion scene.")
	var skeleton := _find_first(scene, "Skeleton3D") as Skeleton3D
	var player := _find_first(scene, "AnimationPlayer") as AnimationPlayer
	if skeleton == null or player == null:
		scene.free()
		return _error("invalid_motion", "The generated glTF has no skeleton animation.")
	if not _validate_skeleton(skeleton, expected_skeleton):
		scene.free()
		return _error("invalid_motion", "The generated skeleton is not canonical SOMA-77.")
	var names := player.get_animation_list()
	if names.size() != 1:
		scene.free()
		return _error("invalid_motion", "Expected exactly one generated animation.")
	var animation := player.get_animation(names[0])
	var expected_duration := float(expected_frames - 1) / expected_fps
	if animation == null or not is_equal_approx(animation.length, expected_duration):
		scene.free()
		return _error(
			"invalid_motion",
			"The generated animation duration does not match the request.",
		)
	for track in animation.get_track_count():
		var type := animation.track_get_type(track)
		for time in [0.0, animation.length * 0.5, animation.length]:
			var sample: Variant = null
			if type == Animation.TYPE_ROTATION_3D:
				sample = animation.rotation_track_interpolate(track, time)
			elif type == Animation.TYPE_POSITION_3D:
				sample = animation.position_track_interpolate(track, time)
			if sample is Quaternion and not sample.is_finite():
				scene.free()
				return _error("invalid_motion", "The generated motion contains non-finite rotations.")
			if sample is Vector3 and not sample.is_finite():
				scene.free()
				return _error("invalid_motion", "The generated motion contains non-finite positions.")

	var motion := ParsedMotion.new()
	motion.scene = scene
	motion.animation_name = names[0]
	motion.duration_seconds = animation.length
	motion.source_rotation_channels = source_result["rotation_channels"]
	motion.source_translation_channels = source_result["translation_channels"]
	return {"ok": true, "motion": motion}


static func _validate_source(document: Dictionary, expected_skeleton: Dictionary) -> Dictionary:
	var asset: Variant = document.get("asset")
	if not asset is Dictionary or not String(asset.get("version", "")).begins_with("2"):
		return _error("invalid_gltf", "The response is not glTF 2.0.")
	var nodes: Variant = document.get("nodes")
	if not nodes is Array or nodes.size() != Contract.JOINT_NAMES.size():
		return _error("invalid_motion", "The response does not contain 77 SOMA joints.")
	var names: Array[String] = []
	for node in nodes:
		if not node is Dictionary or not node.get("name") is String:
			return _error("invalid_motion", "A generated skeleton node is unnamed.")
		names.append(node["name"])
	if names != Contract.JOINT_NAMES:
		return _error("invalid_motion", "Generated joints are not in canonical SOMA-77 order.")
	if not expected_skeleton.is_empty():
		var hierarchy_result := _validate_source_hierarchy(nodes, names, expected_skeleton)
		if not hierarchy_result["ok"]:
			return hierarchy_result
	var animations: Variant = document.get("animations")
	if not animations is Array or animations.size() != 1:
		return _error("invalid_motion", "Expected one glTF animation.")
	var channels: Variant = animations[0].get("channels")
	if not channels is Array:
		return _error("invalid_motion", "The glTF animation has no channels.")
	var rotations := 0
	var translations := 0
	var rotated_nodes: Dictionary = {}
	for channel in channels:
		if not channel is Dictionary or not channel.get("target") is Dictionary:
			return _error("invalid_motion", "A glTF animation channel is malformed.")
		var target: Dictionary = channel["target"]
		var node_index: Variant = target.get("node")
		if not node_index is int and not node_index is float:
			return _error("invalid_motion", "A glTF animation channel targets an invalid node.")
		var node_number := int(node_index)
		if float(node_number) != float(node_index) or node_number < 0 or node_number >= nodes.size():
			return _error("invalid_motion", "A glTF animation channel targets an invalid node.")
		if target.get("path") == "rotation":
			rotations += 1
			rotated_nodes[node_number] = true
		elif target.get("path") == "translation":
			translations += 1
			if node_number != 0:
				return _error("invalid_motion", "Only the SOMA root may have translation motion.")
	if rotations != 77 or rotated_nodes.size() != 77 or translations != 1:
		return _error(
			"invalid_motion",
			"Expected 77 rotation channels and one root translation channel.",
		)
	return {"ok": true, "rotation_channels": rotations, "translation_channels": translations}


static func _validate_source_hierarchy(
	nodes: Array, names: Array[String], expected_skeleton: Dictionary
) -> Dictionary:
	var expected_joints: Variant = expected_skeleton.get("joints")
	if not expected_joints is Array or expected_joints.size() != nodes.size():
		return _error("invalid_motion", "The negotiated skeleton hierarchy is unavailable.")
	var parent_names: Array = []
	parent_names.resize(nodes.size())
	for parent_index in nodes.size():
		var children: Variant = nodes[parent_index].get("children", [])
		if not children is Array:
			return _error("invalid_motion", "A generated skeleton child list is malformed.")
		for child_value in children:
			if not child_value is int and not child_value is float:
				return _error("invalid_motion", "A generated skeleton child index is invalid.")
			var child_index := int(child_value)
			if (
				float(child_index) != float(child_value)
				or child_index < 0
				or child_index >= nodes.size()
				or parent_names[child_index] != null
			):
				return _error("invalid_motion", "The generated skeleton hierarchy is invalid.")
			parent_names[child_index] = names[parent_index]
	for index in nodes.size():
		if parent_names[index] != expected_joints[index].get("parent"):
			return _error("invalid_motion", "Generated joint hierarchy differs from negotiated SOMA-77.")
	return {"ok": true}


static func _validate_skeleton(skeleton: Skeleton3D, expected_skeleton: Dictionary) -> bool:
	if skeleton.get_bone_count() != Contract.JOINT_NAMES.size():
		return false
	for index in skeleton.get_bone_count():
		if skeleton.get_bone_name(index) != Contract.JOINT_NAMES[index]:
			return false
		var parent_index := skeleton.get_bone_parent(index)
		if index > 0 and parent_index >= index:
			return false
		if not expected_skeleton.is_empty():
			var expected_parent: Variant = expected_skeleton["joints"][index].get("parent")
			var actual_parent: Variant = null
			if parent_index >= 0:
				actual_parent = skeleton.get_bone_name(parent_index)
			if actual_parent != expected_parent:
				return false
		if not skeleton.get_bone_rest(index).is_finite():
			return false
	return true


static func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null


static func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}

class_name MmcpMotionResponse
extends RefCounted

const Contract := preload("res://addons/kimodo_motion/domain/soma77_contract.gd")
const GltfLoader := preload("res://addons/kimodo_motion/transport/mmcp_gltf_loader.gd")

class ParsedMotion extends RefCounted:
	var scene: Node
	var animation_name: StringName
	var sample_index: int
	var content_sha256: String
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
	var source_result := _validate_source(document, expected_skeleton, expected_frames, expected_fps)
	if not source_result["ok"]:
		return source_result

	var motions: Array[RefCounted] = []
	var animation_names: Array = source_result["animation_names"]
	for sample_index in animation_names.size():
		var state := GltfLoader.parse_from_buffer(data, "res://", false)
		if state == null:
			_free_motions(motions)
			return _error("invalid_gltf", "Godot could not decode the generated glTF.")
		var scene := GLTFDocument.new().generate_scene(state)
		if scene == null:
			_free_motions(motions)
			return _error("invalid_gltf", "Godot could not create the generated motion scene.")
		var skeleton := _find_first(scene, "Skeleton3D") as Skeleton3D
		var player := _find_first(scene, "AnimationPlayer") as AnimationPlayer
		var animation_name := StringName(animation_names[sample_index])
		if skeleton == null or player == null or not player.has_animation(animation_name):
			scene.free()
			_free_motions(motions)
			return _error("invalid_motion", "The generated glTF is missing a declared take.")
		if not _validate_skeleton(skeleton, expected_skeleton):
			scene.free()
			_free_motions(motions)
			return _error("invalid_motion", "The generated skeleton is not canonical SOMA-77.")
		var animation := player.get_animation(animation_name)
		var expected_duration := float(expected_frames - 1) / expected_fps
		if animation == null or not is_equal_approx(animation.length, expected_duration):
			scene.free()
			_free_motions(motions)
			return _error("invalid_motion", "A generated take duration does not match the request.")
		var finite_error := _validate_animation_values(animation)
		if not finite_error.is_empty():
			scene.free()
			_free_motions(motions)
			return _error("invalid_motion", finite_error)
		var motion := ParsedMotion.new()
		motion.scene = scene
		motion.animation_name = animation_name
		motion.sample_index = sample_index
		motion.content_sha256 = _hash_animation(animation)
		motion.duration_seconds = animation.length
		motion.source_rotation_channels = source_result["rotation_channels"]
		motion.source_translation_channels = source_result["translation_channels"]
		_keep_only_animation(player, animation_name)
		motions.append(motion)
	return {"ok": true, "motions": motions, "motion": motions[0]}


static func _validate_source(
	document: Dictionary,
	expected_skeleton: Dictionary,
	expected_frames: int,
	expected_fps: float,
) -> Dictionary:
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
	if not animations is Array or animations.is_empty():
		return _error("invalid_motion", "Expected at least one glTF animation.")
	var extension: Variant = document.get("extensions", {}).get("MMCP_motion")
	var samples: Variant = extension.get("samples") if extension is Dictionary else null
	if not extension is Dictionary or not is_equal_approx(float(extension.get("fps", 0.0)), expected_fps):
		return _error("invalid_motion", "Take metadata frame rate does not match the request.")
	if not samples is Array or samples.size() != animations.size():
		return _error("invalid_motion", "Take metadata does not match the glTF animations.")
	var animation_names: Array[String] = []
	var seen_names: Dictionary = {}
	for animation_index in animations.size():
		var animation_data: Variant = animations[animation_index]
		if not animation_data is Dictionary:
			return _error("invalid_motion", "A glTF animation is malformed.")
		var animation_name := String(animation_data.get("name", ""))
		if animation_name.is_empty() or seen_names.has(animation_name):
			return _error("invalid_motion", "Generated take names must be non-empty and unique.")
		if not samples[animation_index] is Dictionary or samples[animation_index].get("name") != animation_name:
			return _error("invalid_motion", "Take metadata order or name does not match its animation.")
		if int(samples[animation_index].get("num_frames", -1)) != expected_frames:
			return _error("invalid_motion", "Take metadata frame count does not match the request.")
		seen_names[animation_name] = true
		animation_names.append(animation_name)
		var channel_result := _validate_channels(animation_data.get("channels"), nodes.size())
		if not channel_result["ok"]:
			return channel_result
	return {
		"ok": true,
		"rotation_channels": 77,
		"translation_channels": 1,
		"animation_names": animation_names,
	}


static func _validate_channels(channels: Variant, node_count: int) -> Dictionary:
	if not channels is Array:
		return _error("invalid_motion", "A glTF animation has no channels.")
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
		if float(node_number) != float(node_index) or node_number < 0 or node_number >= node_count:
			return _error("invalid_motion", "A glTF animation channel targets an invalid node.")
		if target.get("path") == "rotation":
			rotations += 1
			rotated_nodes[node_number] = true
		elif target.get("path") == "translation":
			translations += 1
			if node_number != 0:
				return _error("invalid_motion", "Only the SOMA root may have translation motion.")
	if rotations != 77 or rotated_nodes.size() != 77 or translations != 1:
		return _error("invalid_motion", "Expected 77 rotation channels and one root translation channel.")
	return {"ok": true}


static func _validate_animation_values(animation: Animation) -> String:
	for track in animation.get_track_count():
		var type := animation.track_get_type(track)
		for time in [0.0, animation.length * 0.5, animation.length]:
			var sample: Variant = null
			if type == Animation.TYPE_ROTATION_3D:
				sample = animation.rotation_track_interpolate(track, time)
			elif type == Animation.TYPE_POSITION_3D:
				sample = animation.position_track_interpolate(track, time)
			if sample is Quaternion and not sample.is_finite():
				return "A generated take contains non-finite rotations."
			if sample is Vector3 and not sample.is_finite():
				return "A generated take contains non-finite positions."
	return ""


static func _hash_animation(animation: Animation) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for track in animation.get_track_count():
		context.update((str(animation.track_get_type(track)) + "|" + str(animation.track_get_path(track))).to_utf8_buffer())
		for key in animation.track_get_key_count(track):
			context.update(var_to_bytes(animation.track_get_key_time(track, key)))
			context.update(var_to_bytes(animation.track_get_key_value(track, key)))
	return context.finish().hex_encode()


static func _free_motions(motions: Array) -> void:
	for motion in motions:
		if motion != null and is_instance_valid(motion.scene):
			motion.scene.free()


static func _keep_only_animation(player: AnimationPlayer, wanted_name: StringName) -> void:
	for library_name in player.get_animation_library_list():
		var library := player.get_animation_library(library_name)
		for animation_name in library.get_animation_list():
			if animation_name != wanted_name:
				library.remove_animation(animation_name)


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

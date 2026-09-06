class_name NativeAnimationBaker
extends RefCounted

const SKELETON_NODE_NAME := "Soma77Skeleton"
const PLAYER_NODE_NAME := "AnimationPlayer"
const ANIMATION_NAME := "motion"


static func bake(
	imported_root: Node,
	output_directory: String,
	requested_stem: String = "kimodo_motion",
) -> Dictionary:
	var source_skeleton := _find_first(imported_root, "Skeleton3D") as Skeleton3D
	var source_player := _find_first(imported_root, "AnimationPlayer") as AnimationPlayer
	if source_skeleton == null or source_player == null:
		push_error("Cannot bake motion without a Skeleton3D and AnimationPlayer")
		return {}
	var source_names := source_player.get_animation_list()
	if source_names.size() != 1:
		push_error("Expected exactly one source animation, found %d" % source_names.size())
		return {}

	var absolute_directory := ProjectSettings.globalize_path(output_directory)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		push_error("Cannot create native animation output directory: %s" % output_directory)
		return {}
	var stem := _unique_stem(output_directory, requested_stem)
	# Binary .res keeps generated animation keys compact and avoids text-format
	# precision becoming part of the accepted-animation contract.
	var library_path := output_directory.path_join(stem + ".res")
	var scene_path := output_directory.path_join(stem + ".tscn")

	var native_root := Node3D.new()
	native_root.name = "Soma77Motion"
	var native_skeleton := _copy_skeleton(source_skeleton)
	native_root.add_child(native_skeleton)
	native_skeleton.owner = native_root

	var native_animation := source_player.get_animation(source_names[0]).duplicate(true) as Animation
	for track in native_animation.get_track_count():
		var source_path := native_animation.track_get_path(track)
		if source_path.get_subname_count() != 1:
			push_error("Unsupported imported animation track path: %s" % source_path)
			native_root.free()
			return {}
		var bone_name := source_path.get_subname(0)
		native_animation.track_set_path(
			track, NodePath("%s:%s" % [SKELETON_NODE_NAME, bone_name])
		)
	native_animation.resource_name = ANIMATION_NAME

	var library := AnimationLibrary.new()
	if library.add_animation(ANIMATION_NAME, native_animation) != OK:
		push_error("Cannot add the native motion to its AnimationLibrary")
		native_root.free()
		return {}
	if ResourceSaver.save(library, library_path) != OK:
		push_error("Cannot save native AnimationLibrary: %s" % library_path)
		native_root.free()
		return {}

	var saved_library := ResourceLoader.load(
		library_path, "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE
	) as AnimationLibrary
	var player := AnimationPlayer.new()
	player.name = PLAYER_NODE_NAME
	if player.add_animation_library("", saved_library) != OK:
		push_error("Cannot attach the saved AnimationLibrary to its playback scene")
		native_root.free()
		return {}
	native_root.add_child(player)
	player.owner = native_root

	var packed := PackedScene.new()
	if packed.pack(native_root) != OK or ResourceSaver.save(packed, scene_path) != OK:
		push_error("Cannot save native skeleton scene: %s" % scene_path)
		native_root.free()
		return {}
	native_root.free()
	return {
		"stem": stem,
		"library_path": library_path,
		"scene_path": scene_path,
		"animation_name": ANIMATION_NAME,
	}


static func _copy_skeleton(source: Skeleton3D) -> Skeleton3D:
	var target := Skeleton3D.new()
	target.name = SKELETON_NODE_NAME
	target.transform = source.transform
	for index in source.get_bone_count():
		target.add_bone(source.get_bone_name(index))
		target.set_bone_parent(index, source.get_bone_parent(index))
		target.set_bone_rest(index, source.get_bone_rest(index))
		target.set_bone_pose_position(index, source.get_bone_pose_position(index))
		target.set_bone_pose_rotation(index, source.get_bone_pose_rotation(index))
		target.set_bone_pose_scale(index, source.get_bone_pose_scale(index))
	return target


static func _unique_stem(directory: String, requested: String) -> String:
	var clean := requested.validate_filename().strip_edges()
	if clean.is_empty():
		clean = "kimodo_motion"
	var candidate := clean
	var suffix := 2
	while (
		FileAccess.file_exists(directory.path_join(candidate + ".res"))
		or FileAccess.file_exists(directory.path_join(candidate + ".tscn"))
	):
		candidate = "%s_%d" % [clean, suffix]
		suffix += 1
	return candidate


static func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null

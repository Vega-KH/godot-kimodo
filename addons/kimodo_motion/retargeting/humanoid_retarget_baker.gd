class_name HumanoidRetargetBaker
extends RefCounted

const MAP := preload("res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd")
const TARGET_SKELETON_NAME := "HumanoidSkeleton"
const PLAYER_NODE_NAME := "AnimationPlayer"
const ANIMATION_NAME := "motion"


static func bake(
	source_root: Node,
	target_template_root: Node,
	output_directory: String,
	requested_stem: String = "kimodo_humanoid_motion",
) -> Dictionary:
	var source_skeleton := _find_first(source_root, "Skeleton3D") as Skeleton3D
	var source_player := _find_first(source_root, "AnimationPlayer") as AnimationPlayer
	var target_template := _find_first(target_template_root, "Skeleton3D") as Skeleton3D
	if source_skeleton == null or source_player == null or target_template == null:
		push_error("Retargeting requires source motion and target humanoid skeletons")
		return {}
	var mapping_error := MAP.validate(source_skeleton, target_template)
	if not mapping_error.is_empty():
		push_error(mapping_error)
		return {}
	var source_names := source_player.get_animation_list()
	if source_names.size() != 1:
		push_error("Expected exactly one source animation, found %d" % source_names.size())
		return {}
	var source_animation := source_player.get_animation(source_names[0])
	var target_animation := _retarget_animation(
		source_skeleton, source_animation, target_template
	)
	if target_animation == null:
		return {}

	var absolute_directory := ProjectSettings.globalize_path(output_directory)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		push_error("Cannot create retarget output directory: %s" % output_directory)
		return {}
	var stem := _unique_stem(output_directory, requested_stem)
	var library_path := output_directory.path_join(stem + ".res")
	var scene_path := output_directory.path_join(stem + ".tscn")

	var library := AnimationLibrary.new()
	if library.add_animation(ANIMATION_NAME, target_animation) != OK:
		push_error("Cannot add retargeted motion to its AnimationLibrary")
		return {}
	if ResourceSaver.save(library, library_path) != OK:
		push_error("Cannot save retargeted AnimationLibrary: %s" % library_path)
		return {}

	var output_root := Node3D.new()
	output_root.name = "HumanoidMotion"
	var output_skeleton := _copy_skeleton(target_template)
	output_root.add_child(output_skeleton)
	output_skeleton.owner = output_root
	var saved_library := ResourceLoader.load(
		library_path, "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE
	) as AnimationLibrary
	var player := AnimationPlayer.new()
	player.name = PLAYER_NODE_NAME
	if player.add_animation_library("", saved_library) != OK:
		push_error("Cannot attach the retargeted AnimationLibrary")
		output_root.free()
		return {}
	output_root.add_child(player)
	player.owner = output_root

	var packed := PackedScene.new()
	if (
		packed.pack(output_root) != OK
		or ResourceSaver.save(
			packed, scene_path, ResourceSaver.FLAG_OMIT_EDITOR_PROPERTIES
		) != OK
	):
		push_error("Cannot save retargeted humanoid scene: %s" % scene_path)
		output_root.free()
		return {}
	output_root.free()
	if not _strip_scene_unique_ids(scene_path):
		push_error("Cannot normalize retargeted humanoid scene: %s" % scene_path)
		return {}
	return {
		"stem": stem,
		"library_path": library_path,
		"scene_path": scene_path,
		"animation_name": ANIMATION_NAME,
		"mapped_bone_count": MAP.REQUIRED_TARGETS.size(),
	}


static func _retarget_animation(
	source: Skeleton3D, source_animation: Animation, target: Skeleton3D
) -> Animation:
	var source_tracks := _index_tracks(source_animation)
	var sample_times := _collect_sample_times(source_animation)
	if sample_times.is_empty():
		push_error("Source animation has no keys")
		return null
	var source_global_rests := _global_rests(source)
	var target_global_rests := _global_rests(target)
	var animation := Animation.new()
	animation.resource_name = ANIMATION_NAME
	animation.length = source_animation.length
	animation.loop_mode = source_animation.loop_mode

	var rotation_tracks := {}
	for target_name in MAP.REQUIRED_TARGETS:
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath("%s:%s" % [TARGET_SKELETON_NAME, target_name]))
		rotation_tracks[target_name] = track
	var hips_position_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(
		hips_position_track, NodePath("%s:Hips" % TARGET_SKELETON_NAME)
	)
	var root_position_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(
		root_position_track, NodePath("%s:Root" % TARGET_SKELETON_NAME)
	)

	for time in sample_times:
		var source_globals := _sample_global_poses(
			source, source_animation, source_tracks, time
		)
		var target_locals := _target_local_poses(
			source, source_globals, source_global_rests, target, target_global_rests
		)
		for target_name in MAP.REQUIRED_TARGETS:
			var target_index := target.find_bone(target_name)
			var local_pose: Transform3D = target_locals[target_index]
			animation.rotation_track_insert_key(
				rotation_tracks[target_name], time, local_pose.basis.get_rotation_quaternion()
			)
		var hips_index := target.find_bone("Hips")
		var hips_pose: Transform3D = target_locals[hips_index]
		animation.position_track_insert_key(hips_position_track, time, hips_pose.origin)
		var root_index := target.find_bone("Root")
		var root_pose: Transform3D = target_locals[root_index]
		animation.position_track_insert_key(root_position_track, time, root_pose.origin)
	return animation


static func _target_local_poses(
	source: Skeleton3D,
	source_globals: Array[Transform3D],
	source_global_rests: Array[Transform3D],
	target: Skeleton3D,
	target_global_rests: Array[Transform3D],
) -> Array[Transform3D]:
	var target_locals: Array[Transform3D] = []
	var target_globals: Array[Transform3D] = []
	target_locals.resize(target.get_bone_count())
	target_globals.resize(target.get_bone_count())
	for target_index in target.get_bone_count():
		var target_name := target.get_bone_name(target_index)
		var parent_index := target.get_bone_parent(target_index)
		var parent_global := Transform3D.IDENTITY
		if parent_index >= 0:
			parent_global = target_globals[parent_index]
		var local_pose := target.get_bone_rest(target_index)
		if target_name == "Root":
			var source_hips := source.find_bone("Hips")
			var root_delta := (
				source_globals[source_hips].origin
				- source_global_rests[source_hips].origin
			)
			# Planar locomotion belongs to the profile Root. Hips retains
			# vertical pelvis motion relative to that traveling root.
			local_pose.origin += Vector3(root_delta.x, 0.0, root_delta.z)
		var source_name: StringName = MAP.source_for_target(target_name)
		if not source_name.is_empty():
			var source_index := source.find_bone(source_name)
			var source_motion := (
				source_globals[source_index].basis
				* source_global_rests[source_index].basis.inverse()
			)
			var desired_global_basis := (
				source_motion * target_global_rests[target_index].basis
			)
			local_pose.basis = parent_global.basis.inverse() * desired_global_basis
			if target_name == "Hips":
				var root_delta := (
					source_globals[source_index].origin
					- source_global_rests[source_index].origin
				)
				var desired_origin := target_global_rests[target_index].origin + root_delta
				local_pose.origin = parent_global.affine_inverse() * desired_origin
		target_locals[target_index] = local_pose
		target_globals[target_index] = parent_global * local_pose
	return target_locals


static func _sample_global_poses(
	skeleton: Skeleton3D, animation: Animation, tracks: Dictionary, time: float
) -> Array[Transform3D]:
	var globals: Array[Transform3D] = []
	globals.resize(skeleton.get_bone_count())
	for index in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(index)
		var position := skeleton.get_bone_pose_position(index)
		var rotation := skeleton.get_bone_pose_rotation(index)
		var scale := skeleton.get_bone_pose_scale(index)
		var position_key := "%s:%d" % [bone_name, Animation.TYPE_POSITION_3D]
		var rotation_key := "%s:%d" % [bone_name, Animation.TYPE_ROTATION_3D]
		var scale_key := "%s:%d" % [bone_name, Animation.TYPE_SCALE_3D]
		if tracks.has(position_key):
			position = animation.position_track_interpolate(tracks[position_key], time)
		if tracks.has(rotation_key):
			rotation = animation.rotation_track_interpolate(tracks[rotation_key], time)
		if tracks.has(scale_key):
			scale = animation.scale_track_interpolate(tracks[scale_key], time)
		var local := Transform3D(Basis(rotation).scaled(scale), position)
		var parent := skeleton.get_bone_parent(index)
		globals[index] = local if parent < 0 else globals[parent] * local
	return globals


static func _global_rests(skeleton: Skeleton3D) -> Array[Transform3D]:
	var rests: Array[Transform3D] = []
	rests.resize(skeleton.get_bone_count())
	for index in skeleton.get_bone_count():
		var local := skeleton.get_bone_rest(index)
		var parent := skeleton.get_bone_parent(index)
		rests[index] = local if parent < 0 else rests[parent] * local
	return rests


static func _index_tracks(animation: Animation) -> Dictionary:
	var result := {}
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		if path.get_subname_count() == 1:
			result["%s:%d" % [path.get_subname(0), animation.track_get_type(track)]] = track
	return result


static func _collect_sample_times(animation: Animation) -> Array[float]:
	var unique := {}
	for track in animation.get_track_count():
		for key in animation.track_get_key_count(track):
			unique[animation.track_get_key_time(track, key)] = true
	var times: Array[float] = []
	for value in unique.keys():
		times.append(value)
	times.sort()
	return times


static func _copy_skeleton(source: Skeleton3D) -> Skeleton3D:
	var target := Skeleton3D.new()
	target.name = TARGET_SKELETON_NAME
	target.transform = source.transform
	for index in source.get_bone_count():
		target.add_bone(source.get_bone_name(index))
		target.set_bone_parent(index, source.get_bone_parent(index))
		target.set_bone_rest(index, source.get_bone_rest(index))
		target.set_bone_pose(index, source.get_bone_rest(index))
	return target


static func _unique_stem(directory: String, requested: String) -> String:
	var clean := requested.validate_filename().strip_edges()
	if clean.is_empty():
		clean = "kimodo_humanoid_motion"
	var candidate := clean
	var suffix := 2
	while (
		FileAccess.file_exists(directory.path_join(candidate + ".res"))
		or FileAccess.file_exists(directory.path_join(candidate + ".tscn"))
	):
		candidate = "%s_%d" % [clean, suffix]
		suffix += 1
	return candidate


static func _strip_scene_unique_ids(path: String) -> bool:
	# PackedScene assigns random editor-only node IDs. Track paths in this
	# artifact are name-based, so removing those IDs makes regeneration stable.
	var expression := RegEx.create_from_string(" unique_id=[0-9]+")
	var text := FileAccess.get_file_as_string(path)
	var normalized := expression.sub(text, "", true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(normalized)
	return true


static func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null

class_name HumanoidCharacterBaker
extends RefCounted

const HumanoidMap := preload(
	"res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd"
)
const RigProfile := preload(
	"res://addons/kimodo_motion/retargeting/humanoid_rig_profile.gd"
)
const RestOrientation := preload(
	"res://addons/kimodo_motion/retargeting/rest_orientation.gd"
)
const ProjectPaths := preload("res://addons/kimodo_motion/domain/project_paths.gd")
const ANIMATION_NAME := "motion"
const PLAYER_NODE_NAME := "KimodoAnimationPlayer"


class CharacterMotion extends RefCounted:
	var scene: Node3D
	var skeleton: Skeleton3D
	var player: AnimationPlayer
	var animation_name: StringName = &"motion"


static func create_motion(
	source_root: Node, character_root: Node3D, rig_profile: RefCounted = null
) -> CharacterMotion:
	var source_skeleton := _find_first(source_root, "Skeleton3D") as Skeleton3D
	var source_player := _find_first(source_root, "AnimationPlayer") as AnimationPlayer
	var target_skeleton := _find_first(character_root, "Skeleton3D") as Skeleton3D
	if target_skeleton == null:
		push_error("Character target has no Skeleton3D")
		return null
	var skeleton_path := character_root.get_path_to(target_skeleton)
	if rig_profile == null:
		var profile_result := RigProfile.exact_names(target_skeleton, skeleton_path)
		if not profile_result["ok"]:
			push_error(profile_result["message"])
			return null
		rig_profile = profile_result["profile"]
	var target_error := validate_target(character_root, rig_profile)
	if not target_error.is_empty():
		push_error(target_error)
		return null
	var error := validate(source_skeleton, source_player, target_skeleton, rig_profile)
	if not error.is_empty():
		push_error(error)
		return null
	var source_animation := source_player.get_animation(ANIMATION_NAME)
	var animation := _retarget_animation(
		source_skeleton, source_animation, target_skeleton, rig_profile
	)
	if animation == null:
		return null
	var library := AnimationLibrary.new()
	if library.add_animation(ANIMATION_NAME, animation) != OK:
		push_error("Cannot add character motion to its AnimationLibrary")
		return null
	var player := AnimationPlayer.new()
	player.name = PLAYER_NODE_NAME
	if player.add_animation_library("", library) != OK:
		push_error("Cannot attach the character AnimationLibrary")
		player.free()
		return null
	character_root.add_child(player)
	player.owner = character_root
	player.play(ANIMATION_NAME)
	var motion := CharacterMotion.new()
	motion.scene = character_root
	motion.skeleton = target_skeleton
	motion.player = player
	return motion


static func validate_target(character_root: Node, rig_profile: RefCounted = null) -> String:
	if character_root == null:
		return "Character target could not be instantiated"
	var skeletons := character_root.find_children("*", "Skeleton3D", true, false)
	if character_root is Skeleton3D:
		skeletons.push_front(character_root)
	if skeletons.size() != 1:
		return "Character target must contain exactly one Skeleton3D (found %d)" % skeletons.size()
	var skeleton := skeletons[0] as Skeleton3D
	if rig_profile == null:
		var profile_result := RigProfile.exact_names(
			skeleton, character_root.get_path_to(skeleton)
		)
		if not profile_result["ok"]:
			return profile_result["message"]
		rig_profile = profile_result["profile"]
	for canonical_name in ["Root", "Hips"] + rig_profile.rotation_targets():
		var target_name: StringName = rig_profile.target_for(canonical_name)
		if target_name.is_empty() or skeleton.find_bone(target_name) < 0:
			return "Character rig profile cannot resolve %s" % canonical_name
	for bone_index in skeleton.get_bone_count():
		if not skeleton.get_bone_rest(bone_index).is_finite():
			return "Character skeleton has a non-finite rest transform at bone %s" % skeleton.get_bone_name(bone_index)
	var skinned_meshes := 0
	for found in character_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := found as MeshInstance3D
		if mesh_instance.skin == null:
			continue
		if mesh_instance.skin.get_bind_count() <= 0:
			return "Character mesh %s has an empty Skin binding" % mesh_instance.name
		skinned_meshes += 1
	if skinned_meshes == 0:
		return "Character target must contain at least one skinned MeshInstance3D"
	if character_root.get_node_or_null(PLAYER_NODE_NAME) != null:
		return "Character target already owns the reserved %s node" % PLAYER_NODE_NAME
	return ""


static func validate(
	source_skeleton: Skeleton3D,
	source_player: AnimationPlayer,
	target_skeleton: Skeleton3D,
	rig_profile: RefCounted = null,
) -> String:
	if source_skeleton == null or source_player == null:
		return "Character retargeting requires a humanoid source skeleton and animation"
	if target_skeleton == null:
		return "Character retargeting requires a target Skeleton3D"
	if not source_player.has_animation(ANIMATION_NAME):
		return "Humanoid source is missing animation '%s'" % ANIMATION_NAME
	if rig_profile == null:
		var profile_result := RigProfile.exact_names(target_skeleton, NodePath("."))
		if not profile_result["ok"]:
			return profile_result["message"]
		rig_profile = profile_result["profile"]
	for canonical_name in ["Root", "Hips"] + rig_profile.rotation_targets():
		if source_skeleton.find_bone(canonical_name) < 0:
			return "Humanoid source is missing required bone %s" % canonical_name
		var target_name: StringName = rig_profile.target_for(canonical_name)
		if target_skeleton.find_bone(target_name) < 0:
			return "Character skeleton is missing profiled bone %s" % target_name
	var source_rests := _global_rests(source_skeleton)
	var target_rests := _global_rests(target_skeleton)
	for canonical_name in HumanoidMap.ORIENTATION_FRAMES:
		if rig_profile.target_for(canonical_name).is_empty():
			continue
		var frame_error := _validate_orientation_frame(
			canonical_name,
			source_skeleton,
			source_rests,
			target_skeleton,
			target_rests,
			rig_profile,
		)
		if not frame_error.is_empty():
			return frame_error
	return ""


static func save_library(
	character_root: Node3D,
	output_directory: String,
	requested_stem: String = "kimodo_character_motion",
) -> Dictionary:
	var player := character_root.get_node_or_null(PLAYER_NODE_NAME) as AnimationPlayer
	if player == null or not player.has_animation(ANIMATION_NAME):
		push_error("Cannot save a character animation without its Kimodo animation")
		return {}
	var directory_result := ProjectPaths.ensure_directory(output_directory)
	if not directory_result["ok"]:
		push_error(directory_result["message"])
		return {}
	output_directory = directory_result["path"]
	var stem := _unique_library_stem(output_directory, requested_stem)
	var library_path := output_directory.path_join(stem + ".res")
	var library := AnimationLibrary.new()
	var animation := player.get_animation(ANIMATION_NAME).duplicate(true) as Animation
	if library.add_animation(ANIMATION_NAME, animation) != OK:
		push_error("Cannot add character motion to its AnimationLibrary")
		return {}
	if ResourceSaver.save(library, library_path) != OK:
		push_error("Cannot save character AnimationLibrary: %s" % library_path)
		return {}
	return {
		"stem": stem,
		"library_path": library_path,
		"animation_name": ANIMATION_NAME,
	}


static func save_preview_scene(
	character_root: Node3D,
	output_directory: String,
	requested_stem: String = "kimodo_character_preview",
) -> Dictionary:
	var player := character_root.get_node_or_null(PLAYER_NODE_NAME) as AnimationPlayer
	if player == null or not player.has_animation(ANIMATION_NAME):
		push_error("Cannot save a character scene without its Kimodo animation")
		return {}
	var directory_result := ProjectPaths.ensure_directory(output_directory)
	if not directory_result["ok"]:
		push_error(directory_result["message"])
		return {}
	output_directory = directory_result["path"]
	var stem := _unique_scene_stem(output_directory, requested_stem)
	var scene_path := output_directory.path_join(stem + ".tscn")
	var packed := PackedScene.new()
	if (
		packed.pack(character_root) != OK
		or ResourceSaver.save(
			packed, scene_path, ResourceSaver.FLAG_OMIT_EDITOR_PROPERTIES
		) != OK
	):
		push_error("Cannot save retargeted character scene: %s" % scene_path)
		if FileAccess.file_exists(scene_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(scene_path))
		return {}
	return {
		"stem": stem,
		"scene_path": scene_path,
		"animation_name": ANIMATION_NAME,
	}


static func save_motion(
	character_root: Node3D,
	output_directory: String,
	requested_stem: String = "kimodo_character_motion",
) -> Dictionary:
	# Compatibility alias for callers that predate the explicit export choices.
	return save_preview_scene(character_root, output_directory, requested_stem)


static func _retarget_animation(
	source: Skeleton3D,
	source_animation: Animation,
	target: Skeleton3D,
	rig_profile: RefCounted,
) -> Animation:
	var source_tracks := _index_tracks(source_animation)
	var sample_times := _collect_sample_times(source_animation)
	if sample_times.is_empty():
		push_error("Humanoid animation has no keys")
		return null
	var source_global_rests := _global_rests(source)
	var target_global_rests := _global_rests(target)
	var animation := Animation.new()
	animation.resource_name = ANIMATION_NAME
	animation.length = source_animation.length
	animation.loop_mode = source_animation.loop_mode
	var rotation_tracks := {}
	for canonical_name in rig_profile.rotation_targets():
		var bone_name: StringName = rig_profile.target_for(canonical_name)
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, _track_path(rig_profile.skeleton_path, bone_name))
		rotation_tracks[canonical_name] = track
	var root_position_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(
		root_position_track,
		_track_path(rig_profile.skeleton_path, rig_profile.target_for("Root")),
	)
	var hips_position_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(
		hips_position_track,
		_track_path(rig_profile.skeleton_path, rig_profile.target_for("Hips")),
	)

	for time in sample_times:
		var source_globals := _sample_global_poses(
			source, source_animation, source_tracks, time
		)
		var target_locals := _target_local_poses(
			source,
			source_globals,
			source_global_rests,
			target,
			target_global_rests,
			rig_profile,
		)
		for canonical_name in rig_profile.rotation_targets():
			var target_index := target.find_bone(rig_profile.target_for(canonical_name))
			animation.rotation_track_insert_key(
				rotation_tracks[canonical_name],
				time,
				target_locals[target_index].basis.get_rotation_quaternion(),
			)
		animation.position_track_insert_key(
			root_position_track,
			time,
			target_locals[target.find_bone(rig_profile.target_for("Root"))].origin,
		)
		animation.position_track_insert_key(
			hips_position_track,
			time,
			target_locals[target.find_bone(rig_profile.target_for("Hips"))].origin,
		)
	return animation


static func _target_local_poses(
	source: Skeleton3D,
	source_globals: Array[Transform3D],
	source_global_rests: Array[Transform3D],
	target: Skeleton3D,
	target_global_rests: Array[Transform3D],
	rig_profile: RefCounted,
) -> Array[Transform3D]:
	var target_locals: Array[Transform3D] = []
	var target_globals: Array[Transform3D] = []
	target_locals.resize(target.get_bone_count())
	target_globals.resize(target.get_bone_count())
	for target_index in target.get_bone_count():
		var target_name := target.get_bone_name(target_index)
		var canonical_name: StringName = rig_profile.canonical_for(target_name)
		var parent_index := target.get_bone_parent(target_index)
		var parent_global := Transform3D.IDENTITY
		if parent_index >= 0:
			parent_global = target_globals[parent_index]
		var local_pose := target.get_bone_rest(target_index)
		if canonical_name == "Root":
			var source_index := source.find_bone("Root")
			var source_delta := (
				source_globals[source_index].origin
				- source_global_rests[source_index].origin
			)
			local_pose.origin += source_delta
		if canonical_name in rig_profile.rotation_targets():
			var source_index := source.find_bone(canonical_name)
			var source_motion := (
				source_globals[source_index].basis
				* source_global_rests[source_index].basis.inverse()
			)
			var corrected_target_rest := _direction_corrected_rest_basis(
				canonical_name,
				source,
				source_global_rests,
				target,
				target_global_rests,
				rig_profile,
			)
			var desired_global_basis := (
				source_motion * corrected_target_rest
			)
			local_pose.basis = parent_global.basis.inverse() * desired_global_basis
			if canonical_name == "Hips":
				var source_delta := (
					source_globals[source_index].origin
					- source_global_rests[source_index].origin
				)
				var desired_origin := target_global_rests[target_index].origin + source_delta
				local_pose.origin = parent_global.affine_inverse() * desired_origin
		target_locals[target_index] = local_pose
		target_globals[target_index] = parent_global * local_pose
	return target_locals


static func _direction_corrected_rest_basis(
	canonical_name: StringName,
	source: Skeleton3D,
	source_global_rests: Array[Transform3D],
	target: Skeleton3D,
	target_global_rests: Array[Transform3D],
	rig_profile: RefCounted,
) -> Basis:
	var source_index := source.find_bone(canonical_name)
	var target_index := target.find_bone(rig_profile.target_for(canonical_name))
	var target_basis := target_global_rests[target_index].basis
	var frame_owner := HumanoidMap.orientation_frame_owner_for_target(canonical_name)
	var frame: Dictionary = HumanoidMap.orientation_frame_for_target(frame_owner)
	if not frame.is_empty():
		var source_frame := RestOrientation.anatomical_frame(
			source,
			source_global_rests,
			frame_owner,
			frame["forward"],
			frame["lateral_from"],
			frame["lateral_to"],
		)
		var target_frame := RestOrientation.anatomical_frame(
			target,
			target_global_rests,
			rig_profile.target_for(frame_owner),
			rig_profile.target_for(frame["forward"]),
			rig_profile.target_for(frame["lateral_from"]),
			rig_profile.target_for(frame["lateral_to"]),
		)
		if not source_frame["ok"] or not target_frame["ok"]:
			push_error("Validated hand orientation frame became unavailable")
			return target_basis
		return source_frame["basis"] * target_frame["basis"].inverse() * target_basis
	var child_canonical := HumanoidMap.direction_child_for_target(canonical_name)
	if child_canonical.is_empty() or rig_profile.target_for(child_canonical).is_empty():
		return target_basis
	var source_child_index := source.find_bone(child_canonical)
	var target_child_index := target.find_bone(rig_profile.target_for(child_canonical))
	var source_direction := source_global_rests[source_index].origin.direction_to(
		source_global_rests[source_child_index].origin
	)
	var target_direction := target_global_rests[target_index].origin.direction_to(
		target_global_rests[target_child_index].origin
	)
	return Basis(Quaternion(target_direction, source_direction)) * target_basis


static func _validate_orientation_frame(
	canonical_name: StringName,
	source: Skeleton3D,
	source_rests: Array[Transform3D],
	target: Skeleton3D,
	target_rests: Array[Transform3D],
	rig_profile: RefCounted,
) -> String:
	var frame: Dictionary = HumanoidMap.orientation_frame_for_target(canonical_name)
	var source_frame := RestOrientation.anatomical_frame(
		source,
		source_rests,
		canonical_name,
		frame["forward"],
		frame["lateral_from"],
		frame["lateral_to"],
	)
	if not source_frame["ok"]:
		return "Humanoid %s" % source_frame["message"]
	var target_names := [
		rig_profile.target_for(canonical_name),
		rig_profile.target_for(frame["forward"]),
		rig_profile.target_for(frame["lateral_from"]),
		rig_profile.target_for(frame["lateral_to"]),
	]
	for target_name in target_names:
		if target_name.is_empty():
			return "Character rig profile cannot resolve the %s hand orientation frame" % canonical_name
	var target_frame := RestOrientation.anatomical_frame(
		target,
		target_rests,
		target_names[0],
		target_names[1],
		target_names[2],
		target_names[3],
	)
	if not target_frame["ok"]:
		return "Character %s" % target_frame["message"]
	return ""


static func _sample_global_poses(
	skeleton: Skeleton3D,
	animation: Animation,
	tracks: Dictionary,
	time: float,
) -> Array[Transform3D]:
	var globals: Array[Transform3D] = []
	globals.resize(skeleton.get_bone_count())
	for index in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(index)
		var rest := skeleton.get_bone_rest(index)
		var position := rest.origin
		var rotation := rest.basis.get_rotation_quaternion()
		var scale := rest.basis.get_scale()
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


static func _track_path(skeleton_path: NodePath, bone_name: StringName) -> NodePath:
	return NodePath("%s:%s" % [skeleton_path, bone_name])


static func _unique_stem(directory: String, requested: String) -> String:
	var clean := requested.validate_filename().strip_edges()
	if clean.is_empty():
		clean = "kimodo_character_motion"
	var candidate := clean
	var suffix := 2
	while FileAccess.file_exists(directory.path_join(candidate + ".tscn")):
		candidate = "%s_%d" % [clean, suffix]
		suffix += 1
	return candidate


static func _unique_library_stem(directory: String, requested: String) -> String:
	return _unique_stem_for_extension(directory, requested, ".res", "kimodo_character_motion")


static func _unique_scene_stem(directory: String, requested: String) -> String:
	return _unique_stem_for_extension(directory, requested, ".tscn", "kimodo_character_preview")


static func _unique_stem_for_extension(
	directory: String, requested: String, extension: String, fallback: String
) -> String:
	var clean := requested.validate_filename().strip_edges()
	if clean.is_empty():
		clean = fallback
	var candidate := clean
	var suffix := 2
	while FileAccess.file_exists(directory.path_join(candidate + extension)):
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

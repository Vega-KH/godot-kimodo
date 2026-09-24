class_name HumanoidCharacterBaker
extends RefCounted

const HumanoidMap := preload(
	"res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd"
)
const ANIMATION_NAME := "motion"
const PLAYER_NODE_NAME := "KimodoAnimationPlayer"


class CharacterMotion extends RefCounted:
	var scene: Node3D
	var skeleton: Skeleton3D
	var player: AnimationPlayer
	var animation_name: StringName = &"motion"


static func create_motion(source_root: Node, character_root: Node3D) -> CharacterMotion:
	var source_skeleton := _find_first(source_root, "Skeleton3D") as Skeleton3D
	var source_player := _find_first(source_root, "AnimationPlayer") as AnimationPlayer
	var target_skeleton := _find_first(character_root, "Skeleton3D") as Skeleton3D
	var error := validate(source_skeleton, source_player, target_skeleton)
	if not error.is_empty():
		push_error(error)
		return null
	var source_animation := source_player.get_animation(ANIMATION_NAME)
	var skeleton_path := character_root.get_path_to(target_skeleton)
	var animation := _retarget_animation(
		source_skeleton, source_animation, target_skeleton, skeleton_path
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


static func validate(
	source_skeleton: Skeleton3D,
	source_player: AnimationPlayer,
	target_skeleton: Skeleton3D,
) -> String:
	if source_skeleton == null or source_player == null:
		return "Character retargeting requires a humanoid source skeleton and animation"
	if target_skeleton == null:
		return "Character retargeting requires a target Skeleton3D"
	if not source_player.has_animation(ANIMATION_NAME):
		return "Humanoid source is missing animation '%s'" % ANIMATION_NAME
	for bone_name in ["Root", "Hips"]:
		if source_skeleton.find_bone(bone_name) < 0:
			return "Humanoid source is missing required bone %s" % bone_name
		if target_skeleton.find_bone(bone_name) < 0:
			return "Character skeleton is missing required bone %s" % bone_name
	for bone_name in HumanoidMap.REQUIRED_TARGETS:
		if source_skeleton.find_bone(bone_name) < 0:
			return "Humanoid source is missing required bone %s" % bone_name
		if target_skeleton.find_bone(bone_name) < 0:
			return "Character skeleton is missing required bone %s" % bone_name
	return ""


static func save_motion(
	character_root: Node3D,
	output_directory: String,
	requested_stem: String = "kimodo_character_motion",
) -> Dictionary:
	var player := character_root.get_node_or_null(PLAYER_NODE_NAME) as AnimationPlayer
	if player == null or not player.has_animation(ANIMATION_NAME):
		push_error("Cannot save a character scene without its Kimodo animation")
		return {}
	var absolute_directory := ProjectSettings.globalize_path(output_directory)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		push_error("Cannot create character output directory: %s" % output_directory)
		return {}
	var stem := _unique_stem(output_directory, requested_stem)
	var scene_path := output_directory.path_join(stem + ".tscn")
	var packed := PackedScene.new()
	if (
		packed.pack(character_root) != OK
		or ResourceSaver.save(
			packed, scene_path, ResourceSaver.FLAG_OMIT_EDITOR_PROPERTIES
		) != OK
	):
		push_error("Cannot save retargeted character scene: %s" % scene_path)
		return {}
	return {
		"stem": stem,
		"scene_path": scene_path,
		"animation_name": ANIMATION_NAME,
	}


static func _retarget_animation(
	source: Skeleton3D,
	source_animation: Animation,
	target: Skeleton3D,
	target_path: NodePath,
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
	for bone_name in HumanoidMap.REQUIRED_TARGETS:
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, _track_path(target_path, bone_name))
		rotation_tracks[bone_name] = track
	var root_position_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(root_position_track, _track_path(target_path, "Root"))
	var hips_position_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(hips_position_track, _track_path(target_path, "Hips"))

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
		)
		for bone_name in HumanoidMap.REQUIRED_TARGETS:
			var target_index := target.find_bone(bone_name)
			animation.rotation_track_insert_key(
				rotation_tracks[bone_name],
				time,
				target_locals[target_index].basis.get_rotation_quaternion(),
			)
		animation.position_track_insert_key(
			root_position_track,
			time,
			target_locals[target.find_bone("Root")].origin,
		)
		animation.position_track_insert_key(
			hips_position_track,
			time,
			target_locals[target.find_bone("Hips")].origin,
		)
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
		var source_index := source.find_bone(target_name)
		if target_name == "Root":
			var source_delta := (
				source_globals[source_index].origin
				- source_global_rests[source_index].origin
			)
			local_pose.origin += source_delta
		if target_name in HumanoidMap.REQUIRED_TARGETS:
			var source_motion := (
				source_globals[source_index].basis
				* source_global_rests[source_index].basis.inverse()
			)
			var corrected_target_rest := _direction_corrected_rest_basis(
				target_name,
				source,
				source_global_rests,
				target,
				target_global_rests,
			)
			var desired_global_basis := (
				source_motion * corrected_target_rest
			)
			local_pose.basis = parent_global.basis.inverse() * desired_global_basis
			if target_name == "Hips":
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
	bone_name: StringName,
	source: Skeleton3D,
	source_global_rests: Array[Transform3D],
	target: Skeleton3D,
	target_global_rests: Array[Transform3D],
) -> Basis:
	var source_index := source.find_bone(bone_name)
	var target_index := target.find_bone(bone_name)
	var target_basis := target_global_rests[target_index].basis
	var child_name := HumanoidMap.direction_child_for_target(bone_name)
	if child_name.is_empty():
		return target_basis
	var source_child_index := source.find_bone(child_name)
	var target_child_index := target.find_bone(child_name)
	var source_direction := source_global_rests[source_index].origin.direction_to(
		source_global_rests[source_child_index].origin
	)
	var target_direction := target_global_rests[target_index].origin.direction_to(
		target_global_rests[target_child_index].origin
	)
	return Basis(Quaternion(target_direction, source_direction)) * target_basis


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


static func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null

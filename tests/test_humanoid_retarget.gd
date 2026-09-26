extends SceneTree

const Baker := preload(
	"res://addons/kimodo_motion/retargeting/humanoid_retarget_baker.gd"
)
const Map := preload("res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd")
const RestOrientation := preload(
	"res://addons/kimodo_motion/retargeting/rest_orientation.gd"
)
const SOURCE_SCENE := "res://tests/native/generated/soma77_walk.tscn"
const SOURCE_LIBRARY := "res://tests/native/generated/soma77_walk.res"
const TARGET_FIXTURE := "res://tests/retargeting/fixtures/godot_humanoid_a_pose.tscn"
const SAMPLE_TIME := 0.5
const ROTATION_TOLERANCE := 0.001
const POSITION_TOLERANCE := 0.000001

var _failures: Array[String] = []


func _init() -> void:
	var source_hashes := {
		SOURCE_SCENE: _sha256(FileAccess.get_file_as_bytes(SOURCE_SCENE)),
		SOURCE_LIBRARY: _sha256(FileAccess.get_file_as_bytes(SOURCE_LIBRARY)),
		TARGET_FIXTURE: _sha256(FileAccess.get_file_as_bytes(TARGET_FIXTURE)),
	}
	var source := (load(SOURCE_SCENE) as PackedScene).instantiate()
	var target := (load(TARGET_FIXTURE) as PackedScene).instantiate()
	root.add_child(source)
	root.add_child(target)
	var source_skeleton := _find_first(source, "Skeleton3D") as Skeleton3D
	var target_skeleton := _find_first(target, "Skeleton3D") as Skeleton3D
	_validate_fixture(target_skeleton)
	_validate_mapping(source_skeleton, target_skeleton)
	_evaluate_engine_modifier(source_skeleton)

	var output_directory := "res://tests/.goal9_%d_%d" % [
		OS.get_process_id(), Time.get_ticks_usec()
	]
	var first := Baker.bake(source, target, output_directory, "walk_humanoid")
	_check(not first.is_empty(), "first humanoid retarget succeeds")
	if first.is_empty():
		_finish()
		return
	var first_scene_hash := _sha256(FileAccess.get_file_as_bytes(first["scene_path"]))
	var first_library_hash := _sha256(FileAccess.get_file_as_bytes(first["library_path"]))
	var second := Baker.bake(source, target, output_directory, "walk_humanoid")
	_check(second["stem"] == "walk_humanoid_2", "existing output receives a unique name")
	_check(first["scene_path"] != second["scene_path"], "target scene is not overwritten")
	_check(first["library_path"] != second["library_path"], "target library is not overwritten")
	_check(
		_sha256(FileAccess.get_file_as_bytes(first["scene_path"])) == first_scene_hash,
		"first target scene stays byte-identical after a second bake",
	)
	_check(
		_sha256(FileAccess.get_file_as_bytes(first["library_path"])) == first_library_hash,
		"first target library stays byte-identical after a second bake",
	)
	for path in source_hashes:
		_check(
			_sha256(FileAccess.get_file_as_bytes(path)) == source_hashes[path],
			"retargeting does not modify %s" % path,
		)

	var packed := ResourceLoader.load(
		first["scene_path"], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	var reloaded := packed.instantiate()
	root.add_child(reloaded)
	var reloaded_skeleton := _find_first(reloaded, "Skeleton3D") as Skeleton3D
	var reloaded_player := _find_first(reloaded, "AnimationPlayer") as AnimationPlayer
	_validate_reloaded(target_skeleton, reloaded_skeleton, reloaded_player)
	_validate_motion(source, reloaded)
	_validate_finger_rich_motion(source, target)
	_validate_dependency_closure(first["scene_path"])

	reloaded.queue_free()
	target.queue_free()
	source.queue_free()
	_remove_test_directory(output_directory)
	_finish()


func _validate_finger_rich_motion(source: Node, target: Node) -> void:
	var source_player := _find_first(source, "AnimationPlayer") as AnimationPlayer
	var source_animation := source_player.get_animation("motion")
	var finger_targets: Array[StringName] = []
	for target_name in Map.REQUIRED_TARGETS:
		if (
			String(target_name).contains("Thumb")
			or String(target_name).contains("Index")
			or String(target_name).contains("Middle")
			or String(target_name).contains("Ring")
			or String(target_name).contains("Little")
		):
			finger_targets.append(target_name)
			var source_name: StringName = Map.source_for_target(target_name)
			var track := _find_track(source_animation, source_name, Animation.TYPE_ROTATION_3D)
			_check(track >= 0, "finger-rich fixture resolves %s" % source_name)
			if track >= 0:
				var base := source_animation.rotation_track_interpolate(track, SAMPLE_TIME)
				source_animation.rotation_track_insert_key(
					track,
					SAMPLE_TIME,
					(base * Quaternion(Vector3.RIGHT, 0.35)).normalized(),
				)
	_check(finger_targets.size() == 30, "finger-rich fixture exercises all 30 mapped finger joints")
	source_player.clear_caches()
	var motion: RefCounted = Baker.create_motion(source, target)
	_check(motion != null, "finger-rich SOMA motion retargets")
	if motion == null:
		return
	_validate_animation_data_transfer(source, motion.scene, finger_targets)
	var output_player := _find_first(motion.scene, "AnimationPlayer") as AnimationPlayer
	var output_animation := output_player.get_animation("motion")
	var visibly_animated := 0
	for target_name in finger_targets:
		var track := _find_track(output_animation, target_name, Animation.TYPE_ROTATION_3D)
		var start := output_animation.rotation_track_interpolate(track, 0.0)
		var bent := output_animation.rotation_track_interpolate(track, SAMPLE_TIME)
		if start.angle_to(bent) > 0.1:
			visibly_animated += 1
	_check(visibly_animated == 30, "all mapped humanoid fingers visibly leave their initial pose")
	motion.scene.free()


func _validate_animation_data_transfer(
	source_root: Node, target_root: Node, target_names: Array[StringName]
) -> void:
	var source_skeleton := _find_first(source_root, "Skeleton3D") as Skeleton3D
	var source_player := _find_first(source_root, "AnimationPlayer") as AnimationPlayer
	var target_skeleton := _find_first(target_root, "Skeleton3D") as Skeleton3D
	var target_player := _find_first(target_root, "AnimationPlayer") as AnimationPlayer
	var source_globals := _sample_animation_globals(
		source_skeleton, source_player.get_animation("motion"), SAMPLE_TIME
	)
	var target_globals := _sample_animation_globals(
		target_skeleton, target_player.get_animation("motion"), SAMPLE_TIME
	)
	var source_rests := _global_rests(source_skeleton)
	var target_rests := _global_rests(target_skeleton)
	for target_name in target_names:
		var source_index := source_skeleton.find_bone(Map.source_for_target(target_name))
		var target_index := target_skeleton.find_bone(target_name)
		var source_delta := source_globals[source_index].basis * source_rests[source_index].basis.inverse()
		var corrected_rest := _direction_corrected_rest(
			target_name, source_skeleton, source_rests, target_skeleton, target_rests
		)
		var target_delta := target_globals[target_index].basis * corrected_rest.inverse()
		_check(
			source_delta.get_rotation_quaternion().angle_to(
				target_delta.get_rotation_quaternion()
			) <= ROTATION_TOLERANCE,
			"%s finger model-space delta transfers numerically" % target_name,
		)


func _sample_animation_globals(
	skeleton: Skeleton3D, animation: Animation, time: float
) -> Array[Transform3D]:
	var tracks := {}
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		if path.get_subname_count() == 1:
			tracks["%s:%d" % [path.get_subname(0), animation.track_get_type(track)]] = track
	var globals: Array[Transform3D] = []
	globals.resize(skeleton.get_bone_count())
	for index in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(index)
		var rest := skeleton.get_bone_rest(index)
		var position := rest.origin
		var rotation := rest.basis.get_rotation_quaternion()
		var position_key := "%s:%d" % [bone_name, Animation.TYPE_POSITION_3D]
		var rotation_key := "%s:%d" % [bone_name, Animation.TYPE_ROTATION_3D]
		if tracks.has(position_key):
			position = animation.position_track_interpolate(tracks[position_key], time)
		if tracks.has(rotation_key):
			rotation = animation.rotation_track_interpolate(tracks[rotation_key], time)
		var local := Transform3D(Basis(rotation), position)
		var parent := skeleton.get_bone_parent(index)
		globals[index] = local if parent < 0 else globals[parent] * local
	return globals


func _validate_fixture(skeleton: Skeleton3D) -> void:
	var profile := SkeletonProfileHumanoid.new()
	_check(skeleton != null, "target fixture contains a Skeleton3D")
	if skeleton == null:
		return
	_check(skeleton.name == "HumanoidSkeleton", "target fixture has a stable skeleton name")
	_check(skeleton.get_bone_count() == profile.get_bone_size(), "fixture has all 56 profile bones")
	for index in profile.get_bone_size():
		_check(skeleton.get_bone_name(index) == profile.get_bone_name(index), "profile name %d" % index)
		var expected_parent := -1
		if not profile.get_bone_parent(index).is_empty():
			expected_parent = skeleton.find_bone(profile.get_bone_parent(index))
		_check(skeleton.get_bone_parent(index) == expected_parent, "profile hierarchy %d" % index)
		_check(skeleton.get_bone_rest(index).is_finite(), "fixture rest %d is finite" % index)
	var hips := skeleton.find_bone("Hips")
	var left_arm := skeleton.find_bone("LeftUpperArm")
	_check(
		not skeleton.get_bone_rest(hips).is_equal_approx(profile.get_reference_pose(hips)),
		"fixture proportions differ from the profile reference",
	)
	_check(
		not skeleton.get_bone_rest(left_arm).basis.is_equal_approx(
			profile.get_reference_pose(left_arm).basis
		),
		"fixture upper arms differ from the profile T-pose",
	)
	var rests := _global_rests(skeleton)
	var left_shoulder := skeleton.find_bone("LeftShoulder")
	var left_hand := skeleton.find_bone("LeftHand")
	var right_shoulder := skeleton.find_bone("RightShoulder")
	var right_hand := skeleton.find_bone("RightHand")
	_check(rests[left_hand].origin.y < rests[left_shoulder].origin.y, "left arm visibly drops into A-pose")
	_check(rests[right_hand].origin.y < rests[right_shoulder].origin.y, "right arm visibly drops into A-pose")


func _validate_mapping(source: Skeleton3D, target: Skeleton3D) -> void:
	_check(Map.validate(source, target).is_empty(), "explicit SOMA-77 humanoid mapping validates")
	_check(Map.TARGET_TO_SOURCE.size() == 55, "all 55 humanoid profile targets are mapped")
	var source_names := {}
	for source_name in Map.TARGET_TO_SOURCE.values():
		_check(not source_names.has(source_name), "source mapping is one-to-one: %s" % source_name)
		source_names[source_name] = true
	_check(Map.COLLAPSED_SOURCE_JOINTS.size() == 9, "collapsed neck and palm joints are explicit")
	_check(Map.IGNORED_TERMINAL_JOINTS.size() == 13, "all terminal joints are explicit")
	_check(Map.source_dispositions().size() == 77, "all 77 SOMA joints have one disposition")
	_check(Map.source_for_target("LeftIndexProximal") == "LeftHandIndex2", "index palm joint is collapsed")
	_check(Map.source_for_target("RightThumbMetacarpal") == "RightHandThumb1", "thumb metacarpal is mapped")
	_check(Map.source_for_target("Jaw") == "Jaw", "facial rotation targets are mapped")
	_check(Map.ORIENTATION_FRAMES.size() == 2, "both hands have anatomical orientation frames")
	var degenerate := target.duplicate() as Skeleton3D
	var middle_index := degenerate.find_bone("LeftMiddleProximal")
	var middle_rest := degenerate.get_bone_rest(middle_index)
	middle_rest.origin = Vector3.ZERO
	degenerate.set_bone_rest(middle_index, middle_rest)
	_check(
		Map.validate(source, degenerate).contains("zero-length forward axis"),
		"a degenerate hand orientation frame is rejected clearly",
	)
	degenerate.free()


func _evaluate_engine_modifier(source: Skeleton3D) -> void:
	var modifier := RetargetModifier3D.new()
	modifier.profile = SkeletonProfileHumanoid.new()
	modifier.use_global_pose = false
	modifier.set_position_enabled(false)
	modifier.set_rotation_enabled(true)
	_check(modifier.profile is SkeletonProfileHumanoid, "Godot RetargetModifier3D accepts the humanoid profile")
	var direct_matches := 0
	for target_name in Map.REQUIRED_TARGETS:
		if source.find_bone(target_name) >= 0:
			direct_matches += 1
	_check(direct_matches < Map.REQUIRED_TARGETS.size(), "direct name matching cannot cover SOMA-77")
	_check(source.find_bone("LeftUpperArm") < 0, "modifier cannot infer LeftArm to LeftUpperArm")
	var has_bone_map_property := false
	for property in modifier.get_property_list():
		if property["name"] == "bone_map":
			has_bone_map_property = true
	_check(not has_bone_map_property, "RetargetModifier3D has no explicit BoneMap input")
	modifier.free()


func _validate_reloaded(
	fixture: Skeleton3D, skeleton: Skeleton3D, player: AnimationPlayer
) -> void:
	_check(skeleton != null, "saved target scene contains its skeleton")
	_check(player != null, "saved target scene contains its player")
	if skeleton == null or player == null:
		return
	_check(skeleton.get_bone_count() == 56, "saved target retains all profile bones")
	for index in fixture.get_bone_count():
		_check(skeleton.get_bone_name(index) == fixture.get_bone_name(index), "saved target name %d" % index)
		_check(skeleton.get_bone_rest(index).is_equal_approx(fixture.get_bone_rest(index)), "saved target rest %d" % index)
	var animation := player.get_animation("motion")
	_check(animation != null, "saved target has the stable motion name")
	if animation == null:
		return
	_check(
		animation.get_track_count() == 57,
		"saved target has 55 rotations plus root and hips translations",
	)
	_check(is_equal_approx(animation.length, 29.0 / 30.0), "saved target preserves duration")
	var animated_bones := {}
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		_check(path.get_name(0) == "HumanoidSkeleton", "track uses stable target node")
		animated_bones[path.get_subname(0)] = true
		for key in animation.track_get_key_count(track):
			var value: Variant = animation.track_get_key_value(track, key)
			_check(_variant_is_finite(value), "animation key is finite")
	for index in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(index)
		if bone_name != "Root" and not Map.TARGET_TO_SOURCE.has(String(bone_name)):
			_check(not animated_bones.has(bone_name), "unmapped bone %s remains untracked" % bone_name)


func _validate_motion(source_root: Node, target_root: Node) -> void:
	var source_skeleton := _find_first(source_root, "Skeleton3D") as Skeleton3D
	var source_player := _find_first(source_root, "AnimationPlayer") as AnimationPlayer
	var target_skeleton := _find_first(target_root, "Skeleton3D") as Skeleton3D
	var target_player := _find_first(target_root, "AnimationPlayer") as AnimationPlayer
	source_player.stop()
	source_player.play("motion")
	source_player.seek(SAMPLE_TIME, true)
	target_player.stop()
	target_player.play("motion")
	target_player.seek(SAMPLE_TIME, true)
	source_skeleton.force_update_all_bone_transforms()
	target_skeleton.force_update_all_bone_transforms()
	var source_rests := _global_rests(source_skeleton)
	var target_rests := _global_rests(target_skeleton)
	var non_commuting_bones := 0
	for target_name in Map.REQUIRED_TARGETS:
		var source_index := source_skeleton.find_bone(Map.source_for_target(target_name))
		var target_index := target_skeleton.find_bone(target_name)
		var source_delta := (
			source_skeleton.get_bone_global_pose(source_index).basis
			* source_rests[source_index].basis.inverse()
		)
		var corrected_rest := _direction_corrected_rest(
			target_name, source_skeleton, source_rests, target_skeleton, target_rests
		)
		var target_delta := (
			target_skeleton.get_bone_global_pose(target_index).basis
			* corrected_rest.inverse()
		)
		var error := source_delta.get_rotation_quaternion().angle_to(
			target_delta.get_rotation_quaternion()
		)
		_check(error <= ROTATION_TOLERANCE, "%s model-space rest delta %.9f" % [target_name, error])
		var old_order := source_delta * target_rests[target_index].basis
		var corrected_order := source_delta * corrected_rest
		if old_order.get_rotation_quaternion().angle_to(
			corrected_order.get_rotation_quaternion()
		) > 0.1:
			non_commuting_bones += 1
	_check(non_commuting_bones >= 4, "fixture exercises non-commuting rest rotations")
	_validate_segment_directions(source_skeleton, target_skeleton)
	_validate_hand_orientation_frames(source_skeleton, target_skeleton)

	var source_animation := source_player.get_animation("motion")
	var target_animation := target_player.get_animation("motion")
	var source_track := _find_track(source_animation, "Hips", Animation.TYPE_POSITION_3D)
	var root_track := _find_track(target_animation, "Root", Animation.TYPE_POSITION_3D)
	var hips_track := _find_track(target_animation, "Hips", Animation.TYPE_POSITION_3D)
	var source_delta: Vector3 = (
		source_animation.position_track_interpolate(source_track, source_animation.length)
		- source_animation.position_track_interpolate(source_track, 0.0)
	)
	var root_delta: Vector3 = (
		target_animation.position_track_interpolate(root_track, target_animation.length)
		- target_animation.position_track_interpolate(root_track, 0.0)
	)
	var hips_delta: Vector3 = (
		target_animation.position_track_interpolate(hips_track, target_animation.length)
		- target_animation.position_track_interpolate(hips_track, 0.0)
	)
	_check(
		Vector2(source_delta.x, source_delta.z).distance_to(Vector2(root_delta.x, root_delta.z))
		<= POSITION_TOLERANCE,
		"planar travel is preserved on Root",
	)
	_check(absf(root_delta.y) <= POSITION_TOLERANCE, "Root stays on its authored vertical plane")
	_check(absf(hips_delta.x) <= POSITION_TOLERANCE, "Hips has no local X travel")
	_check(absf(hips_delta.z) <= POSITION_TOLERANCE, "Hips has no local Z travel")
	_check(
		absf(source_delta.y - hips_delta.y) <= POSITION_TOLERANCE,
		"vertical pelvis travel is preserved on Hips",
	)
	_validate_root_hips_segment(target_skeleton, target_player, target_animation.length)


func _validate_root_hips_segment(
	skeleton: Skeleton3D, player: AnimationPlayer, animation_length: float
) -> void:
	var root_index := skeleton.find_bone("Root")
	var hips_index := skeleton.find_bone("Hips")
	for ratio in [0.0, 0.25, 0.5, 0.75, 1.0]:
		player.seek(animation_length * ratio, true)
		skeleton.force_update_all_bone_transforms()
		var root_position := skeleton.get_bone_global_pose(root_index).origin
		var hips_position := skeleton.get_bone_global_pose(hips_index).origin
		var offset := hips_position - root_position
		_check(
			Vector2(offset.x, offset.z).length() <= POSITION_TOLERANCE,
			"Root-to-Hips segment stays vertically aligned at %.2f" % ratio,
		)
		_check(offset.length() < 1.1, "Root-to-Hips segment stays bounded at %.2f" % ratio)


func _validate_hand_orientation_frames(
	source: Skeleton3D, target: Skeleton3D
) -> void:
	var source_rests := _global_rests(source)
	var target_rests := _global_rests(target)
	for target_name in Map.ORIENTATION_FRAMES:
		var frame: Dictionary = Map.orientation_frame_for_target(target_name)
		var source_frame := RestOrientation.anatomical_frame(
			source,
			source_rests,
			Map.source_for_target(target_name),
			Map.source_for_target(frame["forward"]),
			Map.source_for_target(frame["lateral_from"]),
			Map.source_for_target(frame["lateral_to"]),
		)
		var target_frame := RestOrientation.anatomical_frame(
			target,
			target_rests,
			target_name,
			frame["forward"],
			frame["lateral_from"],
			frame["lateral_to"],
		)
		var source_index := source.find_bone(Map.source_for_target(target_name))
		var target_index := target.find_bone(target_name)
		var source_motion := (
			source.get_bone_global_pose(source_index).basis
			* source_rests[source_index].basis.inverse()
		)
		var target_motion := (
			target.get_bone_global_pose(target_index).basis
			* target_rests[target_index].basis.inverse()
		)
		var source_animated: Basis = source_motion * source_frame["basis"]
		var target_animated: Basis = target_motion * target_frame["basis"]
		_check(
			source_animated.get_rotation_quaternion().angle_to(
				target_animated.get_rotation_quaternion()
			) <= ROTATION_TOLERANCE,
			"%s preserves its full anatomical hand frame" % target_name,
		)


func _validate_dependency_closure(path: String) -> void:
	var pending: Array[String] = [path]
	var visited := {}
	while not pending.is_empty():
		var current: String = pending.pop_back()
		if visited.has(current):
			continue
		visited[current] = true
		_check(not current.contains("addons/"), "saved target closure excludes addon code")
		_check(not current.ends_with(".gltf"), "saved target closure excludes source glTF")
		for dependency in ResourceLoader.get_dependencies(current):
			var dependency_path := String(dependency)
			if dependency_path.contains("::"):
				dependency_path = dependency_path.get_slice("::", 2)
			pending.append(dependency_path)
	_check(visited.size() == 2, "saved target closure contains scene and AnimationLibrary only")


func _find_track(animation: Animation, bone_name: String, type: Animation.TrackType) -> int:
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		if animation.track_get_type(track) == type and path.get_subname(0) == bone_name:
			return track
	return -1


func _global_rests(skeleton: Skeleton3D) -> Array[Transform3D]:
	var rests: Array[Transform3D] = []
	rests.resize(skeleton.get_bone_count())
	for index in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(index)
		rests[index] = skeleton.get_bone_rest(index)
		if parent >= 0:
			rests[index] = rests[parent] * rests[index]
	return rests


func _direction_corrected_rest(
	target_name: StringName,
	source: Skeleton3D,
	source_rests: Array[Transform3D],
	target: Skeleton3D,
	target_rests: Array[Transform3D],
) -> Basis:
	var target_index := target.find_bone(target_name)
	var frame: Dictionary = Map.orientation_frame_for_target(target_name)
	if not frame.is_empty():
		var source_frame := RestOrientation.anatomical_frame(
			source,
			source_rests,
			Map.source_for_target(target_name),
			Map.source_for_target(frame["forward"]),
			Map.source_for_target(frame["lateral_from"]),
			Map.source_for_target(frame["lateral_to"]),
		)
		var target_frame := RestOrientation.anatomical_frame(
			target,
			target_rests,
			target_name,
			frame["forward"],
			frame["lateral_from"],
			frame["lateral_to"],
		)
		return (
			source_frame["basis"]
			* target_frame["basis"].inverse()
			* target_rests[target_index].basis
		)
	var child_name := Map.direction_child_for_target(target_name)
	if child_name.is_empty():
		return target_rests[target_index].basis
	var source_index := source.find_bone(Map.source_for_target(target_name))
	var source_child := source.find_bone(Map.source_direction_child_for_target(target_name))
	var target_child := target.find_bone(child_name)
	var source_direction := source_rests[source_index].origin.direction_to(
		source_rests[source_child].origin
	)
	var target_direction := target_rests[target_index].origin.direction_to(
		target_rests[target_child].origin
	)
	return Basis(Quaternion(target_direction, source_direction)) * target_rests[target_index].basis


func _validate_segment_directions(source: Skeleton3D, target: Skeleton3D) -> void:
	for target_name in Map.DIRECTION_CHILDREN:
		var child_name: StringName = Map.direction_child_for_target(target_name)
		var source_parent := source.find_bone(Map.source_for_target(target_name))
		var source_child := source.find_bone(Map.source_direction_child_for_target(target_name))
		var target_parent := target.find_bone(target_name)
		var target_child := target.find_bone(child_name)
		var source_direction := source.get_bone_global_pose(source_parent).origin.direction_to(
			source.get_bone_global_pose(source_child).origin
		)
		var target_direction := target.get_bone_global_pose(target_parent).origin.direction_to(
			target.get_bone_global_pose(target_child).origin
		)
		_check(
			source_direction.angle_to(target_direction) <= ROTATION_TOLERANCE,
			"%s segment direction matches source" % target_name,
		)


func _variant_is_finite(value: Variant) -> bool:
	if value is Vector3:
		return value.is_finite()
	if value is Quaternion:
		return value.is_finite()
	return false


func _sha256(data: PackedByteArray) -> PackedByteArray:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(data)
	return hashing.finish()


func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null


func _remove_test_directory(directory: String) -> void:
	var absolute := ProjectSettings.globalize_path(directory)
	var access := DirAccess.open(absolute)
	if access == null:
		return
	for file_name in access.get_files():
		DirAccess.remove_absolute(absolute.path_join(file_name))
	DirAccess.remove_absolute(absolute)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: humanoid retarget is rest-aware, non-destructive, and reload-stable")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)

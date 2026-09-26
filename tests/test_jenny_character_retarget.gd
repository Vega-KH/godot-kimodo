extends SceneTree

const Baker := preload(
	"res://addons/kimodo_motion/retargeting/humanoid_character_baker.gd"
)
const HumanoidMap := preload(
	"res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd"
)
const RigProfile := preload(
	"res://addons/kimodo_motion/retargeting/humanoid_rig_profile.gd"
)
const RestOrientation := preload(
	"res://addons/kimodo_motion/retargeting/rest_orientation.gd"
)
const SOURCE_SCENE := preload(
	"res://tests/retargeting/generated/soma77_walk_humanoid.tscn"
)
const JENNY_SCENE := preload("res://tests/characters/fixtures/Jenny03.glb")
const JENNY_PATH := "res://tests/characters/fixtures/Jenny03.glb"
const JENNY_SHA256 := "cea2da0dead498499b0433322d9aba04681da24e587d3e2a15004acfe2afeae9"
const ROTATION_TOLERANCE := 0.001
const INTERPOLATED_ROTATION_TOLERANCE := 0.006
const DIGIT_LOCAL_ANGLE_TOLERANCE := deg_to_rad(6.0)
const POSITION_TOLERANCE := 0.000001
const SAMPLE_TIMES := [0.0, 0.25, 0.5, 29.0 / 30.0]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(FileAccess.get_sha256(JENNY_PATH) == JENNY_SHA256, "Jenny fixture hash is stable")
	var source := SOURCE_SCENE.instantiate()
	var character := JENNY_SCENE.instantiate() as Node3D
	root.add_child(source)
	root.add_child(character)
	var source_skeleton := _find_first(source, "Skeleton3D") as Skeleton3D
	var source_player := _find_first(source, "AnimationPlayer") as AnimationPlayer
	source_player.play("motion")
	var target_skeleton := _find_first(character, "Skeleton3D") as Skeleton3D
	var profile_result := RigProfile.exact_names(
		target_skeleton, character.get_path_to(target_skeleton)
	)
	var rig_profile: RefCounted = profile_result["profile"] if profile_result["ok"] else null
	_check(profile_result["ok"], "Jenny builds an explicit exact-name rig profile")
	var target_rests := _bone_rests(target_skeleton)
	var mesh_summary := _mesh_summary(character)
	_check(target_skeleton.get_bone_count() == 61, "root-bearing Jenny has 61 bones")
	_check(target_skeleton.get_bone_name(0) == "Root", "Jenny uses a dedicated Root")
	_check(target_skeleton.get_bone_parent(0) == -1, "Jenny Root owns the hierarchy")
	_check(mesh_summary["meshes"] == 8, "Jenny retains eight skinned meshes")
	_check(mesh_summary["triangles"] == 37270, "Jenny triangle count is recorded")
	_check(mesh_summary["max_skin_binds"] == 61, "Jenny skin binds all 61 bones")
	_check(
		Baker.validate(source_skeleton, source_player, target_skeleton).is_empty(),
		"Jenny satisfies the humanoid character contract",
	)
	_check(Baker.validate_target(character).is_empty(), "Jenny satisfies target-scene validation")
	var multiple_skeletons := JENNY_SCENE.instantiate() as Node3D
	multiple_skeletons.add_child(Skeleton3D.new())
	_check(
		Baker.validate_target(multiple_skeletons).contains("exactly one Skeleton3D"),
		"multiple target skeletons are rejected",
	)
	multiple_skeletons.free()
	var no_skin := SOURCE_SCENE.instantiate()
	_check(
		Baker.validate_target(no_skin).contains("skinned MeshInstance3D"),
		"a target without skin bindings is rejected",
	)
	no_skin.free()
	var non_finite := JENNY_SCENE.instantiate() as Node3D
	var non_finite_skeleton := _find_first(non_finite, "Skeleton3D") as Skeleton3D
	var invalid_rest := non_finite_skeleton.get_bone_rest(0)
	invalid_rest.origin.x = NAN
	non_finite_skeleton.set_bone_rest(0, invalid_rest)
	_check(
		Baker.validate_target(non_finite).contains("non-finite rest"),
		"a non-finite target rest is rejected",
	)
	non_finite.free()
	var reserved_player := JENNY_SCENE.instantiate() as Node3D
	var conflict := AnimationPlayer.new()
	conflict.name = Baker.PLAYER_NODE_NAME
	reserved_player.add_child(conflict)
	_check(
		Baker.validate_target(reserved_player).contains("reserved"),
		"reserved animation ownership is rejected",
	)
	reserved_player.free()
	var extra_bone_character := JENNY_SCENE.instantiate() as Node3D
	var extra_bone_skeleton := _find_first(
		extra_bone_character, "Skeleton3D"
	) as Skeleton3D
	var ponytail_index := extra_bone_skeleton.get_bone_count()
	extra_bone_skeleton.add_bone("PonytailTest")
	extra_bone_skeleton.set_bone_parent(
		ponytail_index, extra_bone_skeleton.find_bone("Head")
	)
	var ponytail_rest := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, -0.08))
	extra_bone_skeleton.set_bone_rest(ponytail_index, ponytail_rest)
	extra_bone_skeleton.set_bone_pose(ponytail_index, ponytail_rest)
	_check(
		Baker.validate_target(extra_bone_character).is_empty(),
		"an unmapped ponytail bone is accepted as an extra rig branch",
	)
	var extra_bone_motion: RefCounted = Baker.create_motion(source, extra_bone_character)
	_check(extra_bone_motion != null, "a character with an extra ponytail bone retargets")
	if extra_bone_motion != null:
		var extra_animation: Animation = extra_bone_motion.player.get_animation("motion")
		_check(
			_find_track(extra_animation, "PonytailTest", Animation.TYPE_ROTATION_3D) < 0,
			"the unmapped ponytail bone receives no authored track",
		)
		extra_bone_motion.player.seek(0.5, true)
		var head_index := extra_bone_skeleton.find_bone("Head")
		var inherited_pose := (
			extra_bone_skeleton.get_bone_global_pose(head_index)
			* extra_bone_skeleton.get_bone_rest(ponytail_index)
		)
		_check(
			extra_bone_skeleton.get_bone_global_pose(ponytail_index).is_equal_approx(
				inherited_pose
			),
			"the unmapped ponytail bone inherits animated head motion",
		)
		extra_bone_motion.scene.free()
	var renamed_character := JENNY_SCENE.instantiate() as Node3D
	var renamed_skeleton := _find_first(renamed_character, "Skeleton3D") as Skeleton3D
	var renamed_index := renamed_skeleton.find_bone("LeftHand")
	renamed_skeleton.set_bone_name(renamed_index, "CustomLeftHand")
	var renamed_mapping: Dictionary = rig_profile.canonical_to_target.duplicate(true)
	renamed_mapping["LeftHand"] = "CustomLeftHand"
	var renamed_profile_result := RigProfile.create(
		renamed_mapping,
		renamed_character.get_path_to(renamed_skeleton),
		renamed_skeleton,
	)
	_check(renamed_profile_result["ok"], "a profile can map canonical semantics to renamed bones")
	var renamed_motion: RefCounted = Baker.create_motion(
		source, renamed_character, renamed_profile_result["profile"]
	)
	_check(renamed_motion != null, "retargeting accepts a non-Jenny-specific bone mapping")
	if renamed_motion != null:
		_check(
			_find_track(
				renamed_motion.player.get_animation("motion"),
				"CustomLeftHand",
				Animation.TYPE_ROTATION_3D,
			) >= 0,
			"renamed target receives the canonical LeftHand animation",
		)
		renamed_motion.scene.free()

	var motion: RefCounted = Baker.create_motion(source, character)
	_check(motion != null, "humanoid motion retargets to the skinned character")
	if motion == null:
		_finish()
		return
	var target_player: AnimationPlayer = motion.player
	var animation := target_player.get_animation("motion")
	_check(animation.get_track_count() == 54, "character motion has 52 rotations plus root and hips tracks")
	_check(is_equal_approx(animation.length, 29.0 / 30.0), "character duration is preserved")
	_check(_bone_rests(target_skeleton) == target_rests, "retargeting preserves Jenny rest data")
	_check(_mesh_summary(character) == mesh_summary, "retargeting preserves mesh and skin data")
	_validate_tracks(animation, character.get_path_to(target_skeleton), rig_profile)
	_validate_model_space_deltas(
		source_skeleton, source_player, target_skeleton, target_player, rig_profile
	)
	_validate_root_motion(source_player, target_player)

	var invalid_skeleton := Skeleton3D.new()
	invalid_skeleton.add_bone("Hips")
	var validation_error := Baker.validate(source_skeleton, source_player, invalid_skeleton)
	_check(validation_error.contains("Root"), "a target without Root is rejected clearly")
	invalid_skeleton.free()

	var directory := "res://tests/.goal11_%d_%d" % [
		OS.get_process_id(), Time.get_ticks_usec()
	]
	var first := Baker.save_motion(character, directory, "jenny walk")
	var second := Baker.save_motion(character, directory, "jenny walk")
	_check(not first.is_empty(), "character scene saves")
	_check(first["scene_path"].ends_with("jenny walk.tscn"), "first save uses requested name")
	_check(second["scene_path"].ends_with("jenny walk_2.tscn"), "second save is unique")
	_check(FileAccess.get_sha256(JENNY_PATH) == JENNY_SHA256, "saving does not modify Jenny GLB")
	var packed := ResourceLoader.load(
		first["scene_path"], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	var reloaded := packed.instantiate()
	root.add_child(reloaded)
	var reloaded_skeleton := _find_first(reloaded, "Skeleton3D") as Skeleton3D
	var reloaded_player := reloaded.get_node(Baker.PLAYER_NODE_NAME) as AnimationPlayer
	_check(reloaded_skeleton.get_bone_count() == 61, "saved character reloads its skeleton")
	_check(_mesh_summary(reloaded) == mesh_summary, "saved character reloads meshes and skins")
	_compare_animations(animation, reloaded_player.get_animation("motion"))
	var dependencies := ResourceLoader.get_dependencies(first["scene_path"])
	_check(dependencies.is_empty(), "saved character scene is self-contained")

	reloaded.queue_free()
	source.queue_free()
	character.queue_free()
	await process_frame
	_remove_test_directory(directory)
	_check(root.get_child_count() == 0, "character test leaves no nodes behind")
	_finish()


func _validate_tracks(
	animation: Animation, skeleton_path: NodePath, rig_profile: RefCounted
) -> void:
	var required: Array[StringName] = rig_profile.rotation_targets()
	required.append_array(["Root", "Hips"])
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		_check(
			String(path.get_concatenated_names()) == String(skeleton_path),
			"track targets Jenny Skeleton3D",
		)
		_check(path.get_subname_count() == 1, "track has one bone subname")
		_check(String(path.get_subname(0)) in required, "track targets an explicit mapped bone")
		for key in animation.track_get_key_count(track):
			var value: Variant = animation.track_get_key_value(track, key)
			if value is Quaternion:
				_check(value.is_finite(), "rotation key is finite")
			else:
				_check(value.is_finite(), "position key is finite")
	for twist_name in [
		"LeftUpperArm_twist_01", "LeftLowerArm_twist_01",
		"RightUpperArm_twist_01", "RightLowerArm_twist_01",
		"LeftUpperLeg_twist_01", "LeftLowerLeg_twist_01",
		"RightUpperLeg_twist_01", "RightLowerLeg_twist_01",
	]:
		_check(
			_find_track(animation, twist_name, Animation.TYPE_ROTATION_3D) < 0,
			"%s remains inherited from its parent" % twist_name,
		)


func _validate_model_space_deltas(
	source_skeleton: Skeleton3D,
	source_player: AnimationPlayer,
	target_skeleton: Skeleton3D,
	target_player: AnimationPlayer,
	rig_profile: RefCounted,
) -> void:
	var source_rests := _global_rests(source_skeleton)
	var target_rests := _global_rests(target_skeleton)
	var non_commuting_bones := 0
	for time in SAMPLE_TIMES:
		source_player.seek(time, true)
		target_player.seek(time, true)
		for bone_name in rig_profile.rotation_targets():
			var source_index := source_skeleton.find_bone(bone_name)
			var target_index := target_skeleton.find_bone(bone_name)
			var source_delta := (
				source_skeleton.get_bone_global_pose(source_index).basis
				* source_rests[source_index].basis.inverse()
			)
			var corrected_rest := _direction_corrected_rest(
				bone_name, source_skeleton, source_rests, target_skeleton, target_rests
			)
			var target_delta := (
				target_skeleton.get_bone_global_pose(target_index).basis
				* corrected_rest.inverse()
			)
			var angle := source_delta.get_rotation_quaternion().angle_to(
				target_delta.get_rotation_quaternion()
			)
			var tolerance := (
				ROTATION_TOLERANCE
				if is_equal_approx(time * 30.0, roundf(time * 30.0))
				else INTERPOLATED_ROTATION_TOLERANCE
			)
			_check(
				angle <= tolerance,
				"%s rest delta matches at %.3f (%.9f)" % [bone_name, time, angle],
			)
			if is_zero_approx(time):
				var old_order := source_delta * target_rests[target_index].basis
				var corrected_order := source_delta * corrected_rest
				if old_order.get_rotation_quaternion().angle_to(
					corrected_order.get_rotation_quaternion()
				) > 0.1:
					non_commuting_bones += 1
	_check(non_commuting_bones >= 4, "Jenny exercises non-commuting rest rotations")
	_validate_segment_directions(source_skeleton, source_player, target_skeleton, target_player)
	_validate_hand_orientation_frames(
		source_skeleton, source_player, target_skeleton, target_player, rig_profile
	)
	_validate_digit_local_rotation_magnitudes(
		source_skeleton, source_player, target_skeleton, target_player, rig_profile
	)


func _validate_root_motion(source_player: AnimationPlayer, target_player: AnimationPlayer) -> void:
	var source := source_player.get_animation("motion")
	var target := target_player.get_animation("motion")
	var source_root := _find_track(source, "Root", Animation.TYPE_POSITION_3D)
	var target_root := _find_track(target, "Root", Animation.TYPE_POSITION_3D)
	var source_delta: Vector3 = (
		source.position_track_interpolate(source_root, source.length)
		- source.position_track_interpolate(source_root, 0.0)
	)
	var target_delta: Vector3 = (
		target.position_track_interpolate(target_root, target.length)
		- target.position_track_interpolate(target_root, 0.0)
	)
	_check(source_delta.distance_to(target_delta) <= POSITION_TOLERANCE, "root travel is preserved")


func _compare_animations(source: Animation, saved: Animation) -> void:
	var saved_tracks := {}
	for track in saved.get_track_count():
		saved_tracks[_track_key(saved, track)] = track
	for source_track in source.get_track_count():
		var key := _track_key(source, source_track)
		_check(saved_tracks.has(key), "reloaded animation retains %s" % key)
		if not saved_tracks.has(key):
			continue
		for time in SAMPLE_TIMES:
			var before: Variant = _sample(source, source_track, time)
			var after: Variant = _sample(saved, saved_tracks[key], time)
			if before is Quaternion:
				_check(
					before.normalized().angle_to(after.normalized()) <= ROTATION_TOLERANCE,
					"%s reload rotation matches" % key,
				)
			else:
				_check(
					before.distance_to(after) <= POSITION_TOLERANCE,
					"%s reload position matches" % key,
				)


func _mesh_summary(node: Node) -> Dictionary:
	var result := {"meshes": 0, "triangles": 0, "max_skin_binds": 0}
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := found as MeshInstance3D
		result["meshes"] += 1
		if mesh_instance.skin != null:
			result["max_skin_binds"] = maxi(
				result["max_skin_binds"], mesh_instance.skin.get_bind_count()
			)
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			result["triangles"] += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return result


func _bone_rests(skeleton: Skeleton3D) -> Array[Transform3D]:
	var rests: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		rests.append(skeleton.get_bone_rest(index))
	return rests


func _global_rests(skeleton: Skeleton3D) -> Array[Transform3D]:
	var rests: Array[Transform3D] = []
	rests.resize(skeleton.get_bone_count())
	for index in skeleton.get_bone_count():
		var local := skeleton.get_bone_rest(index)
		var parent := skeleton.get_bone_parent(index)
		rests[index] = local if parent < 0 else rests[parent] * local
	return rests


func _direction_corrected_rest(
	bone_name: StringName,
	source: Skeleton3D,
	source_rests: Array[Transform3D],
	target: Skeleton3D,
	target_rests: Array[Transform3D],
) -> Basis:
	var source_index := source.find_bone(bone_name)
	var target_index := target.find_bone(bone_name)
	var frame_owner := HumanoidMap.orientation_frame_owner_for_target(bone_name)
	var frame: Dictionary = HumanoidMap.orientation_frame_for_target(frame_owner)
	if not frame.is_empty():
		var source_frame := RestOrientation.anatomical_frame(
			source,
			source_rests,
			frame_owner,
			frame["forward"],
			frame["lateral_from"],
			frame["lateral_to"],
		)
		var target_frame := RestOrientation.anatomical_frame(
			target,
			target_rests,
			frame_owner,
			frame["forward"],
			frame["lateral_from"],
			frame["lateral_to"],
		)
		return (
			source_frame["basis"]
			* target_frame["basis"].inverse()
			* target_rests[target_index].basis
		)
	var child_name := HumanoidMap.direction_child_for_target(bone_name)
	if child_name.is_empty():
		return target_rests[target_index].basis
	var source_child := source.find_bone(child_name)
	var target_child := target.find_bone(child_name)
	var source_direction := source_rests[source_index].origin.direction_to(
		source_rests[source_child].origin
	)
	var target_direction := target_rests[target_index].origin.direction_to(
		target_rests[target_child].origin
	)
	return Basis(Quaternion(target_direction, source_direction)) * target_rests[target_index].basis


func _validate_segment_directions(
	source: Skeleton3D,
	source_player: AnimationPlayer,
	target: Skeleton3D,
	target_player: AnimationPlayer,
) -> void:
	for time in SAMPLE_TIMES:
		source_player.seek(time, true)
		target_player.seek(time, true)
		for bone_name in HumanoidMap.DIRECTION_CHILDREN:
			if not HumanoidMap.orientation_frame_owner_for_target(bone_name).is_empty():
				continue
			var child_name: StringName = HumanoidMap.direction_child_for_target(bone_name)
			var source_parent := source.find_bone(bone_name)
			var source_child := source.find_bone(child_name)
			var target_parent := target.find_bone(bone_name)
			var target_child := target.find_bone(child_name)
			var source_direction := source.get_bone_global_pose(source_parent).origin.direction_to(
				source.get_bone_global_pose(source_child).origin
			)
			var target_direction := target.get_bone_global_pose(target_parent).origin.direction_to(
				target.get_bone_global_pose(target_child).origin
			)
			_check(
				source_direction.angle_to(target_direction) <= INTERPOLATED_ROTATION_TOLERANCE,
				"%s segment direction matches at %.3f" % [bone_name, time],
			)


func _validate_hand_orientation_frames(
	source: Skeleton3D,
	source_player: AnimationPlayer,
	target: Skeleton3D,
	target_player: AnimationPlayer,
	rig_profile: RefCounted,
) -> void:
	var source_rests := _global_rests(source)
	var target_rests := _global_rests(target)
	for time in SAMPLE_TIMES:
		source_player.seek(time, true)
		target_player.seek(time, true)
		for canonical_name in HumanoidMap.ORIENTATION_FRAMES:
			var frame: Dictionary = HumanoidMap.orientation_frame_for_target(canonical_name)
			var source_frame := RestOrientation.anatomical_frame(
				source,
				source_rests,
				canonical_name,
				frame["forward"],
				frame["lateral_from"],
				frame["lateral_to"],
			)
			var target_frame := RestOrientation.anatomical_frame(
				target,
				target_rests,
				rig_profile.target_for(canonical_name),
				rig_profile.target_for(frame["forward"]),
				rig_profile.target_for(frame["lateral_from"]),
				rig_profile.target_for(frame["lateral_to"]),
			)
			var source_index := source.find_bone(canonical_name)
			var target_index := target.find_bone(rig_profile.target_for(canonical_name))
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
				) <= INTERPOLATED_ROTATION_TOLERANCE,
				"%s anatomical frame matches at %.3f" % [canonical_name, time],
			)


func _validate_digit_local_rotation_magnitudes(
	source: Skeleton3D,
	source_player: AnimationPlayer,
	target: Skeleton3D,
	target_player: AnimationPlayer,
	rig_profile: RefCounted,
) -> void:
	for time in SAMPLE_TIMES:
		source_player.seek(time, true)
		target_player.seek(time, true)
		for canonical_name in HumanoidMap.ORIENTATION_FRAME_OWNERS:
			if canonical_name in HumanoidMap.ORIENTATION_FRAMES:
				continue
			var source_index := source.find_bone(canonical_name)
			var target_index := target.find_bone(rig_profile.target_for(canonical_name))
			var source_angle := source.get_bone_pose(source_index).basis.get_rotation_quaternion().angle_to(
				source.get_bone_rest(source_index).basis.get_rotation_quaternion()
			)
			var target_angle := target.get_bone_pose(target_index).basis.get_rotation_quaternion().angle_to(
				target.get_bone_rest(target_index).basis.get_rotation_quaternion()
			)
			_check(
				absf(source_angle - target_angle) <= DIGIT_LOCAL_ANGLE_TOLERANCE,
				"%s avoids local compensation at %.3f (source %.3f, target %.3f)"
				% [canonical_name, time, rad_to_deg(source_angle), rad_to_deg(target_angle)],
			)


func _find_track(animation: Animation, bone_name: String, type: Animation.TrackType) -> int:
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		if (
			animation.track_get_type(track) == type
			and path.get_subname_count() == 1
			and path.get_subname(0) == bone_name
		):
			return track
	return -1


func _track_key(animation: Animation, track: int) -> String:
	return "%d:%s" % [animation.track_get_type(track), animation.track_get_path(track)]


func _sample(animation: Animation, track: int, time: float) -> Variant:
	if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
		return animation.rotation_track_interpolate(track, time)
	return animation.position_track_interpolate(track, time)


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
		print("PASS: Jenny skin, rest-delta retarget, root travel, save, and reload")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)

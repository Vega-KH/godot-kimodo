extends SceneTree

const Fixture := preload("res://addons/kimodo_motion/retargeting/humanoid_fixture.gd")
const Matcher := preload("res://addons/kimodo_motion/retargeting/rig_candidate_matcher.gd")
const Profile := preload("res://addons/kimodo_motion/retargeting/kimodo_rig_profile.gd")
const Store := preload("res://addons/kimodo_motion/retargeting/rig_profile_store.gd")
const SessionStore := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const Baker := preload("res://addons/kimodo_motion/retargeting/humanoid_character_baker.gd")
const RestOrientation := preload("res://addons/kimodo_motion/retargeting/rest_orientation.gd")
const HumanoidMap := preload("res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd")
const HUMANOID_MOTION := preload("res://tests/retargeting/generated/soma77_walk_humanoid.tscn")

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var skeleton := _mixamo_skeleton()
	var first := Matcher.suggest(skeleton)
	var second := Matcher.suggest(skeleton)
	_check(first == second, "candidate generation is deterministic")
	_check(first["root_motion_policy"] == Profile.ROOT_HIPS_ONLY, "root Hips is represented by an explicit policy")
	var rows: Dictionary = first["rows"]
	_check(rows["LeftUpperArm"]["target"] == "mixamorig_LeftArm", "curated arm alias is transparent")
	_check(rows["LeftLittleDistal"]["target"] == "mixamorig_LeftHandPinky3", "five-digit Mixamo chain maps completely")
	_check(rows["LeftUpperArm"]["evidence"].contains("Mixamo"), "mapping row records its evidence")
	var mapping := Matcher.mapping_from_rows(rows)
	mapping.erase("Jaw")
	_check(Matcher.diagnose(skeleton, mapping, first["root_motion_policy"]).is_empty(), "complete Mixamo mapping certifies")
	var created := Profile.create(mapping, NodePath("Skeleton3D"), skeleton, first["root_motion_policy"], "leg_height")
	_check(created["ok"], "profile is created from reviewed rows")
	var profile: Resource = created.get("profile")
	_check(profile.ignored_optional_roles.has("Jaw"), "profile records intentionally unmapped optional anatomy")
	var signature := SessionStore.skeleton_signature(skeleton)
	_check(profile.certify(skeleton, signature)["ok"], "reviewed profile certifies")
	_check(profile.is_current(skeleton, signature), "certified exact signature is reusable")

	var path := "res://tests/.goal18_profile_%d.tres" % OS.get_process_id()
	var saved := Store.save(profile, path)
	_check(saved["ok"], "profile saves atomically inside the project")
	var loaded := Store.load_current(path, skeleton, signature)
	_check(loaded["ok"], "profile reopens for its exact skeleton signature")
	if loaded["ok"]:
		_check(loaded["profile"].canonical_to_target == mapping, "profile mapping round-trips exactly")
	var stale := Store.load_current(path, skeleton, "changed-signature")
	_check(not stale["ok"] and stale["code"] == "stale_profile", "changed skeleton signature rejects profile reuse")

	var conflicted := mapping.duplicate(true)
	conflicted["RightHand"] = conflicted["LeftHand"]
	_check(not Matcher.diagnose(skeleton, conflicted, Profile.ROOT_HIPS_ONLY).is_empty(), "duplicate target is rejected")
	var wrong_side := mapping.duplicate(true)
	wrong_side["LeftUpperArm"] = "mixamorig_RightArm"
	wrong_side.erase("RightUpperArm")
	_check(_contains(Matcher.diagnose(skeleton, wrong_side, Profile.ROOT_HIPS_ONLY), "wrong side"), "wrong-side assignment is diagnosed")

	if FileAccess.file_exists("res://tests/private_models/Remy-with-taunt-animation.fbx"):
		_validate_private_remy()
	else:
		print("SKIP: private Remy fixture is not present (expected in clean checkouts)")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	skeleton.free()
	_finish()

func _mixamo_skeleton() -> Skeleton3D:
	var source := Fixture.create_skeleton()
	var target := Skeleton3D.new()
	target.name = "Skeleton3D"
	var remap := {}
	for old_index in source.get_bone_count():
		var canonical := String(source.get_bone_name(old_index))
		if canonical == "Root":
			continue
		var index := target.get_bone_count()
		target.add_bone(_mixamo_name(canonical))
		remap[old_index] = index
		var rest := source.get_bone_rest(old_index)
		if canonical == "Hips":
			rest = source.get_bone_rest(source.find_bone("Root")) * rest
		target.set_bone_rest(index, rest)
	for old_index in remap:
		var parent := source.get_bone_parent(old_index)
		if remap.has(parent):
			target.set_bone_parent(remap[old_index], remap[parent])
	source.free()
	return target

func _mixamo_name(role: String) -> String:
	var aliases := {
		"Hips":"Hips", "Spine":"Spine", "Chest":"Spine1", "UpperChest":"Spine2", "Neck":"Neck", "Head":"Head", "LeftEye":"LeftEye", "RightEye":"RightEye", "Jaw":"Jaw",
		"LeftShoulder":"LeftShoulder", "LeftUpperArm":"LeftArm", "LeftLowerArm":"LeftForeArm", "LeftHand":"LeftHand", "RightShoulder":"RightShoulder", "RightUpperArm":"RightArm", "RightLowerArm":"RightForeArm", "RightHand":"RightHand",
		"LeftUpperLeg":"LeftUpLeg", "LeftLowerLeg":"LeftLeg", "LeftFoot":"LeftFoot", "LeftToes":"LeftToeBase", "RightUpperLeg":"RightUpLeg", "RightLowerLeg":"RightLeg", "RightFoot":"RightFoot", "RightToes":"RightToeBase",
	}
	if aliases.has(role):
		return "mixamorig_" + aliases[role]
	for side in ["Left", "Right"]:
		for digit in ["Thumb", "Index", "Middle", "Ring", "Little"]:
			var joints := ["Metacarpal", "Proximal", "Distal"] if digit == "Thumb" else ["Proximal", "Intermediate", "Distal"]
			var offset := role.trim_prefix(side + digit)
			var joint := joints.find(offset)
			if joint >= 0:
				return "mixamorig_%sHand%s%d" % [side, "Pinky" if digit == "Little" else digit, joint + 1]
	return "mixamorig_" + role

func _validate_private_remy() -> void:
	var packed := ResourceLoader.load("res://tests/private_models/Remy-with-taunt-animation.fbx", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_check(packed != null, "private Remy fixture imports as a PackedScene")
	if packed == null:
		return
	var instance := packed.instantiate()
	var skeleton := _find_first(instance, "Skeleton3D") as Skeleton3D
	var player := _find_first(instance, "AnimationPlayer") as AnimationPlayer
	var names := player.get_animation_list() if player != null else PackedStringArray()
	var current: String = player.current_animation if player != null else ""
	var suggested := Matcher.suggest(skeleton)
	var mapping := Matcher.mapping_from_rows(suggested["rows"])
	_check(skeleton.get_bone_count() == 67, "private Remy import retains its 67-bone rig")
	_check(names.has("Take 001") and names.has("mixamo_com"), "private Remy bundled animations remain present")
	_check(Matcher.diagnose(skeleton, mapping, suggested["root_motion_policy"]).is_empty(), "private Remy suggestions certify without a model-specific override")
	var created := Profile.create(mapping, instance.get_path_to(skeleton), skeleton, suggested["root_motion_policy"], "leg_height")
	_check(created["ok"], "private Remy profile is created")
	if created["ok"]:
		var profile: Resource = created["profile"]
		profile.certify(skeleton, SessionStore.skeleton_signature(skeleton))
		var source := HUMANOID_MOTION.instantiate()
		root.add_child(source)
		root.add_child(instance)
		var motion: RefCounted = Baker.create_motion(source, instance, profile)
		_check(motion != null, "private Remy receives profile-driven Kimodo motion")
		if motion != null:
			var animation: Animation = motion.player.get_animation("motion")
			_check(animation.get_track_count() == profile.rotation_targets().size() + 1, "Hips-is-root emits one position track without an invented Root")
			var hips_positions := 0
			for track in animation.get_track_count():
				var path := String(animation.track_get_path(track))
				if animation.track_get_type(track) == Animation.TYPE_POSITION_3D and path.ends_with(":" + String(profile.target_for("Hips"))):
					hips_positions += 1
				_check(not path.ends_with(":Root"), "private Remy animation contains no invented Root track")
			_check(hips_positions == 1, "private Remy root travel has one owner")
			_validate_motion_numbers(source, motion, profile)
		_check(player.get_animation_list() == names and player.current_animation == current, "private Remy bundled animations remain unmodified and unplayed")
		source.free()
	if is_instance_valid(instance):
		instance.free()

func _validate_motion_numbers(source: Node3D, motion: RefCounted, profile: Resource) -> void:
	var source_skeleton := _find_first(source, "Skeleton3D") as Skeleton3D
	var source_player := _find_first(source, "AnimationPlayer") as AnimationPlayer
	var target_skeleton: Skeleton3D = motion.skeleton
	var target_player: AnimationPlayer = motion.player
	var end_time := 29.0 / 30.0
	source_player.play("motion")
	target_player.play("motion")
	source_player.seek(0.0, true)
	target_player.seek(0.0, true)
	var source_start := _bone_origin(source_skeleton, "Hips")
	var target_start := _bone_origin(target_skeleton, profile.target_for("Hips"))
	source_player.seek(end_time, true)
	target_player.seek(end_time, true)
	var source_delta := _bone_origin(source_skeleton, "Hips") - source_start
	var target_delta := _bone_origin(target_skeleton, profile.target_for("Hips")) - target_start
	var expected_delta: Vector3 = source_delta * profile.translation_scale(source_skeleton)
	_check(target_delta.distance_to(expected_delta) < 0.0001, "private Remy Hips preserves scaled root travel and pelvis motion")
	var worst_angle := 0.0
	var worst_label := ""
	for time in [0.0, 0.25, 0.5, end_time]:
		source_player.seek(time, true)
		target_player.seek(time, true)
		for pair in [["LeftUpperArm", "LeftLowerArm"], ["RightUpperArm", "RightLowerArm"], ["LeftUpperLeg", "LeftLowerLeg"], ["RightUpperLeg", "RightLowerLeg"]]:
			var source_direction := _bone_origin(source_skeleton, pair[0]).direction_to(_bone_origin(source_skeleton, pair[1]))
			var target_direction := _bone_origin(target_skeleton, profile.target_for(pair[0])).direction_to(_bone_origin(target_skeleton, profile.target_for(pair[1])))
			var angle := rad_to_deg(source_direction.angle_to(target_direction))
			if angle > worst_angle:
				worst_angle = angle
				worst_label = "%s at %.3f" % [pair[0], time]
	_check(worst_angle < 3.0, "private Remy body and hand chain directions agree within 3 degrees (%.3f, %s)" % [worst_angle, worst_label])
	var source_rests := Profile._global_rests(source_skeleton)
	var target_rests := Profile._global_rests(target_skeleton)
	var worst_hand_frame := 0.0
	var worst_digit_bend := 0.0
	for time in [0.0, 0.25, 0.5, end_time]:
		source_player.seek(time, true)
		target_player.seek(time, true)
		for hand in ["LeftHand", "RightHand"]:
			var frame: Dictionary = HumanoidMap.ORIENTATION_FRAMES[hand]
			var source_frame := RestOrientation.anatomical_frame(source_skeleton, source_rests, hand, frame["forward"], frame["lateral_from"], frame["lateral_to"])
			var target_frame := RestOrientation.anatomical_frame(target_skeleton, target_rests, profile.target_for(hand), profile.target_for(frame["forward"]), profile.target_for(frame["lateral_from"]), profile.target_for(frame["lateral_to"]))
			var source_index := source_skeleton.find_bone(hand)
			var target_index := target_skeleton.find_bone(profile.target_for(hand))
			var source_motion := source_skeleton.get_bone_global_pose(source_index).basis * source_rests[source_index].basis.inverse()
			var target_motion := target_skeleton.get_bone_global_pose(target_index).basis * target_rests[target_index].basis.inverse()
			worst_hand_frame = maxf(worst_hand_frame, rad_to_deg((source_motion * source_frame["basis"]).get_rotation_quaternion().angle_to((target_motion * target_frame["basis"]).get_rotation_quaternion())))
		for digit in ["LeftIndexProximal", "RightThumbProximal", "LeftLittleDistal"]:
			var source_index := source_skeleton.find_bone(digit)
			var target_index := target_skeleton.find_bone(profile.target_for(digit))
			var source_angle := source_skeleton.get_bone_pose(source_index).basis.get_rotation_quaternion().angle_to(source_skeleton.get_bone_rest(source_index).basis.get_rotation_quaternion())
			var target_angle := target_skeleton.get_bone_pose(target_index).basis.get_rotation_quaternion().angle_to(target_skeleton.get_bone_rest(target_index).basis.get_rotation_quaternion())
			worst_digit_bend = maxf(worst_digit_bend, rad_to_deg(absf(source_angle - target_angle)))
	_check(worst_hand_frame < 3.0, "private Remy anatomical wrist frames agree within 3 degrees (%.3f)" % worst_hand_frame)
	_check(worst_digit_bend < 1.0, "private Remy finger bends avoid compensation within 1 degree (%.3f)" % worst_digit_bend)
	var rests := Profile._global_rests(target_skeleton)
	var rest_floor := minf(rests[target_skeleton.find_bone(profile.target_for("LeftFoot"))].origin.y, rests[target_skeleton.find_bone(profile.target_for("RightFoot"))].origin.y)
	var animated_floor := INF
	for frame in 30:
		target_player.seek(float(frame) / 30.0, true)
		animated_floor = minf(animated_floor, minf(_bone_origin(target_skeleton, profile.target_for("LeftFoot")).y, _bone_origin(target_skeleton, profile.target_for("RightFoot")).y))
	var leg_height := float(profile.reference_measurements["leg_height"])
	_check(animated_floor >= rest_floor - leg_height * 0.05, "private Remy feet remain grounded without material floor penetration")

func _bone_origin(skeleton: Skeleton3D, bone_name: StringName) -> Vector3:
	return skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin

func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null

func _contains(values: Array[String], fragment: String) -> bool:
	for value in values:
		if value.to_lower().contains(fragment):
			return true
	return false

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("PASS: versioned rig profile, deterministic matching, signatures, and private Remy import")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)

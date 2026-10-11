extends SceneTree

const Converter := preload("res://addons/kimodo_motion/poses/character_pose_converter.gd")
const Fixture := preload("res://addons/kimodo_motion/retargeting/humanoid_fixture.gd")
const Profile := preload("res://addons/kimodo_motion/retargeting/kimodo_rig_profile.gd")
const SourceBaker := preload("res://addons/kimodo_motion/retargeting/humanoid_retarget_baker.gd")
const CharacterBaker := preload("res://addons/kimodo_motion/retargeting/humanoid_character_baker.gd")
const Map := preload("res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd")
const Factory := preload("res://tests/rig_variant_factory.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Source reference comes from the Stage 1 licensed synthetic contract fixture.
	var scene := (load("res://tests/native/generated/soma77_walk.tscn") as PackedScene).instantiate()
	var source := _find(scene) as Skeleton3D
	var source_rests := Converter.global_transforms(source, true)
	for bone in ["Hips", "LeftArm", "LeftForeArm", "LeftHand", "Neck1", "Neck2"]:
		var index := source.find_bone(bone)
		source.set_bone_pose_rotation(index, Quaternion(Vector3.UP if bone == "Hips" else Vector3.FORWARD, 0.35))
	source.set_bone_pose_position(source.find_bone("Hips"), source.get_bone_rest(source.find_bone("Hips")).origin + Vector3(1.5, -0.1, 2.0))
	var original := Converter.global_transforms(source, false)
	var humanoid := Fixture.create_skeleton()
	var humanoid_rests := Converter.global_transforms(humanoid, true)
	var humanoid_locals := SourceBaker._target_local_poses(source, original, source_rests, humanoid, humanoid_rests)
	for index in humanoid.get_bone_count():
		humanoid.set_bone_pose(index, humanoid_locals[index])
	var target := Fixture.create_skeleton()
	var created := Profile.exact_names(target, NodePath("Skeleton"))
	_check(created["ok"], "fixture profile")
	var profile: Resource = created["profile"]
	var locals := CharacterBaker._target_local_poses(humanoid, Converter.global_transforms(humanoid, false), humanoid_rests, target, Converter.global_transforms(target, true), profile)
	for index in target.get_bone_count():
		target.set_bone_pose(index, locals[index])
	var result := Converter.reconstruct(target, profile, source)
	_check(result["ok"], "reverse supported forward pose")
	if result["ok"]:
		_check(result["joint_rotations"].size() == 30, "exact SOMA-30 joint set")
		var global_bases := {}
		var max_angle := 0.0
		for joint in Converter.JOINTS:
			var q: Array = result["joint_rotations"][joint[0]]
			var local := Basis(Quaternion(q[0], q[1], q[2], q[3]))
			var parent: Basis = global_bases.get(joint[1], Basis.IDENTITY)
			var reconstructed := parent * local
			global_bases[joint[0]] = reconstructed
			if joint[0] in ["Neck1", "LeftHandThumbEnd", "LeftHandMiddleEnd", "RightHandThumbEnd", "RightHandMiddleEnd"]:
				continue
			var source_index := source.find_bone(joint[0])
			var angle := reconstructed.get_rotation_quaternion().angle_to(original[source_index].basis.get_rotation_quaternion())
			max_angle = maxf(max_angle, angle)
			_check(angle < 0.0005, "global orientation survives collapsed reverse: " + joint[0])
		var root_value: Array = result["root_position"]
		_check(Vector3(root_value[0], root_value[1], root_value[2]).distance_to(original[source.find_bone("Hips")].origin) < 0.00001, "root travel and height reconstructed")
		print("POSE_CONVERSION_MAX_ANGLE_RAD ", max_angle)
		print("POSE_CONVERSION_POSITION_RESIDUALS_M ", result["position_residuals_m"])
	var forearm := target.find_bone("LeftLowerArm")
	target.set_bone_pose_position(forearm, target.get_bone_pose_position(forearm) + Vector3(0.1, 0, 0))
	_check(not Converter.reconstruct(target, profile, source)["ok"], "positional edits are not silently discarded")
	_variants(source, humanoid, humanoid_rests)
	scene.free()
	humanoid.free()
	target.free()
	if failures.is_empty():
		print("PASS: deliberate character-to-SOMA-30 orientation reconstruction")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _variants(source: Skeleton3D, humanoid: Skeleton3D, humanoid_rests: Array[Transform3D]) -> void:
	for recipe in [
		{},
		{"names": "opaque", "reverse": true, "axes": true},
		{"names": "sided", "hips_only": true, "scale": 0.8},
		{"names": "opaque", "torso": 1, "minimal": true, "reverse": true, "axes": true, "hips_only": true, "proportions": true, "scale": 1.4},
		{"common_pelvis": true, "proportions": true},
	]:
		var built := Factory.create(recipe)
		var target: Skeleton3D = built["skeleton"]
		var policy := Profile.ROOT_HIPS_ONLY if recipe.get("hips_only", false) else Profile.ROOT_SEPARATE
		var created := Profile.create(built["mapping"], NodePath("Rig"), target, policy, "leg_height")
		_check(created["ok"], "variant profile: " + str(recipe))
		if not created["ok"]:
			built["scene"].free()
			continue
		var profile: Resource = created["profile"]
		# Artist edits originate on the character, independently of a source clip.
		for role in ["Hips", "Spine", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperLeg"]:
			var index := target.find_bone(profile.target_for(role))
			target.set_bone_pose_rotation(index, target.get_bone_pose_rotation(index) * Quaternion(Vector3(0.2, 0.8, 0.4).normalized(), 0.29))
		var hips := target.find_bone(profile.target_for("Hips"))
		target.set_bone_pose_position(hips, target.get_bone_pose_position(hips) + Vector3(0.4, -0.08, 0.6))
		var expected := Converter.global_transforms(target, false)
		var converted := Converter.reconstruct(target, profile, source)
		_check(converted["ok"], "manual variant converts: " + str(converted.get("message", recipe)))
		if converted["ok"]:
			var reconstructed := source.duplicate() as Skeleton3D
			var model_globals := {}
			for joint in Converter.JOINTS:
				var q: Array = converted["joint_rotations"][joint[0]]
				model_globals[joint[0]] = (model_globals.get(joint[1], Basis.IDENTITY) as Basis) * Basis(Quaternion(q[0], q[1], q[2], q[3]))
			# Expand the reconstructed global orientations into the presentation hierarchy.
			var expanded: Array[Basis] = []
			expanded.resize(reconstructed.get_bone_count())
			for index in Converter.Geometry.order(reconstructed):
				var name_value := String(reconstructed.get_bone_name(index))
				var parent := reconstructed.get_bone_parent(index)
				var parent_basis := Basis.IDENTITY if parent < 0 else expanded[parent]
				var desired: Basis = model_globals.get(name_value, parent_basis * reconstructed.get_bone_rest(index).basis)
				expanded[index] = desired
				reconstructed.set_bone_pose_rotation(index, (parent_basis.inverse() * desired).get_rotation_quaternion())
			var p: Array = converted["root_position"]
			reconstructed.set_bone_pose_position(reconstructed.find_bone("Hips"), Vector3(p[0], p[1], p[2]))
			var source_rests := Converter.global_transforms(reconstructed, true)
			var hlocals := SourceBaker._target_local_poses(reconstructed, Converter.global_transforms(reconstructed, false), source_rests, humanoid, humanoid_rests)
			for index in humanoid.get_bone_count():
				humanoid.set_bone_pose(index, hlocals[index])
			var locals := CharacterBaker._target_local_poses(humanoid, Converter.global_transforms(humanoid, false), humanoid_rests, target, Converter.global_transforms(target, true), profile)
			for index in target.get_bone_count():
				target.set_bone_pose(index, locals[index])
			var actual := Converter.global_transforms(target, false)
			for role in profile.rotation_targets():
				if String(Map.source_for_target(role)) not in model_globals:
					continue
				var index := target.find_bone(profile.target_for(role))
				_check(actual[index].basis.get_rotation_quaternion().angle_to(expected[index].basis.get_rotation_quaternion()) < 0.001, "manual variant orientation: " + String(role))
			_check(actual[hips].origin.distance_to(expected[hips].origin) < 0.00001, "manual variant root position")
			print("POSE_VARIANT_RESIDUALS_M ", recipe, " ", converted["position_residuals_m"])
			reconstructed.free()
			if policy == Profile.ROOT_SEPARATE:
				var motion_root := target.find_bone(profile.target_for("Root"))
				target.set_bone_pose_scale(motion_root, Vector3.ONE * 1.1)
				_check(not Converter.reconstruct(target, profile, source)["ok"], "ancestor scaling rejected")
		built["scene"].free()


func _find(node: Node) -> Node:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find(child)
		if found != null:
			return found
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

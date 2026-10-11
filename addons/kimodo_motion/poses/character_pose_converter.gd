@tool
class_name KimodoCharacterPoseConverter
extends RefCounted

const Map := preload("res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd")
const Geometry := preload("res://addons/kimodo_motion/retargeting/rig_geometry.gd")
const Fixture := preload("res://addons/kimodo_motion/retargeting/humanoid_fixture.gd")
const SourceBaker := preload("res://addons/kimodo_motion/retargeting/humanoid_retarget_baker.gd")
const CharacterBaker := preload("res://addons/kimodo_motion/retargeting/humanoid_character_baker.gd")

# The model hierarchy differs from SOMA-77 at its hand endpoints. Reconstruct
# global orientations, then decompose against this hierarchy; never slice local
# character quaternions or attempt to recover unobservable collapsed articulation.
const JOINTS := [
	["Hips", ""], ["Spine1", "Hips"], ["Spine2", "Spine1"], ["Chest", "Spine2"],
	["Neck1", "Chest"], ["Neck2", "Neck1"], ["Head", "Neck2"], ["Jaw", "Head"],
	["LeftEye", "Head"], ["RightEye", "Head"], ["LeftShoulder", "Chest"],
	["LeftArm", "LeftShoulder"], ["LeftForeArm", "LeftArm"], ["LeftHand", "LeftForeArm"],
	["LeftHandThumbEnd", "LeftHand"], ["LeftHandMiddleEnd", "LeftHand"],
	["RightShoulder", "Chest"], ["RightArm", "RightShoulder"],
	["RightForeArm", "RightArm"], ["RightHand", "RightForeArm"],
	["RightHandThumbEnd", "RightHand"], ["RightHandMiddleEnd", "RightHand"],
	["LeftLeg", "Hips"], ["LeftShin", "LeftLeg"], ["LeftFoot", "LeftShin"], ["LeftToeBase", "LeftFoot"],
	["RightLeg", "Hips"], ["RightShin", "RightLeg"], ["RightFoot", "RightShin"], ["RightToeBase", "RightFoot"],
]


static func canonical_skeleton(payload: Dictionary) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Soma77Reference"
	for joint in payload.get("joints", []):
		skeleton.add_bone(joint["name"])
		var index := skeleton.get_bone_count() - 1
		var parent: Variant = joint.get("parent")
		skeleton.set_bone_parent(index, skeleton.find_bone(parent) if parent is String else -1)
		var p: Array = joint["rest_translation"]
		var q: Array = joint["rest_rotation"]
		var rest := Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3])), Vector3(p[0], p[1], p[2]))
		skeleton.set_bone_rest(index, rest)
		skeleton.set_bone_pose(index, rest)
	return skeleton


static func reconstruct(target: Skeleton3D, profile: Resource, source: Skeleton3D) -> Dictionary:
	if target == null or profile == null or source == null:
		return _error("Select a character with a current reviewed profile and a canonical rig.")
	var problem: String = profile.validate_for(target)
	if not problem.is_empty():
		return _error(problem)
	for joint in JOINTS:
		if source.find_bone(joint[0]) < 0:
			return _error("The canonical rig is missing SOMA-30 joint %s." % joint[0])
	var target_rests := global_transforms(target, true)
	var target_poses := global_transforms(target, false)
	# An unmapped ancestor can scale or translate an entire mapped limb too.
	# Reject those changes rather than stripping scale during orthonormalization.
	var body_ancestors := {}
	for role in profile.rotation_targets():
		var index := target.find_bone(profile.target_for(role))
		while index >= 0:
			body_ancestors[index] = true
			index = target.get_bone_parent(index)
	for index in body_ancestors:
		var rest := target.get_bone_rest(index)
		var value := target.get_bone_pose(index)
		if not value.is_finite() or not value.basis.get_scale().is_equal_approx(rest.basis.get_scale()):
			return _error("Bone scaling cannot be represented by SOMA-30: %s." % target.get_bone_name(index))
		var role: StringName = profile.canonical_for(target.get_bone_name(index))
		if role not in ["Root", "Hips"] and not value.origin.is_equal_approx(rest.origin):
			return _error("Non-root translation requires positional fitting: %s. The edit is preserved, but cannot yet be sent as a rotation-only pose." % target.get_bone_name(index))
	var source_rests := global_transforms(source, true)
	var humanoid := Fixture.create_skeleton()
	var humanoid_rests := global_transforms(humanoid, true)
	var scale: float = profile.translation_scale(humanoid)
	if not is_finite(scale) or scale <= 0.0:
		humanoid.free()
		return _error("The profile has no valid positive translation scale.")
	var mapped_globals := {}
	var excluded: Array[String] = []
	for role in profile.rotation_targets():
		var source_name: StringName = Map.source_for_target(role)
		var source_index := source.find_bone(source_name)
		var humanoid_index := humanoid.find_bone(role)
		var target_index := target.find_bone(profile.target_for(role))
		if source_index < 0 or humanoid_index < 0 or target_index < 0:
			continue
		var local_rest := target.get_bone_rest(target_index)
		var local_pose := target.get_bone_pose(target_index)
		if not local_pose.is_finite() or not local_pose.basis.get_scale().is_equal_approx(local_rest.basis.get_scale()):
			humanoid.free()
			return _error("Bone scaling cannot be represented by SOMA-30: %s." % target.get_bone_name(target_index))
		if role != "Hips" and not local_pose.origin.is_equal_approx(local_rest.origin):
			humanoid.free()
			return _error("Non-root translation requires positional fitting: %s. The edit is preserved, but cannot yet be sent as a rotation-only pose." % target.get_bone_name(target_index))
		var corrected_character := CharacterBaker._direction_corrected_rest_basis(role, humanoid, humanoid_rests, target, target_rests, profile)
		var corrected_humanoid := SourceBaker._direction_corrected_rest_basis(role, source, source_rests, humanoid, humanoid_rests)
		var character_global := target_poses[target_index].basis.orthonormalized()
		var humanoid_global := character_global * corrected_character.inverse() * humanoid_rests[humanoid_index].basis
		mapped_globals[String(source_name)] = (humanoid_global * corrected_humanoid.inverse() * source_rests[source_index].basis).orthonormalized()
	var rotations := {}
	var globals := {}
	for joint in JOINTS:
		var name_value: String = joint[0]
		var parent: String = joint[1]
		var parent_basis: Basis = globals.get(parent, Basis.IDENTITY)
		var desired: Basis = mapped_globals.get(name_value, parent_basis)
		globals[name_value] = desired
		var q := (parent_basis.inverse() * desired).get_rotation_quaternion().normalized()
		rotations[name_value] = [q.x, q.y, q.z, q.w]
	for source_name in mapped_globals:
		if not rotations.has(source_name):
			excluded.append(source_name)
	var excluded_character_bones: Array[String] = []
	for index in target.get_bone_count():
		var role: StringName = profile.canonical_for(target.get_bone_name(index))
		if role != "Root" and not rotations.has(String(Map.source_for_target(role))):
			excluded_character_bones.append(String(target.get_bone_name(index)))
	var hips_target := target.find_bone(profile.target_for("Hips"))
	var hips_source := source.find_bone("Hips")
	# The first forward stage preserves source root displacement unchanged.
	# Only the character stage scales travel; scene placement remains separate.
	var combined_scale := scale
	var root_delta := (target_poses[hips_target].origin - target_rests[hips_target].origin) / combined_scale
	var root_position := source_rests[hips_source].origin + root_delta
	var position_residuals := {}
	var soma_positions := {}
	# Compare motion against the character's forward-transferred canonical neutral,
	# not its imported A/T bind pose. Those are intentionally different baselines.
	var neutral_humanoid := _globals_for_locals(humanoid, SourceBaker._target_local_poses(source, source_rests, source_rests, humanoid, humanoid_rests))
	var neutral_target := _globals_for_locals(target, CharacterBaker._target_local_poses(humanoid, neutral_humanoid, humanoid_rests, target, target_rests, profile))
	for joint in JOINTS:
		var bone: String = joint[0]
		var parent: String = joint[1]
		var index := source.find_bone(bone)
		if index < 0:
			humanoid.free()
			return _error("The canonical rig is missing SOMA-30 joint %s." % bone)
		if parent.is_empty():
			soma_positions[bone] = root_position
		else:
			var offset := source_rests[index].origin - source_rests[source.find_bone(parent)].origin
			soma_positions[bone] = soma_positions[parent] + globals[parent] * offset
	for role in ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
		var target_index := target.find_bone(profile.target_for(role))
		var bone := String(Map.source_for_target(role))
		var normalized_position := source_rests[source.find_bone(bone)].origin + (target_poses[target_index].origin - neutral_target[target_index].origin) / combined_scale
		position_residuals[role] = soma_positions[bone].distance_to(normalized_position)
	humanoid.free()
	return {"ok": true, "joint_rotations": rotations, "root_position": [root_position.x, root_position.y, root_position.z], "excluded_source_joints": excluded, "excluded_character_bones": excluded_character_bones, "position_residuals_m": position_residuals, "root_space": "skeleton_local_meters"}


static func global_transforms(skeleton: Skeleton3D, rest: bool) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	result.resize(skeleton.get_bone_count())
	for index in Geometry.order(skeleton):
		var local := skeleton.get_bone_rest(index) if rest else skeleton.get_bone_pose(index)
		var parent := skeleton.get_bone_parent(index)
		result[index] = local if parent < 0 else result[parent] * local
	return result


static func _globals_for_locals(skeleton: Skeleton3D, locals: Array[Transform3D]) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	result.resize(skeleton.get_bone_count())
	for index in Geometry.order(skeleton):
		var parent := skeleton.get_bone_parent(index)
		result[index] = locals[index] if parent < 0 else result[parent] * locals[index]
	return result


static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}

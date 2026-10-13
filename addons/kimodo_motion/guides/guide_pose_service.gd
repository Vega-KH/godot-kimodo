@tool
class_name KimodoGuidePoseService
extends RefCounted

const Space := preload("res://addons/kimodo_motion/guides/root_guide_space.gd")
const Converter := preload("res://addons/kimodo_motion/poses/character_pose_converter.gd")
const Fixture := preload("res://addons/kimodo_motion/retargeting/humanoid_fixture.gd")
const SourceBaker := preload("res://addons/kimodo_motion/retargeting/humanoid_retarget_baker.gd")
const CharacterBaker := preload("res://addons/kimodo_motion/retargeting/humanoid_character_baker.gd")
const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")


static func create_reference(target: Skeleton3D, profile: Resource, payload: Dictionary) -> Dictionary:
	var checked := Capabilities.validate_skeleton_payload(payload)
	if not checked["ok"]:
		return checked
	var problem: String = profile.validate_for(target)
	if not problem.is_empty():
		return _error(problem)
	var source := Converter.canonical_skeleton(payload)
	var humanoid := Fixture.create_skeleton()
	var source_rests := Converter.global_transforms(source, true)
	var humanoid_rests := Converter.global_transforms(humanoid, true)
	var target_rests := Converter.global_transforms(target, true)
	# Same right-hand calibration used by the complete pose converter. Multiplying
	# a character global Hips basis by this gives the SOMA global Hips basis.
	var character_basis := CharacterBaker._direction_corrected_rest_basis("Hips", humanoid, humanoid_rests, target, target_rests, profile)
	var source_basis := SourceBaker._direction_corrected_rest_basis("Hips", source, source_rests, humanoid, humanoid_rests)
	var calibration: Basis = character_basis.inverse() * humanoid_rests[humanoid.find_bone("Hips")].basis * source_basis.inverse() * source_rests[source.find_bone("Hips")].basis
	source.free()
	humanoid.free()
	calibration = calibration.orthonormalized()
	return {"ok": true, "reference": {"version": 1, "canonical_skeleton": payload.duplicate(true), "hips_calibration": [Space.vector(calibration.x), Space.vector(calibration.y), Space.vector(calibration.z)]}}


static func validation_error(value: Dictionary) -> String:
	if value.get("version") != 1 or not value.get("canonical_skeleton") is Dictionary:
		return "Guide pose reference is incomplete."
	if not Capabilities.validate_skeleton_payload(value["canonical_skeleton"])["ok"]:
		return "Guide pose reference has an invalid canonical skeleton."
	var axes: Variant = value.get("hips_calibration")
	if not axes is Array or axes.size() != 3:
		return "Guide pose calibration is incomplete."
	for axis in axes:
		if not axis is Array or axis.size() != 3:
			return "Guide pose calibration is malformed."
		for component in axis:
			if not (component is float or component is int) or not is_finite(float(component)):
				return "Guide pose calibration must be finite."
	var basis := _calibration(value)
	if basis.determinant() <= 0 or not basis.is_equal_approx(basis.orthonormalized()):
		return "Guide pose calibration must be a rotation."
	return ""


static func current_guide(target: Skeleton3D, profile: Resource, space: Dictionary, value: Dictionary) -> Dictionary:
	var index := target.find_bone(profile.target_for("Hips"))
	if index < 0:
		return _error("The character has no mapped Hips bone.")
	var hips: Transform3D = Converter.global_transforms(target, false)[index]
	var basis := hips.basis.orthonormalized() * _calibration(value)
	var lateral := basis * Vector3.LEFT
	if Vector2(lateral.x, lateral.z).length_squared() < 0.000001:
		return _error("This Hips orientation has no stable horizontal facing.")
	var heading := atan2(lateral.z, -lateral.x)
	var position := target.global_transform * hips.origin
	position.y = Space.decode_transform(space["placement"]).origin.y
	return {"ok": true, "transform": Transform3D(Basis(Vector3.UP, Space.model_heading_to_world(space, heading)), position)}


static func apply_guide(target: Skeleton3D, profile: Resource, space: Dictionary, value: Dictionary, guide: Transform3D) -> Dictionary:
	var edited := guide_edit(target, profile, space, value, guide)
	if edited["ok"]:
		target.set_bone_pose(edited["bone"], edited["pose"])
	return edited


static func guide_edit(target: Skeleton3D, profile: Resource, space: Dictionary, value: Dictionary, guide: Transform3D) -> Dictionary:
	if not guide.is_finite():
		return _error("The guide transform must be finite.")
	var current := current_guide(target, profile, space, value)
	if not current["ok"]:
		return current
	var direction := guide.basis * Vector3.BACK
	if Vector2(direction.x, direction.z).length_squared() < 0.000001:
		return _error("Keep the guide's facing arrow horizontal.")
	var old_direction: Vector3 = current["transform"].basis * Vector3.BACK
	var old_heading := Space.world_heading_to_model(space, atan2(old_direction.x, old_direction.z))
	var new_heading := Space.world_heading_to_model(space, atan2(direction.x, direction.z))
	var index := target.find_bone(profile.target_for("Hips"))
	var globals := Converter.global_transforms(target, false)
	var desired: Transform3D = globals[index]
	var position := target.global_transform * desired.origin
	position.x = guide.origin.x
	position.z = guide.origin.z
	desired.origin = target.global_transform.affine_inverse() * position
	desired.basis = Basis(Vector3.UP, wrapf(new_heading - old_heading, -PI, PI)) * desired.basis
	var parent := target.get_bone_parent(index)
	var local := (globals[parent].affine_inverse() * desired) if parent >= 0 else desired
	return {"ok": true, "bone": index, "pose": local}


static func channel_error(channels: Array, target: Skeleton3D = null) -> String:
	var seen := {}
	for channel in channels:
		if not channel is Dictionary or not channel.get("bone") is String or channel.get("kind") not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			return "Authored pose channel is invalid."
		if target != null and target.find_bone(channel["bone"]) < 0:
			return "Authored pose contains an unknown bone."
		var key := "%s:%d" % [channel["bone"], channel["kind"]]
		if seen.has(key):
			return "Authored pose contains duplicate channels."
		seen[key] = true
		var numbers: Variant = channel.get("value")
		var count := 4 if channel["kind"] == Animation.TYPE_ROTATION_3D else 3
		if not numbers is Array or numbers.size() != count:
			return "Authored pose channel has an invalid value."
		for number in numbers:
			if not (number is float or number is int) or not is_finite(float(number)):
				return "Authored pose channels must be finite."
		if count == 4 and absf(Quaternion(numbers[0], numbers[1], numbers[2], numbers[3]).length_squared() - 1.0) > 0.0001:
			return "Authored pose rotation must be normalized."
	return ""


static func restore_channels(target: Skeleton3D, channels: Array) -> Dictionary:
	var problem := channel_error(channels, target)
	if not problem.is_empty():
		return _error(problem)
	for channel in channels:
		var index := target.find_bone(channel["bone"])
		var numbers: Array = channel["value"]
		match channel["kind"]:
			Animation.TYPE_POSITION_3D:
				target.set_bone_pose_position(index, Space.unvector(numbers))
			Animation.TYPE_ROTATION_3D:
				target.set_bone_pose_rotation(index, Quaternion(numbers[0], numbers[1], numbers[2], numbers[3]))
			Animation.TYPE_SCALE_3D:
				target.set_bone_pose_scale(index, Space.unvector(numbers))
	return {"ok": true}


static func _calibration(value: Dictionary) -> Basis:
	var axes: Array = value["hips_calibration"]
	return Basis(Space.unvector(axes[0]), Space.unvector(axes[1]), Space.unvector(axes[2]))


static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}

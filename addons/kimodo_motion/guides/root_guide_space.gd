@tool
class_name KimodoRootGuideSpace
extends RefCounted

# Guide points represent the projected neutral pelvis plus model root travel.
# This mirrors the two forward bakers: character travel is scaled once, while
# canonical neutral height/offset is not used as a scene placement transform.
const Fixture := preload("res://addons/kimodo_motion/retargeting/humanoid_fixture.gd")
const Geometry := preload("res://addons/kimodo_motion/retargeting/rig_geometry.gd")


static func capture(skeleton: Skeleton3D, profile: Resource, model_hips_rest: Vector3) -> Dictionary:
	if skeleton == null or profile == null:
		return _error("Choose a character with a reviewed profile first.")
	var problem: String = profile.validate_for(skeleton)
	if not problem.is_empty():
		return _error(problem)
	var placement := skeleton.global_transform
	var axes := placement.basis
	var sizes := axes.get_scale()
	if not placement.is_finite() or axes.determinant() <= 0 or sizes.x <= 0 or not sizes.is_equal_approx(Vector3.ONE * sizes.x):
		return _error("Root guides require a positive uniform character scene scale.")
	var orientation := axes.orthonormalized()
	if not axes.is_equal_approx(orientation.scaled(Vector3.ONE * sizes.x)):
		return _error("Root guides require an orthogonal character placement without shear.")
	if not (orientation * Vector3.UP).is_equal_approx(Vector3.UP):
		return _error("Root guides require an upright character placement (yaw only).")
	var humanoid := Fixture.create_skeleton()
	var scale: float = profile.translation_scale(humanoid)
	humanoid.free()
	if not is_finite(scale) or scale <= 0:
		return _error("The profile has an invalid translation scale.")
	var rests := Geometry.global_rests(skeleton)
	var neutral: Vector3 = rests[skeleton.find_bone(profile.target_for("Hips"))].origin
	return {"ok": true, "space": {"version": 1, "placement": encode_transform(placement), "neutral_hips": vector(neutral), "model_hips_rest": vector(model_hips_rest), "profile_scale": scale}}


static func world_to_model(space: Dictionary, position: Vector3) -> Vector3:
	var placement := decode_transform(space["placement"])
	return unvector(space["model_hips_rest"]) + (placement.affine_inverse() * position - unvector(space["neutral_hips"])) / float(space["profile_scale"])


static func model_to_world(space: Dictionary, position: Vector3) -> Vector3:
	return decode_transform(space["placement"]) * (unvector(space["neutral_hips"]) + (position - unvector(space["model_hips_rest"])) * float(space["profile_scale"]))


static func world_heading_to_model(space: Dictionary, heading: float) -> float:
	var local := decode_transform(space["placement"]).basis.inverse() * Vector3(sin(heading), 0, cos(heading))
	return atan2(local.x, local.z)


static func model_heading_to_world(space: Dictionary, heading: float) -> float:
	var world := decode_transform(space["placement"]).basis * Vector3(sin(heading), 0, cos(heading))
	return atan2(world.x, world.z)


static func encode_transform(value: Transform3D) -> Array:
	return [vector(value.basis.x), vector(value.basis.y), vector(value.basis.z), vector(value.origin)]


static func decode_transform(value: Array) -> Transform3D:
	return Transform3D(Basis(unvector(value[0]), unvector(value[1]), unvector(value[2])), unvector(value[3]))


static func vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func unvector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}

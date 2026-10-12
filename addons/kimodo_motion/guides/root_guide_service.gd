@tool
class_name KimodoRootGuideService
extends RefCounted

const Space := preload("res://addons/kimodo_motion/guides/root_guide_space.gd")


static func validation_error(intent: Dictionary, duration := 900) -> String:
	if intent.is_empty():
		return ""
	if intent.get("version") != 1 or not intent.get("points") is Array or not intent.get("space") is Dictionary:
		return "Root guide data is incomplete or unsupported."
	var space: Dictionary = intent["space"]
	if space.get("version") != 1 or not _numbers(space.get("neutral_hips"), 3) or not _numbers(space.get("model_hips_rest"), 3):
		return "Root guide reference positions are invalid."
	var placement: Variant = space.get("placement")
	if not placement is Array or placement.size() != 4:
		return "Root guide scene placement is invalid."
	for axis in placement:
		if not _numbers(axis, 3):
			return "Root guide scene placement must be finite."
	var transform := Space.decode_transform(placement)
	var scale := transform.basis.get_scale()
	if transform.basis.determinant() <= 0 or scale.x <= 0 or not scale.is_equal_approx(Vector3.ONE * scale.x) or not (transform.basis.orthonormalized() * Vector3.UP).is_equal_approx(Vector3.UP):
		return "Root guide scene placement must be upright with positive uniform scale."
	if not transform.basis.is_equal_approx(transform.basis.orthonormalized().scaled(Vector3.ONE * scale.x)):
		return "Root guide scene placement must be orthogonal without shear."
	var profile_scale: Variant = space.get("profile_scale")
	if not _number(profile_scale) or float(profile_scale) <= 0:
		return "Root guide profile scale is invalid."
	if String(intent.get("target_signature", "")).length() != 64 or not intent.get("profile_configuration") is Dictionary:
		return "Root guide rig identity is invalid."
	if not intent.get("scene_path") is String or not intent.get("skeleton_path") is String or not intent.get("player_path") is String:
		return "Root guide scene binding is invalid."
	var seen := {}
	for point in intent["points"]:
		if not point is Dictionary:
			return "Root guide waypoint is invalid."
		var frame: Variant = point.get("frame")
		if not frame is int or frame < 0 or frame >= duration or seen.has(frame):
			return "Root guide frames must be unique and within the generation duration."
		seen[frame] = true
		if not _numbers(point.get("world_position"), 3) or not point.get("use_heading") is bool or not _number(point.get("world_heading")):
			return "Root guide position/facing must be finite."
	return ""


static func constraints(intent: Dictionary, poses: Array, duration: int) -> Dictionary:
	var problem := validation_error(intent, duration)
	if not problem.is_empty():
		return _error(problem)
	if intent.is_empty() or intent["points"].is_empty():
		return {"ok": true, "constraints": []}
	var space: Dictionary = intent["space"]
	var points: Array = intent["points"].duplicate(true)
	points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["frame"] < b["frame"])
	var frames: Array = []
	var positions: Array = []
	var heading_frames: Array = []
	var heading_positions: Array = []
	var headings: Array = []
	for point in points:
		var position := Space.world_to_model(space, Space.unvector(point["world_position"]))
		var heading := Space.world_heading_to_model(space, float(point["world_heading"]))
		for entry in poses:
			var pose: Dictionary = entry.get("constraint", entry)
			if pose.get("frame") != point["frame"]:
				continue
			var root := Space.unvector(pose["root_position"])
			if Vector2(root.x, root.z).distance_to(Vector2(position.x, position.z)) > 0.00001:
				return _error("Root guide and full-body pose disagree at frame %d. Move the waypoint to the pose root, or remove/recapture one of the constraints." % point["frame"])
			if point["use_heading"]:
				var q: Array = pose["joint_rotations"]["Hips"]
				var rotation := Quaternion(q[0], q[1], q[2], q[3])
				var lateral := rotation * Vector3.LEFT
				var pose_heading := atan2(lateral.z, -lateral.x)
				if absf(wrapf(pose_heading - heading, -PI, PI)) > 0.0001:
					return _error("Root guide facing and full-body pose disagree at frame %d. Disable guide facing or recapture the pose." % point["frame"])
		if point["use_heading"]:
			heading_frames.append(point["frame"])
			heading_positions.append([position.x, position.z])
			headings.append(heading)
		else:
			frames.append(point["frame"])
			positions.append([position.x, position.z])
	var result: Array[Dictionary] = []
	if not frames.is_empty():
		result.append({"type": "root_path", "frames": frames, "positions_xz": positions})
	if not heading_frames.is_empty():
		result.append({"type": "root_path", "frames": heading_frames, "positions_xz": heading_positions, "heading_radians": headings})
	return {"ok": true, "constraints": result}


static func _numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for component in value:
		if not _number(component):
			return false
	return true


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}

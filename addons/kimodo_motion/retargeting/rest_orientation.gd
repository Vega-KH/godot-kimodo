class_name KimodoRestOrientation
extends RefCounted

const MIN_AXIS_LENGTH := 0.000001


static func anatomical_frame(
	skeleton: Skeleton3D,
	global_rests: Array[Transform3D],
	origin_name: StringName,
	forward_name: StringName,
	lateral_from_name: StringName,
	lateral_to_name: StringName,
) -> Dictionary:
	var names := [origin_name, forward_name, lateral_from_name, lateral_to_name]
	var indices: Array[int] = []
	for bone_name in names:
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			return {
				"ok": false,
				"message": "Anatomical orientation frame is missing bone %s" % bone_name,
			}
		indices.append(index)
	var origin := global_rests[indices[0]].origin
	var forward := global_rests[indices[1]].origin - origin
	var lateral_hint := (
		global_rests[indices[3]].origin - global_rests[indices[2]].origin
	)
	if forward.length() <= MIN_AXIS_LENGTH:
		return {
			"ok": false,
			"message": "Anatomical orientation frame has a zero-length forward axis at %s"
			% origin_name,
		}
	forward = forward.normalized()
	var lateral := lateral_hint - forward * lateral_hint.dot(forward)
	if lateral.length() <= MIN_AXIS_LENGTH:
		return {
			"ok": false,
			"message": "Anatomical orientation frame has a degenerate lateral axis at %s"
			% origin_name,
		}
	lateral = lateral.normalized()
	var normal := forward.cross(lateral).normalized()
	lateral = normal.cross(forward).normalized()
	var basis := Basis(lateral, normal, forward).orthonormalized()
	if not basis.is_finite() or basis.determinant() <= 0.0:
		return {
			"ok": false,
			"message": "Anatomical orientation frame is invalid at %s" % origin_name,
		}
	return {"ok": true, "basis": basis}

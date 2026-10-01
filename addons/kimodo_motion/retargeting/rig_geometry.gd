class_name KimodoRigGeometry
extends RefCounted

# Exporters need not number bones in parent-first order.
static func order(skeleton: Skeleton3D) -> Array[int]:
	var result: Array[int] = []
	for index in skeleton.get_parentless_bones():
		_append_branch(skeleton, index, result)
	return result

static func _append_branch(skeleton: Skeleton3D, index: int, result: Array[int]) -> void:
	result.append(index)
	for child in skeleton.get_bone_children(index):
		_append_branch(skeleton, child, result)

static func global_rests(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	result.resize(skeleton.get_bone_count())
	for index in order(skeleton):
		var parent := skeleton.get_bone_parent(index)
		result[index] = skeleton.get_bone_rest(index)
		if parent >= 0:
			result[index] = result[parent] * result[index]
	return result

static func descendant(skeleton: Skeleton3D, child: String, ancestor: String) -> bool:
	var index := skeleton.find_bone(child)
	var owner := skeleton.find_bone(ancestor)
	if index < 0 or owner < 0 or index == owner:
		return false
	while index >= 0:
		index = skeleton.get_bone_parent(index)
		if index == owner:
			return true
	return false

static func rest_basis_issue(basis: Basis) -> String:
	# Rotation-only libraries preserve rest scale, but cannot represent shear
	# induced by rotating below an anisotropically scaled bone. Allow small
	# exporter rounding and positive uniform bone scale, not silent distortion.
	if basis.determinant() <= 0.0:
		return "a reflected rest basis"
	var lengths := Vector3(basis.x.length(), basis.y.length(), basis.z.length())
	var mean := (lengths.x + lengths.y + lengths.z) / 3.0
	if (maxf(lengths.x, maxf(lengths.y, lengths.z)) - minf(lengths.x, minf(lengths.y, lengths.z))) / mean > 0.001:
		return "non-uniform bone scale"
	var axes := [basis.x.normalized(), basis.y.normalized(), basis.z.normalized()]
	if absf(axes[0].dot(axes[1])) > 0.001 or absf(axes[0].dot(axes[2])) > 0.001 or absf(axes[1].dot(axes[2])) > 0.001:
		return "a sheared rest basis"
	return ""

static func relative_transform(node: Node3D, root: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

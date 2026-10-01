class_name KimodoRigCompatibility
extends RefCounted

const Geometry := preload("res://addons/kimodo_motion/retargeting/rig_geometry.gd")
const BASIS_TOLERANCE := 0.001

static func inspect(character: Node) -> Dictionary:
	var skeletons := character.find_children("*", "Skeleton3D", true, false)
	if character is Skeleton3D:
		skeletons.push_front(character)
	if skeletons.size() != 1:
		return _error("skeleton_count", "This character contains %d skeletons. Select a scene with one deform skeleton; multiple-skeleton selection is not supported yet." % skeletons.size())
	var skeleton := skeletons[0] as Skeleton3D
	for index in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(index)
		if not rest.is_finite() or absf(rest.basis.determinant()) < 0.000001:
			return _error("invalid_rest", "Bone '%s' has a non-finite or non-invertible rest transform. Correct its transform in your modeling tool and re-export." % skeleton.get_bone_name(index))
		var basis_issue := Geometry.rest_basis_issue(rest.basis)
		if not basis_issue.is_empty():
			return _error("unsupported_rest_basis", "Bone '%s' has %s. Rotation-only retargeting cannot safely preserve this basis. Apply/correct bone scale and shear in your modeling tool while preserving the skin bind pose, then re-export the mesh and armature together." % [skeleton.get_bone_name(index), basis_issue])
	var rests := Geometry.global_rests(skeleton)
	var skeleton_transform := Geometry.relative_transform(skeleton, character)
	if not skeleton_transform.is_finite() or absf(skeleton_transform.basis.determinant()) < 0.000001:
		return _error("invalid_transform", "The skeleton node has an invalid transform. Apply a finite, nonzero transform in your modeling tool and re-export.")
	var extent := 0.0
	for rest in rests:
		extent = maxf(extent, rest.origin.length())
	var position_tolerance := maxf(extent * 0.0001, 0.0001)
	var count := 0
	var worst_position := 0.0
	var worst_basis := 0.0
	var bind_space_scale := 0.0
	for found in character.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		if mesh.skin == null:
			continue
		if mesh.get_node_or_null(mesh.skeleton) != skeleton:
			return _error("wrong_skin_skeleton", "Mesh '%s' is not bound to the selected skeleton. Correct its skeleton assignment before using this character." % mesh.name)
		if mesh.skin.get_bind_count() == 0:
			return _error("empty_skin", "Mesh '%s' has an empty skin binding. Export its armature and vertex weights together." % mesh.name)
		count += 1
		var expected := skeleton_transform.affine_inverse() * Geometry.relative_transform(mesh, character)
		if not expected.is_finite() or absf(expected.basis.determinant()) < 0.000001:
			return _error("invalid_transform", "Mesh '%s' has an invalid transform relative to its skeleton. Correct its finite, nonzero transform and re-export." % mesh.name)
		for bind in mesh.skin.get_bind_count():
			var name := mesh.skin.get_bind_name(bind)
			var index := skeleton.find_bone(name) if not name.is_empty() else mesh.skin.get_bind_bone(bind)
			if index < 0 or index >= skeleton.get_bone_count():
				return _error("missing_skin_bone", "Mesh '%s' skin binding %d refers to a missing bone '%s'. Re-export the mesh with its complete armature." % [mesh.name, bind, name])
			var bind_pose := mesh.skin.get_bind_pose(bind)
			if not bind_pose.is_finite() or absf(bind_pose.basis.determinant()) < 0.000001:
				return _error("invalid_bind", "Mesh '%s', bone '%s' has an invalid skin bind transform. Re-export valid skin bindings from your modeling tool." % [mesh.name, skeleton.get_bone_name(index)])
			var composed := rests[index] * bind_pose
			# Importers may retain a uniform bind-shape scale after normalizing scene
			# nodes. Only one positive scalar shared by ALL meshes/binds is harmless;
			# never independently normalize bones or rewrite their skin/rest data.
			var residual := expected.affine_inverse() * composed
			if bind_space_scale == 0.0:
				bind_space_scale = (residual.basis.x.x + residual.basis.y.y + residual.basis.z.z) / 3.0
				if bind_space_scale <= 0.000001 or not is_finite(bind_space_scale):
					return _error("bind_rest_mismatch", "Mesh '%s', bone '%s': the skin bind space is not a positive uniform scale. This add-on requires matching bind and rest poses; correct the binding and re-export the mesh and armature together." % [mesh.name, skeleton.get_bone_name(index)])
			var position_error := composed.origin.distance_to(expected.origin)
			var basis_error := 0.0
			for axis in 3:
				basis_error = maxf(basis_error, (residual.basis[axis] / bind_space_scale).distance_to(Basis.IDENTITY[axis]))
			worst_position = maxf(worst_position, position_error)
			worst_basis = maxf(worst_basis, basis_error)
			if position_error > position_tolerance or basis_error > BASIS_TOLERANCE:
				return _error("bind_rest_mismatch", "Mesh '%s', bone '%s': the mesh's skin bind pose does not match the skeleton's rest pose (position difference %.6f, axis difference %.6f). This add-on requires matching bind and rest poses. Restore the armature's bind/rest pose in your modeling tool and re-export the mesh and armature together; changing the bone map will not fix this." % [mesh.name, skeleton.get_bone_name(index), position_error, basis_error])
	if count == 0:
		return _error("missing_skin", "This scene has no skinned mesh. Select a character exported with an armature and skin weights.")
	return {"ok": true, "skeleton": skeleton, "position_error": worst_position, "basis_error": worst_basis, "meshes": count, "bind_space_scale": bind_space_scale}

static func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}

extends RefCounted

const Fixture := preload("res://addons/kimodo_motion/retargeting/humanoid_fixture.gd")
const Map := preload("res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd")

# Independent synthetic skin/rest data, not private model extracts.
static func create(recipe: Dictionary) -> Dictionary:
	var original := Fixture.create_skeleton()
	if recipe.get("proportions", false):
		for index in original.get_bone_count():
			var role := String(original.get_bone_name(index))
			var rest := original.get_bone_rest(index)
			if role == "Hips":
				rest.origin.y *= 1.15
			elif role in ["Spine", "Chest", "UpperChest"]:
				rest.origin *= 0.8
			elif role.ends_with("LowerArm") or role.ends_with("Hand"):
				rest.origin *= 1.25
			elif role.ends_with("LowerLeg") or role.ends_with("Foot"):
				rest.origin *= 0.85
			original.set_bone_rest(index, rest)
			original.set_bone_pose(index, rest)
	var roles: Array[String] = []
	var mapping := {}
	var globals := {}
	var omitted: Array = []
	if recipe.get("torso", 3) < 3:
		omitted.append("UpperChest")
	if recipe.get("torso", 3) < 2:
		omitted.append("Chest")
	if recipe.get("hips_only", false):
		omitted.append("Root")
	if recipe.get("minimal", false):
		omitted.append_array(["Neck", "LeftShoulder", "RightShoulder", "LeftToes", "RightToes", "Jaw", "LeftEye", "RightEye"])
	for index in original.get_bone_count():
		var role := String(original.get_bone_name(index))
		if role in omitted:
			continue
		if recipe.get("digits", 5) == 4 and role.contains("Little"):
			continue
		if recipe.get("digits", 5) == 0 and (role.contains("Thumb") or role.contains("Index") or role.contains("Middle") or role.contains("Ring") or role.contains("Little")):
			continue
		if recipe.get("short_digits", false) and role.contains("Intermediate"):
			continue
		roles.append(role)
		var global_rest := original.get_bone_global_rest(index)
		global_rest.origin *= float(recipe.get("scale", 1.0))
		if recipe.get("axes", false):
			global_rest.basis = global_rest.basis * Basis(Vector3(0.3, 0.7, 0.2).normalized(), 0.37 + index * 0.013)
		globals[role] = global_rest
	if recipe.get("reverse", false):
		roles.reverse()
	var skeleton := Skeleton3D.new()
	skeleton.name = "Rig"
	var indices := {}
	for role in roles:
		indices[role] = skeleton.get_bone_count()
		var name := _name(role, String(recipe.get("names", "canonical")), indices[role])
		skeleton.add_bone(name)
		mapping[role] = name
	for role in roles:
		var parent := original.get_bone_parent(original.find_bone(role))
		while parent >= 0 and String(original.get_bone_name(parent)) not in roles:
			parent = original.get_bone_parent(parent)
		var rest: Transform3D = globals[role]
		if parent >= 0:
			var parent_role := String(original.get_bone_name(parent))
			skeleton.set_bone_parent(indices[role], indices[parent_role])
			rest = (globals[parent_role] as Transform3D).affine_inverse() * rest
		skeleton.set_bone_rest(indices[role], rest)
		skeleton.set_bone_pose(indices[role], rest)
	# Hair plus a grandchild tests unmapped branch inheritance, not just no tracks.
	for name in ["Accessory", "AccessoryTip", "ArmTwist"]:
		var index := skeleton.get_bone_count()
		skeleton.add_bone(name)
		var parent: int = indices["Head"] if name == "Accessory" else index - 1
		if name == "ArmTwist":
			parent = indices["LeftUpperArm"]
		skeleton.set_bone_parent(index, parent)
		var rest := Transform3D(Basis(Vector3.UP, 0.2), Vector3(0.04, 0.08, -0.06))
		skeleton.set_bone_rest(index, rest)
		skeleton.set_bone_pose(index, rest)
	original.free()
	if recipe.get("common_pelvis", false):
		# A common body helper carries torso + an unmapped colocated hip branch.
		# Preserve every original joint's global rest when adding the branch.
		var body := skeleton.find_bone(mapping["Hips"])
		var body_name := _name("Body", recipe.get("names", "canonical"), body)
		skeleton.set_bone_name(body, body_name)
		mapping["Hips"] = body_name
		var helper := skeleton.get_bone_count()
		skeleton.add_bone(_name("Hip", recipe.get("names", "canonical"), helper))
		skeleton.set_bone_parent(helper, body)
		var helper_rest := Transform3D(Basis(Vector3.UP, 0.27), Vector3.ZERO)
		skeleton.set_bone_rest(helper, helper_rest)
		skeleton.set_bone_pose(helper, helper_rest)
		for role in ["LeftUpperLeg", "RightUpperLeg"]:
			var index := skeleton.find_bone(mapping[role])
			var rest := helper_rest.affine_inverse() * skeleton.get_bone_rest(index)
			skeleton.set_bone_parent(index, helper)
			skeleton.set_bone_rest(index, rest)
			skeleton.set_bone_pose(index, rest)
	var scene := Node3D.new()
	scene.name = "SyntheticCharacter"
	scene.add_child(skeleton)
	skeleton.owner = scene
	var skin := Skin.new()
	var bind_shape := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(recipe.get("bind_scale", 1.0))), Vector3.ZERO)
	for index in skeleton.get_bone_count():
		skin.add_named_bind(skeleton.get_bone_name(index), skeleton.get_bone_global_rest(index).affine_inverse() * bind_shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "SkinMesh"
	mesh.mesh = BoxMesh.new()
	mesh.skin = skin
	skeleton.add_child(mesh)
	mesh.skeleton = NodePath("..")
	mesh.owner = scene
	return {"scene": scene, "skeleton": skeleton, "mapping": mapping}

static func _name(role: String, convention: String, index: int) -> String:
	if convention == "opaque":
		return "joint_%03d" % index
	if convention == "namespace":
		return "Armature_" + role
	if convention == "mixamo":
		var body := {"LeftUpperArm":"LeftArm", "RightUpperArm":"RightArm", "LeftLowerArm":"LeftForeArm", "RightLowerArm":"RightForeArm", "LeftUpperLeg":"LeftUpLeg", "RightUpperLeg":"RightUpLeg", "LeftLowerLeg":"LeftLeg", "RightLowerLeg":"RightLeg", "Chest":"Spine1", "UpperChest":"Spine2"}
		for side in ["Left", "Right"]:
			for digit in ["Thumb", "Index", "Middle", "Ring", "Little"]:
				var joints := ["Metacarpal", "Proximal", "Distal"] if digit == "Thumb" else ["Proximal", "Intermediate", "Distal"]
				for joint in joints.size():
					if role == side + digit + joints[joint]:
						return "mixamorig_%sHand%s%d" % [side, "Pinky" if digit == "Little" else digit, joint + 1]
		return "mixamorig_" + String(body.get(role, role))
	if convention == "sided":
		var body := {"UpperArm":"upperarm", "LowerArm":"lowerarm", "UpperLeg":"thigh", "LowerLeg":"calf", "Shoulder":"clavicle", "Toes":"ball"}
		var core := {"Hips":"pelvis", "Spine":"spine_01", "Chest":"spine_02", "UpperChest":"spine_03", "Neck":"neck_01"}
		if core.has(role):
			return core[role]
		for side in ["Left", "Right"]:
			if role.begins_with(side):
				var part := role.trim_prefix(side)
				for digit in ["Thumb", "Index", "Middle", "Ring", "Little"]:
					var joints := ["Metacarpal", "Proximal", "Distal"] if digit == "Thumb" else ["Proximal", "Intermediate", "Distal"]
					for joint in joints.size():
						if part == digit + joints[joint]:
							part = digit.to_lower() + "_%02d" % (joint + 1)
				return String(body.get(part, part.to_lower())) + (".l" if side == "Left" else ".r")
		return role.to_lower()
	return role

class_name HumanoidFixture
extends RefCounted

const SKELETON_NODE_NAME := "HumanoidSkeleton"
const ARM_DROP_RADIANS := deg_to_rad(32.0)


static func create_skeleton() -> Skeleton3D:
	var profile := SkeletonProfileHumanoid.new()
	var skeleton := Skeleton3D.new()
	skeleton.name = SKELETON_NODE_NAME
	for index in profile.get_bone_size():
		var bone_name := profile.get_bone_name(index)
		skeleton.add_bone(bone_name)
		var parent_name := profile.get_bone_parent(index)
		if not parent_name.is_empty():
			skeleton.set_bone_parent(index, skeleton.find_bone(parent_name))
		var rest := _fixture_rest(bone_name, profile.get_reference_pose(index))
		skeleton.set_bone_rest(index, rest)
		skeleton.set_bone_pose(index, rest)
	return skeleton


static func create_scene() -> Node3D:
	var scene := Node3D.new()
	scene.name = "GodotHumanoidAPose"
	var skeleton := create_skeleton()
	scene.add_child(skeleton)
	skeleton.owner = scene
	return scene


static func _fixture_rest(bone_name: StringName, profile_rest: Transform3D) -> Transform3D:
	var rest := profile_rest
	# Distinct but plausible proportions: taller torso and legs, broader
	# shoulders, and longer arms than the one-meter reference profile.
	var name := String(bone_name)
	if name == "Hips":
		rest.origin.y = 0.9
	elif name in ["Spine", "Chest", "UpperChest"]:
		rest.origin.y *= 1.18
	elif name in ["Neck", "Head"]:
		rest.origin.y *= 1.12
	elif name in ["LeftShoulder", "RightShoulder"]:
		rest.origin *= 1.2
	elif name in ["LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand"]:
		rest.origin.y *= 1.14
	elif name in ["LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot"]:
		rest.origin.y *= 1.16
	elif name in ["LeftToes", "RightToes"]:
		rest.origin.y *= 1.1

	# Rotate the upper-arm rest bases away from the canonical T-pose. Their
	# children therefore form a visible A-pose while retaining profile axes.
	if name == "LeftUpperArm":
		rest.basis = rest.basis * Basis(Vector3.RIGHT, ARM_DROP_RADIANS)
	elif name == "RightUpperArm":
		rest.basis = rest.basis * Basis(Vector3.RIGHT, ARM_DROP_RADIANS)
	return rest

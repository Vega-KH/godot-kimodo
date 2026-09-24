class_name Soma77HumanoidMap
extends RefCounted

# The target names are Godot SkeletonProfileHumanoid names. Intermediate SOMA
# joints are intentionally collapsed by model-space rest-delta transfer.
const TARGET_TO_SOURCE := {
	"Hips": "Hips",
	"Spine": "Spine1",
	"Chest": "Spine2",
	"UpperChest": "Chest",
	"Neck": "Neck2",
	"Head": "Head",
	"LeftShoulder": "LeftShoulder",
	"LeftUpperArm": "LeftArm",
	"LeftLowerArm": "LeftForeArm",
	"LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder",
	"RightUpperArm": "RightArm",
	"RightLowerArm": "RightForeArm",
	"RightHand": "RightHand",
	"LeftUpperLeg": "LeftLeg",
	"LeftLowerLeg": "LeftShin",
	"LeftFoot": "LeftFoot",
	"LeftToes": "LeftToeBase",
	"RightUpperLeg": "RightLeg",
	"RightLowerLeg": "RightShin",
	"RightFoot": "RightFoot",
	"RightToes": "RightToeBase",
}

const REQUIRED_TARGETS := [
	"Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
]

# The primary semantic child defines the visible direction of each non-leaf
# body segment. Retargeting aligns these rest directions before applying the
# source motion, so A/T-pose and exporter-axis differences do not leak into the
# animated pose.
const DIRECTION_CHILDREN := {
	"Hips": "Spine",
	"Spine": "Chest",
	"Chest": "UpperChest",
	"UpperChest": "Neck",
	"Neck": "Head",
	"LeftShoulder": "LeftUpperArm",
	"LeftUpperArm": "LeftLowerArm",
	"LeftLowerArm": "LeftHand",
	"RightShoulder": "RightUpperArm",
	"RightUpperArm": "RightLowerArm",
	"RightLowerArm": "RightHand",
	"LeftUpperLeg": "LeftLowerLeg",
	"LeftLowerLeg": "LeftFoot",
	"LeftFoot": "LeftToes",
	"RightUpperLeg": "RightLowerLeg",
	"RightLowerLeg": "RightFoot",
	"RightFoot": "RightToes",
}

const DIRECTION_SOURCE_CHILD_OVERRIDES := {
	# UpperChest collapses SOMA's first neck segment. Its visible direction is
	# therefore Chest -> Neck1, while target Neck rotation still maps Neck2.
	"UpperChest": "Neck1",
}

const COLLAPSED_SOURCE_JOINTS := ["Neck1"]
const IGNORED_FACE_JOINTS := ["HeadEnd", "Jaw", "LeftEye", "RightEye"]
const IGNORED_TOE_END_JOINTS := ["LeftToeEnd", "RightToeEnd"]


static func ignored_finger_joints() -> Array[String]:
	var ignored: Array[String] = []
	for name in Soma77Contract.JOINT_NAMES:
		if String(name).contains("Hand") and not String(name).ends_with("Hand"):
			ignored.append(name)
	return ignored


static func source_for_target(target_name: StringName) -> StringName:
	return StringName(TARGET_TO_SOURCE.get(String(target_name), ""))


static func direction_child_for_target(target_name: StringName) -> StringName:
	return StringName(DIRECTION_CHILDREN.get(String(target_name), ""))


static func source_direction_child_for_target(target_name: StringName) -> StringName:
	if DIRECTION_SOURCE_CHILD_OVERRIDES.has(String(target_name)):
		return StringName(DIRECTION_SOURCE_CHILD_OVERRIDES[String(target_name)])
	return source_for_target(direction_child_for_target(target_name))


static func validate(source: Skeleton3D, target: Skeleton3D) -> String:
	if source == null or target == null:
		return "Retargeting requires source and target Skeleton3D nodes"
	if source.get_bone_count() != Soma77Contract.JOINT_NAMES.size():
		return "Source skeleton must contain the canonical 77 SOMA joints"
	for index in Soma77Contract.JOINT_NAMES.size():
		if source.get_bone_name(index) != Soma77Contract.JOINT_NAMES[index]:
			return "Source skeleton is not canonical SOMA-77 at bone %d" % index
	for target_name in REQUIRED_TARGETS:
		var source_name: StringName = source_for_target(target_name)
		if target.find_bone(target_name) < 0:
			return "Target humanoid is missing required bone %s" % target_name
		if source.find_bone(source_name) < 0:
			return "SOMA-77 source is missing mapped bone %s" % source_name
	return ""

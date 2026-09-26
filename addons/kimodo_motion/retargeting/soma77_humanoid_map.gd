class_name Soma77HumanoidMap
extends RefCounted

const RestOrientation := preload(
	"res://addons/kimodo_motion/retargeting/rest_orientation.gd"
)

# The target names are Godot SkeletonProfileHumanoid names. Intermediate SOMA
# joints are intentionally collapsed by model-space rest-delta transfer.
const TARGET_TO_SOURCE := {
	"Hips": "Hips",
	"Spine": "Spine1",
	"Chest": "Spine2",
	"UpperChest": "Chest",
	"Neck": "Neck2",
	"Head": "Head",
	"LeftEye": "LeftEye",
	"RightEye": "RightEye",
	"Jaw": "Jaw",
	"LeftShoulder": "LeftShoulder",
	"LeftUpperArm": "LeftArm",
	"LeftLowerArm": "LeftForeArm",
	"LeftHand": "LeftHand",
	"LeftThumbMetacarpal": "LeftHandThumb1",
	"LeftThumbProximal": "LeftHandThumb2",
	"LeftThumbDistal": "LeftHandThumb3",
	"LeftIndexProximal": "LeftHandIndex2",
	"LeftIndexIntermediate": "LeftHandIndex3",
	"LeftIndexDistal": "LeftHandIndex4",
	"LeftMiddleProximal": "LeftHandMiddle2",
	"LeftMiddleIntermediate": "LeftHandMiddle3",
	"LeftMiddleDistal": "LeftHandMiddle4",
	"LeftRingProximal": "LeftHandRing2",
	"LeftRingIntermediate": "LeftHandRing3",
	"LeftRingDistal": "LeftHandRing4",
	"LeftLittleProximal": "LeftHandPinky2",
	"LeftLittleIntermediate": "LeftHandPinky3",
	"LeftLittleDistal": "LeftHandPinky4",
	"RightShoulder": "RightShoulder",
	"RightUpperArm": "RightArm",
	"RightLowerArm": "RightForeArm",
	"RightHand": "RightHand",
	"RightThumbMetacarpal": "RightHandThumb1",
	"RightThumbProximal": "RightHandThumb2",
	"RightThumbDistal": "RightHandThumb3",
	"RightIndexProximal": "RightHandIndex2",
	"RightIndexIntermediate": "RightHandIndex3",
	"RightIndexDistal": "RightHandIndex4",
	"RightMiddleProximal": "RightHandMiddle2",
	"RightMiddleIntermediate": "RightHandMiddle3",
	"RightMiddleDistal": "RightHandMiddle4",
	"RightRingProximal": "RightHandRing2",
	"RightRingIntermediate": "RightHandRing3",
	"RightRingDistal": "RightHandRing4",
	"RightLittleProximal": "RightHandPinky2",
	"RightLittleIntermediate": "RightHandPinky3",
	"RightLittleDistal": "RightHandPinky4",
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
	"LeftEye", "RightEye", "Jaw",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"LeftThumbMetacarpal", "LeftThumbProximal", "LeftThumbDistal",
	"LeftIndexProximal", "LeftIndexIntermediate", "LeftIndexDistal",
	"LeftMiddleProximal", "LeftMiddleIntermediate", "LeftMiddleDistal",
	"LeftRingProximal", "LeftRingIntermediate", "LeftRingDistal",
	"LeftLittleProximal", "LeftLittleIntermediate", "LeftLittleDistal",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"RightThumbMetacarpal", "RightThumbProximal", "RightThumbDistal",
	"RightIndexProximal", "RightIndexIntermediate", "RightIndexDistal",
	"RightMiddleProximal", "RightMiddleIntermediate", "RightMiddleDistal",
	"RightRingProximal", "RightRingIntermediate", "RightRingDistal",
	"RightLittleProximal", "RightLittleIntermediate", "RightLittleDistal",
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
	"LeftThumbMetacarpal": "LeftThumbProximal",
	"LeftThumbProximal": "LeftThumbDistal",
	"LeftIndexProximal": "LeftIndexIntermediate",
	"LeftIndexIntermediate": "LeftIndexDistal",
	"LeftMiddleProximal": "LeftMiddleIntermediate",
	"LeftMiddleIntermediate": "LeftMiddleDistal",
	"LeftRingProximal": "LeftRingIntermediate",
	"LeftRingIntermediate": "LeftRingDistal",
	"LeftLittleProximal": "LeftLittleIntermediate",
	"LeftLittleIntermediate": "LeftLittleDistal",
	"RightShoulder": "RightUpperArm",
	"RightUpperArm": "RightLowerArm",
	"RightLowerArm": "RightHand",
	"RightThumbMetacarpal": "RightThumbProximal",
	"RightThumbProximal": "RightThumbDistal",
	"RightIndexProximal": "RightIndexIntermediate",
	"RightIndexIntermediate": "RightIndexDistal",
	"RightMiddleProximal": "RightMiddleIntermediate",
	"RightMiddleIntermediate": "RightMiddleDistal",
	"RightRingProximal": "RightRingIntermediate",
	"RightRingIntermediate": "RightRingDistal",
	"RightLittleProximal": "RightLittleIntermediate",
	"RightLittleIntermediate": "RightLittleDistal",
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

# Hands need a complete anatomical frame rather than the one-vector direction
# correction used by limb segments. The forward and lateral axes preserve both
# wrist flexion and palm roll across rigs with different bone rest bases.
const ORIENTATION_FRAMES := {
	"LeftHand": {
		"forward": "LeftMiddleProximal",
		"lateral_from": "LeftIndexProximal",
		"lateral_to": "LeftLittleProximal",
	},
	"RightHand": {
		"forward": "RightMiddleProximal",
		"lateral_from": "RightIndexProximal",
		"lateral_to": "RightLittleProximal",
	},
}

const COLLAPSED_SOURCE_JOINTS := [
	"Neck1",
	"LeftHandIndex1", "LeftHandMiddle1", "LeftHandRing1", "LeftHandPinky1",
	"RightHandIndex1", "RightHandMiddle1", "RightHandRing1", "RightHandPinky1",
]
const IGNORED_TERMINAL_JOINTS := [
	"HeadEnd",
	"LeftHandThumbEnd", "LeftHandIndexEnd", "LeftHandMiddleEnd",
	"LeftHandRingEnd", "LeftHandPinkyEnd",
	"RightHandThumbEnd", "RightHandIndexEnd", "RightHandMiddleEnd",
	"RightHandRingEnd", "RightHandPinkyEnd",
	"LeftToeEnd", "RightToeEnd",
]


static func source_for_target(target_name: StringName) -> StringName:
	return StringName(TARGET_TO_SOURCE.get(String(target_name), ""))


static func direction_child_for_target(target_name: StringName) -> StringName:
	return StringName(DIRECTION_CHILDREN.get(String(target_name), ""))


static func source_direction_child_for_target(target_name: StringName) -> StringName:
	if DIRECTION_SOURCE_CHILD_OVERRIDES.has(String(target_name)):
		return StringName(DIRECTION_SOURCE_CHILD_OVERRIDES[String(target_name)])
	return source_for_target(direction_child_for_target(target_name))


static func orientation_frame_for_target(target_name: StringName) -> Dictionary:
	return ORIENTATION_FRAMES.get(String(target_name), {})


static func source_dispositions() -> Dictionary:
	var dispositions := {}
	for target_name in REQUIRED_TARGETS:
		dispositions[String(source_for_target(target_name))] = "mapped:%s" % target_name
	for source_name in COLLAPSED_SOURCE_JOINTS:
		dispositions[source_name] = "collapsed"
	for source_name in IGNORED_TERMINAL_JOINTS:
		dispositions[source_name] = "terminal"
	return dispositions


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
	var dispositions := source_dispositions()
	if dispositions.size() != Soma77Contract.JOINT_NAMES.size():
		return "SOMA-77 profile must account for all 77 source joints"
	for source_name in Soma77Contract.JOINT_NAMES:
		if not dispositions.has(String(source_name)):
			return "SOMA-77 profile does not account for source joint %s" % source_name
	var source_rests := _global_rests(source)
	var target_rests := _global_rests(target)
	for target_name in ORIENTATION_FRAMES:
		var frame: Dictionary = ORIENTATION_FRAMES[target_name]
		var source_frame := RestOrientation.anatomical_frame(
			source,
			source_rests,
			source_for_target(target_name),
			source_for_target(frame["forward"]),
			source_for_target(frame["lateral_from"]),
			source_for_target(frame["lateral_to"]),
		)
		if not source_frame["ok"]:
			return "SOMA-77 %s" % source_frame["message"]
		var target_frame := RestOrientation.anatomical_frame(
			target,
			target_rests,
			target_name,
			frame["forward"],
			frame["lateral_from"],
			frame["lateral_to"],
		)
		if not target_frame["ok"]:
			return "Humanoid %s" % target_frame["message"]
	return ""


static func _global_rests(skeleton: Skeleton3D) -> Array[Transform3D]:
	var rests: Array[Transform3D] = []
	rests.resize(skeleton.get_bone_count())
	for index in skeleton.get_bone_count():
		var local := skeleton.get_bone_rest(index)
		var parent := skeleton.get_bone_parent(index)
		rests[index] = local if parent < 0 else rests[parent] * local
	return rests

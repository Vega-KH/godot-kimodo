class_name Soma77Contract
extends RefCounted

const JOINT_NAMES := [
	"Hips", "Spine1", "Spine2", "Chest", "Neck1", "Neck2", "Head", "HeadEnd", "Jaw",
	"LeftEye", "RightEye", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"LeftHandThumb1", "LeftHandThumb2", "LeftHandThumb3", "LeftHandThumbEnd",
	"LeftHandIndex1", "LeftHandIndex2", "LeftHandIndex3", "LeftHandIndex4",
	"LeftHandIndexEnd", "LeftHandMiddle1", "LeftHandMiddle2", "LeftHandMiddle3",
	"LeftHandMiddle4", "LeftHandMiddleEnd", "LeftHandRing1", "LeftHandRing2",
	"LeftHandRing3", "LeftHandRing4", "LeftHandRingEnd", "LeftHandPinky1",
	"LeftHandPinky2", "LeftHandPinky3", "LeftHandPinky4", "LeftHandPinkyEnd",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand", "RightHandThumb1",
	"RightHandThumb2", "RightHandThumb3", "RightHandThumbEnd", "RightHandIndex1",
	"RightHandIndex2", "RightHandIndex3", "RightHandIndex4", "RightHandIndexEnd",
	"RightHandMiddle1", "RightHandMiddle2", "RightHandMiddle3", "RightHandMiddle4",
	"RightHandMiddleEnd", "RightHandRing1", "RightHandRing2", "RightHandRing3",
	"RightHandRing4", "RightHandRingEnd", "RightHandPinky1", "RightHandPinky2",
	"RightHandPinky3", "RightHandPinky4", "RightHandPinkyEnd", "LeftLeg", "LeftShin",
	"LeftFoot", "LeftToeBase", "LeftToeEnd", "RightLeg", "RightShin", "RightFoot",
	"RightToeBase", "RightToeEnd",
]

const CONTACT_JOINTS := [
	"LeftFoot", "LeftToeBase", "LeftToeEnd",
	"RightFoot", "RightToeBase", "RightToeEnd",
]

const CONSTRAINT_TYPES := ["root_path", "effector_target", "pose_keyframe"]

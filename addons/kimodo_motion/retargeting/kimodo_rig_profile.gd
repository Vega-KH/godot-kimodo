@tool
class_name KimodoRigProfile
extends Resource

const SCHEMA_VERSION := 2
const ROOT_SEPARATE := "separate_root"
const ROOT_HIPS_ONLY := "hips_only"
const REQUIRED_BODY := ["Hips", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]
const HumanoidMap := preload("res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd")
const Geometry := preload("res://addons/kimodo_motion/retargeting/rig_geometry.gd")
const Orientation := preload("res://addons/kimodo_motion/retargeting/rest_orientation.gd")
const TORSO := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"]
const DIGIT_JOINTS := {"Thumb": ["Metacarpal", "Proximal", "Distal"], "Index": ["Proximal", "Intermediate", "Distal"], "Middle": ["Proximal", "Intermediate", "Distal"], "Ring": ["Proximal", "Intermediate", "Distal"], "Little": ["Proximal", "Intermediate", "Distal"]}

@export var schema_version := SCHEMA_VERSION
@export_file("*.tscn", "*.scn", "*.glb", "*.gltf", "*.fbx") var target_scene_path := ""
@export var target_scene_signature := ""
@export var target_skeleton_signature := ""
@export var skeleton_path := NodePath()
@export var canonical_to_target: Dictionary = {}
@export_enum("Separate Root:separate_root", "Hips Is Root:hips_only") var root_motion_policy := ROOT_SEPARATE
@export_enum("Preserve Units:none", "Scale by Leg Height:leg_height") var translation_scale_policy := "none"
@export var reference_measurements: Dictionary = {}
@export var ignored_optional_roles: Array[String] = []
@export var certification: Dictionary = {}
# Source landmarks are canonical humanoid roles; target landmarks are actual
# target bone names. Explicit pairs support unconventional/manual mappings.
@export var hand_frames: Dictionary = {}

var target_to_canonical: Dictionary = {}

static func exact_names(skeleton: Skeleton3D, path: NodePath) -> Dictionary:
	if skeleton == null:
		return _error("Character target has no Skeleton3D")
	var mapping := {}
	var root_policy := ROOT_HIPS_ONLY
	if skeleton.find_bone("Root") >= 0:
		mapping["Root"] = "Root"
		root_policy = ROOT_SEPARATE
	for role in HumanoidMap.REQUIRED_TARGETS:
		if skeleton.find_bone(role) >= 0:
			mapping[String(role)] = String(role)
		elif String(role) in REQUIRED_BODY:
			return _error("Character skeleton is missing required bone %s" % role)
	return create(mapping, path, skeleton, root_policy)

static func create(mapping: Dictionary, path: NodePath, skeleton: Skeleton3D, root_policy := ROOT_SEPARATE, scale_policy := "none", frames: Dictionary = {}) -> Dictionary:
	var profile := KimodoRigProfile.new()
	profile.skeleton_path = path
	profile.root_motion_policy = root_policy
	profile.translation_scale_policy = scale_policy
	profile.canonical_to_target = mapping.duplicate(true)
	profile.hand_frames = (suggest_hand_frames(mapping) if frames.is_empty() else frames).duplicate(true)
	for role in HumanoidMap.REQUIRED_TARGETS:
		if String(role) not in REQUIRED_BODY and not mapping.has(String(role)):
			profile.ignored_optional_roles.append(String(role))
	profile.reference_measurements = measure(skeleton, mapping)
	var error := profile.validate_for(skeleton)
	if not error.is_empty():
		return _error(error)
	profile.rebuild_reverse_map()
	return {"ok": true, "profile": profile}

func validate_for(skeleton: Skeleton3D) -> String:
	if schema_version != SCHEMA_VERSION:
		return "Unsupported rig profile schema version %d" % schema_version
	if skeleton == null:
		return "Character target has no Skeleton3D"
	if root_motion_policy not in [ROOT_SEPARATE, ROOT_HIPS_ONLY]:
		return "Rig profile has an unsupported root-motion policy"
	if translation_scale_policy not in ["none", "leg_height"]:
		return "Choose a supported translation scale policy."
	var required: Array = REQUIRED_BODY.duplicate()
	if root_motion_policy == ROOT_SEPARATE:
		required.push_front("Root")
	var used := {}
	for role in canonical_to_target:
		if String(role) != "Root" and String(role) not in HumanoidMap.REQUIRED_TARGETS:
			return "Unknown semantic role '%s'. Choose a supported role in Rig Setup." % role
		var target := String(canonical_to_target[role])
		if target.is_empty() or skeleton.find_bone(target) < 0:
			return "Rig profile target bone %s does not exist" % target
		if used.has(target):
			return "Bone '%s' is assigned to both %s and %s. Choose a distinct bone for each role in Rig Setup." % [target, used[target], role]
		used[target] = String(role)
	for role in required:
		if not canonical_to_target.has(role) or String(canonical_to_target[role]).is_empty():
			return "Required role '%s' is unmapped. Select its corresponding character bone in Rig Setup." % role
	if not canonical_to_target.has("Spine") and not canonical_to_target.has("Chest") and not canonical_to_target.has("UpperChest"):
		return "No torso segment is mapped. Map at least one Spine, Chest, or UpperChest bone between Hips and Head."
	if root_motion_policy == ROOT_HIPS_ONLY and canonical_to_target.has("Root"):
		return "A Hips-is-root profile must not map a separate Root"
	var rests := Geometry.global_rests(skeleton)
	for index in skeleton.get_bone_count():
		if not rests[index].is_finite() or absf(rests[index].basis.determinant()) < 0.000001:
			return "Bone '%s' has an invalid rest transform. Correct it in your modeling tool before mapping." % skeleton.get_bone_name(index)
		var basis_issue := Geometry.rest_basis_issue(rests[index].basis)
		if not basis_issue.is_empty():
			return "Bone '%s' has %s in its accumulated rest transform. Correct bone scale/shear and preserve matching bind/rest poses before re-export; rotation-only transfer does not support this basis." % [skeleton.get_bone_name(index), basis_issue]
	for chain in semantic_chains():
		var previous := ""
		for role in chain:
			if not canonical_to_target.has(role):
				continue
			if not previous.is_empty():
				var parent_name := String(canonical_to_target[previous])
				var child_name := String(canonical_to_target[role])
				if not Geometry.descendant(skeleton, child_name, parent_name):
					var actual_parent := skeleton.get_bone_parent(skeleton.find_bone(child_name))
					var actual_name := String(skeleton.get_bone_name(actual_parent)) if actual_parent >= 0 else "(skeleton root)"
					return "%s ('%s') must descend from %s ('%s'); its actual parent is '%s'. Review the ancestor chain and bone map. A genuinely separate control-driven branch needs a compatible game/deform hierarchy; changing names alone will not repair it." % [role, child_name, previous, parent_name, actual_name]
				if rests[skeleton.find_bone(parent_name)].origin.distance_to(rests[skeleton.find_bone(child_name)].origin) <= 0.00001:
					return "%s ('%s') and %s ('%s') have zero-length rest geometry. Choose distinct anatomical joints; an optional colocated helper may be left unmapped. Do not omit a required joint or alter the bind pose merely to bypass this check." % [previous, parent_name, role, child_name]
			previous = role
	for hand in ["LeftHand", "RightHand"]:
		var frame: Dictionary = hand_frames.get(hand, {})
		for key in ["forward", "lateral_from", "lateral_to"]:
			var source_role := String(frame.get("source_" + key, ""))
			var target_name := String(frame.get("target_" + key, ""))
			if source_role not in palm_source_roles(hand):
				return "%s palm frame needs a valid source %s landmark. Review Hand Frames in Rig Setup." % [hand, key]
			if target_name.is_empty() or not Geometry.descendant(skeleton, target_name, String(canonical_to_target[hand])):
				return "%s palm frame needs a %s landmark below its hand bone. Select an available finger/palm bone in Hand Frames; this rig cannot be certified without enough palm geometry." % [hand, key]
		var result := Orientation.anatomical_frame(skeleton, rests, canonical_to_target[hand], frame["target_forward"], frame["target_lateral_from"], frame["target_lateral_to"])
		if not result["ok"]:
			return "%s. Choose non-collinear palm landmarks in Hand Frames." % result["message"]
	return ""

func certify(skeleton: Skeleton3D, skeleton_signature: String) -> Dictionary:
	var error := validate_for(skeleton)
	if not error.is_empty():
		certification = {"certified": false, "message": error}
		return {"ok": false, "message": error}
	target_skeleton_signature = skeleton_signature
	reference_measurements = measure(skeleton, canonical_to_target)
	rebuild_reverse_map()
	certification = {"certified": true, "schema_version": SCHEMA_VERSION, "skeleton_signature": skeleton_signature, "validated_roles": canonical_to_target.size()}
	return {"ok": true}

func is_current(skeleton: Skeleton3D, signature: String) -> bool:
	return bool(certification.get("certified", false)) and not signature.is_empty() and target_skeleton_signature == signature and validate_for(skeleton).is_empty()

func rebuild_reverse_map() -> void:
	target_to_canonical.clear()
	for role in canonical_to_target:
		var target := String(canonical_to_target[role])
		if not target.is_empty():
			target_to_canonical[target] = String(role)

func target_for(canonical_name: StringName) -> StringName:
	return StringName(canonical_to_target.get(String(canonical_name), ""))

func canonical_for(target_name: StringName) -> StringName:
	if target_to_canonical.is_empty() and not canonical_to_target.is_empty():
		rebuild_reverse_map()
	return StringName(target_to_canonical.get(String(target_name), ""))

func rotation_targets() -> Array[StringName]:
	var result: Array[StringName] = []
	for role in HumanoidMap.REQUIRED_TARGETS:
		if canonical_to_target.has(String(role)):
			result.append(role)
	return result

func translation_scale(source: Skeleton3D) -> float:
	if translation_scale_policy != "leg_height":
		return 1.0
	var source_mapping := {}
	for role in HumanoidMap.REQUIRED_TARGETS:
		source_mapping[String(role)] = String(role)
	var source_measurements := measure(source, source_mapping)
	var source_leg := float(source_measurements.get("leg_height", 0.0))
	var target_leg := float(reference_measurements.get("leg_height", 0.0))
	return target_leg / source_leg if source_leg > 0.000001 and target_leg > 0.000001 else 1.0

static func measure(skeleton: Skeleton3D, mapping: Dictionary) -> Dictionary:
	if skeleton == null:
		return {}
	var rests := _global_rests(skeleton)
	var hips := _mapped_origin(skeleton, rests, mapping, "Hips")
	var feet := (_mapped_origin(skeleton, rests, mapping, "LeftFoot") + _mapped_origin(skeleton, rests, mapping, "RightFoot")) * 0.5
	var head := _mapped_origin(skeleton, rests, mapping, "Head")
	return {"leg_height": hips.distance_to(feet), "body_height": head.distance_to(feet)}

static func _mapped_origin(skeleton: Skeleton3D, rests: Array[Transform3D], mapping: Dictionary, role: String) -> Vector3:
	var index := skeleton.find_bone(String(mapping.get(role, "")))
	return rests[index].origin if index >= 0 else Vector3.ZERO

static func _global_rests(skeleton: Skeleton3D) -> Array[Transform3D]:
	return Geometry.global_rests(skeleton)

static func suggest_hand_frames(mapping: Dictionary) -> Dictionary:
	var result := {}
	for side in ["Left", "Right"]:
		var candidates: Array[String] = []
		for digit in ["Index", "Middle", "Ring", "Little"]:
			for joint in DIGIT_JOINTS[digit]:
				var role: String = side + digit + joint
				if mapping.has(role):
					candidates.append(role)
					break
		var frame := {}
		var forward: String = side + "MiddleProximal"
		if not mapping.has(forward) and not candidates.is_empty():
			forward = candidates[candidates.size() / 2]
		var first: String = candidates[0] if not candidates.is_empty() else side + "IndexProximal"
		var last: String = candidates[-1] if candidates.size() > 1 else side + "LittleProximal"
		for pair in [["forward", forward], ["lateral_from", first], ["lateral_to", last]]:
			frame["source_" + pair[0]] = pair[1]
			frame["target_" + pair[0]] = String(mapping.get(pair[1], ""))
		result[side + "Hand"] = frame
	return result

static func palm_source_roles(hand: String) -> Array[String]:
	var result: Array[String] = []
	for digit in DIGIT_JOINTS:
		for joint in DIGIT_JOINTS[digit]:
			result.append(hand.trim_suffix("Hand") + digit + joint)
	return result

static func semantic_chains() -> Array:
	var result: Array = [TORSO, ["Root", "Hips"], ["Head", "LeftEye"], ["Head", "RightEye"], ["Head", "Jaw"]]
	for side in ["Left", "Right"]:
		result.append(["Hips", "Spine", "Chest", "UpperChest", side + "Shoulder", side + "UpperArm", side + "LowerArm", side + "Hand"])
		result.append(["Hips", side + "UpperLeg", side + "LowerLeg", side + "Foot", side + "Toes"])
		for digit in DIGIT_JOINTS:
			var chain: Array = [side + "Hand"]
			for joint in DIGIT_JOINTS[digit]:
				chain.append(side + digit + joint)
			result.append(chain)
	return result

func direction_child(role: StringName) -> StringName:
	# Select the next mapped role on the same semantic chain, crossing omitted
	# intermediates without discarding their source world-space motion.
	var child := HumanoidMap.direction_child_for_target(role)
	while not child.is_empty() and target_for(child).is_empty():
		child = HumanoidMap.direction_child_for_target(child)
	return child

func upgrade_legacy(skeleton: Skeleton3D, signature: String) -> bool:
	if schema_version != 1 or not bool(certification.get("certified", false)) or target_skeleton_signature != signature:
		return false
	schema_version = SCHEMA_VERSION
	hand_frames = suggest_hand_frames(canonical_to_target)
	# Upgrade is in-memory only until the artist explicitly saves the profile.
	return certify(skeleton, signature)["ok"]

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}

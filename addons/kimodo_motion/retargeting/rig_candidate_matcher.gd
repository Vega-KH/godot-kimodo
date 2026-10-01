class_name KimodoRigCandidateMatcher
extends RefCounted

const HumanoidMap := preload("res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd")
const Profile := preload("res://addons/kimodo_motion/retargeting/kimodo_rig_profile.gd")
const Geometry := preload("res://addons/kimodo_motion/retargeting/rig_geometry.gd")

const MIXAMO_ALIASES := {
	"Hips": "hips", "Spine": "spine", "Chest": "spine1", "UpperChest": "spine2",
	"Neck": "neck", "Head": "head", "LeftEye": "lefteye", "RightEye": "righteye",
	"LeftShoulder": "leftshoulder", "LeftUpperArm": "leftarm", "LeftLowerArm": "leftforearm", "LeftHand": "lefthand",
	"RightShoulder": "rightshoulder", "RightUpperArm": "rightarm", "RightLowerArm": "rightforearm", "RightHand": "righthand",
	"LeftUpperLeg": "leftupleg", "LeftLowerLeg": "leftleg", "LeftFoot": "leftfoot", "LeftToes": "lefttoebase",
	"RightUpperLeg": "rightupleg", "RightLowerLeg": "rightleg", "RightFoot": "rightfoot", "RightToes": "righttoebase",
}
const DIGITS := {"Thumb": ["Metacarpal", "Proximal", "Distal"], "Index": ["Proximal", "Intermediate", "Distal"], "Middle": ["Proximal", "Intermediate", "Distal"], "Ring": ["Proximal", "Intermediate", "Distal"], "Little": ["Proximal", "Intermediate", "Distal"]}

static func suggest(skeleton: Skeleton3D) -> Dictionary:
	var roles: Array[String] = ["Root"]
	for role in HumanoidMap.REQUIRED_TARGETS:
		roles.append(String(role))
	var normalized := {}
	for index in skeleton.get_bone_count():
		var bone := String(skeleton.get_bone_name(index))
		var key := normalize(bone)
		if not normalized.has(key):
			normalized[key] = []
		normalized[key].append(bone)
	var suggestions := {}
	for role in roles:
		var row := {"role": role, "target": "", "confidence": "unmatched", "evidence": "Required role needs a manual mapping" if role in Profile.REQUIRED_BODY else "Optional role may be intentionally left unmapped", "required": role in Profile.REQUIRED_BODY or role == "Root", "conflict": false}
		if skeleton.find_bone(role) >= 0:
			row.merge({"target": role, "confidence": "high", "evidence": "Exact Godot humanoid name"}, true)
		else:
			var key := normalize(role)
			if normalized.has(key) and normalized[key].size() == 1:
				row.merge({"target": normalized[key][0], "confidence": "high", "evidence": "Normalized name after namespace/prefix stripping"}, true)
			else:
				var matches: Array[String] = []
				for alias in _aliases_for(role):
					for candidate in normalized.get(alias, []):
						if candidate not in matches:
							matches.append(candidate)
				if matches.size() == 1:
					row.merge({"target": matches[0], "confidence": "high", "evidence": "Curated Mixamo / sided / numbered-chain alias; review hierarchy"}, true)
				elif matches.size() > 1:
					row["evidence"] = "Ambiguous aliases: %s. Choose the deform bone manually." % ", ".join(matches)
		suggestions[role] = row
	# A conservative structural tier is useful on regular rigs with poor names.
	# It suggests only a unique, non-degenerate child on the correct side and
	# labels the result low-confidence so artist review remains explicit.
	for _pass in 3:
		for role in roles:
			if not String(suggestions[role]["target"]).is_empty():
				continue
			var candidate := _structural_candidate(skeleton, role, suggestions)
			if not candidate.is_empty():
				suggestions[role].merge({"target": candidate, "confidence": "low", "evidence": "Unique side + hierarchy + non-degenerate rest-axis candidate; review required"}, true)
	var hips: Dictionary = suggestions["Hips"]
	var root_policy := Profile.ROOT_SEPARATE
	if String(suggestions["Root"]["target"]).is_empty() and not String(hips["target"]).is_empty() and skeleton.get_bone_parent(skeleton.find_bone(hips["target"])) < 0:
		root_policy = Profile.ROOT_HIPS_ONLY
		suggestions["Root"]["required"] = false
		suggestions["Root"]["evidence"] = "Hips is the skeleton root; use the explicit Hips-is-root motion policy"
	_mark_conflicts(suggestions)
	return {"rows": suggestions, "root_motion_policy": root_policy, "hand_frames": Profile.suggest_hand_frames(mapping_from_rows(suggestions))}

static func mapping_from_rows(rows: Dictionary) -> Dictionary:
	var mapping := {}
	for role in rows:
		var target := String(rows[role].get("target", ""))
		if not target.is_empty():
			mapping[String(role)] = target
	return mapping

static func reviewed(profile: Resource, suggestions: Dictionary) -> Dictionary:
	var result := suggestions.duplicate(true)
	result["root_motion_policy"] = profile.root_motion_policy
	result["hand_frames"] = profile.hand_frames.duplicate(true)
	result["rows"]["Root"]["required"] = profile.root_motion_policy == Profile.ROOT_SEPARATE
	for role in result["rows"]:
		var row: Dictionary = result["rows"][role]
		var target := String(profile.canonical_to_target.get(String(role), ""))
		row["target"] = target
		row["conflict"] = false
		if target.is_empty():
			row["confidence"] = "unmapped"
			row["evidence"] = (
				"Certified as intentionally unmapped optional anatomy"
				if String(role) in profile.ignored_optional_roles
				else "Not mapped by the certified profile"
			)
		else:
			row["confidence"] = "certified"
			row["evidence"] = "Saved artist-reviewed profile mapping"
		result["rows"][role] = row
	return result

static func diagnose(skeleton: Skeleton3D, mapping: Dictionary, root_policy: String, frames: Dictionary = {}) -> Array[String]:
	var issues: Array[String] = []
	for side in ["Left", "Right"]:
		for role in mapping:
			if String(role).begins_with(side) and normalize(String(mapping[role])).begins_with(("right" if side == "Left" else "left")):
				issues.append("%s is assigned to the wrong side bone %s" % [role, mapping[role]])
	var created := Profile.create(mapping, NodePath("."), skeleton, root_policy, "none", frames)
	if not created["ok"]:
		issues.append(created["message"])
		return issues
	for parent_role in HumanoidMap.DIRECTION_CHILDREN:
		var child_role: String = HumanoidMap.DIRECTION_CHILDREN[parent_role]
		if mapping.has(parent_role) and mapping.has(child_role) and not _is_descendant(skeleton, String(mapping[child_role]), String(mapping[parent_role])):
			var message := "%s must descend from %s" % [child_role, parent_role]
			if message not in issues:
				issues.append(message)
	var rests := _global_rests(skeleton)
	var measurements := Profile.measure(skeleton, mapping)
	var maximum_segment := maxf(float(measurements.get("body_height", 0.0)) * 1.25, 0.00001)
	for role in HumanoidMap.DIRECTION_CHILDREN:
		var child: String = HumanoidMap.DIRECTION_CHILDREN[role]
		if not mapping.has(role) or not mapping.has(child):
			continue
		var owner_index := skeleton.find_bone(String(mapping[role]))
		var child_index := skeleton.find_bone(String(mapping[child]))
		if owner_index >= 0 and child_index >= 0:
			var segment_length := rests[owner_index].origin.distance_to(rests[child_index].origin)
			if segment_length <= 0.00001:
				issues.append("%s and %s have degenerate rest geometry" % [role, child])
			elif segment_length > maximum_segment:
				issues.append("%s and %s have implausible rest geometry" % [role, child])
	return issues

static func normalize(name: String) -> String:
	var value := name.get_slice(":", name.get_slice_count(":") - 1).to_lower().replace("mixamorig", "")
	for prefix in ["armature_", "skeleton_", "rig_"]:
		value = value.trim_prefix(prefix)
	for side in [["l", "left"], ["r", "right"]]:
		for separator in [".", "_", "-"]:
			if value.ends_with(separator + side[0]):
				value = side[1] + value.trim_suffix(separator + side[0])
			elif value.begins_with(side[0] + separator):
				value = side[1] + value.trim_prefix(side[0] + separator)
	var result := ""
	for character in value:
		if character >= "a" and character <= "z" or character >= "0" and character <= "9":
			result += character
	return result

static func _aliases_for(role: String) -> Array[String]:
	var result: Array[String] = [_alias_for(role)]
	var core := {"Hips": "pelvis", "Spine": "spine01", "Chest": "spine02", "UpperChest": "spine03", "Neck": "neck01"}
	if core.has(role):
		result.append(core[role])
	for side in ["Left", "Right"]:
		var lower: String = side.to_lower()
		var body := {"Shoulder": "clavicle", "UpperArm": "upperarm", "LowerArm": "lowerarm", "Hand": "hand", "UpperLeg": "thigh", "LowerLeg": "calf", "Foot": "foot", "Toes": "ball", "Eye": "eye"}
		for part in body:
			if role == side + part:
				result.append(lower + body[part])
		for digit in DIGITS:
			for joint in DIGITS[digit].size():
				if role == side + digit + DIGITS[digit][joint]:
					result.append(lower + String(digit).to_lower() + "%02d" % (joint + 1))
	return result

static func _alias_for(role: String) -> String:
	if MIXAMO_ALIASES.has(role):
		return MIXAMO_ALIASES[role]
	for side in ["Left", "Right"]:
		for digit in DIGITS:
			var joints: Array = DIGITS[digit]
			for index in joints.size():
				if role == side + digit + joints[index]:
					return (side + "Hand" + ("Pinky" if digit == "Little" else digit) + str(index + 1)).to_lower()
	return normalize(role)

static func _mark_conflicts(rows: Dictionary) -> void:
	var owners := {}
	for role in rows:
		var target := String(rows[role]["target"])
		if target.is_empty():
			continue
		if owners.has(target):
			rows[role]["conflict"] = true
			rows[owners[target]]["conflict"] = true
		else:
			owners[target] = role

static func _structural_candidate(skeleton: Skeleton3D, role: String, rows: Dictionary) -> String:
	var parent_role := _parent_role(role)
	if parent_role.is_empty() or not rows.has(parent_role):
		return ""
	var parent_target := String(rows[parent_role]["target"])
	var parent_index := skeleton.find_bone(parent_target)
	if parent_index < 0:
		return ""
	var rests := _global_rests(skeleton)
	var candidates: Array[String] = []
	for index in skeleton.get_bone_count():
		if skeleton.get_bone_parent(index) != parent_index:
			continue
		var name := String(skeleton.get_bone_name(index))
		var already_used := false
		for row in rows.values():
			if row["target"] == name:
				already_used = true
		if already_used:
			continue
		var normalized_name := normalize(name)
		if role.begins_with("Left") and not normalized_name.contains("left"):
			continue
		if role.begins_with("Right") and not normalized_name.contains("right"):
			continue
		if rests[parent_index].origin.distance_to(rests[index].origin) <= 0.00001:
			continue
		candidates.append(name)
	return candidates[0] if candidates.size() == 1 else ""

static func _parent_role(role: String) -> String:
	for parent in HumanoidMap.DIRECTION_CHILDREN:
		if String(HumanoidMap.DIRECTION_CHILDREN[parent]) == role:
			return String(parent)
	var special := {"LeftShoulder":"UpperChest", "RightShoulder":"UpperChest", "LeftUpperLeg":"Hips", "RightUpperLeg":"Hips"}
	return String(special.get(role, ""))

static func _is_descendant(skeleton: Skeleton3D, child_name: String, ancestor_name: String) -> bool:
	var index := skeleton.find_bone(child_name)
	var ancestor := skeleton.find_bone(ancestor_name)
	while index >= 0:
		if index == ancestor:
			return true
		index = skeleton.get_bone_parent(index)
	return false

static func _global_rests(skeleton: Skeleton3D) -> Array[Transform3D]:
	return Geometry.global_rests(skeleton)

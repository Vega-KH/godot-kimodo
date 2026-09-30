class_name KimodoRigCandidateMatcher
extends RefCounted

const HumanoidMap := preload("res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd")
const Profile := preload("res://addons/kimodo_motion/retargeting/kimodo_rig_profile.gd")
const RestOrientation := preload("res://addons/kimodo_motion/retargeting/rest_orientation.gd")

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
		var row := {"role": role, "target": "", "confidence": "unmatched", "evidence": "No reliable candidate", "required": role not in Profile.OPTIONAL_ROLES, "conflict": false}
		if skeleton.find_bone(role) >= 0:
			row.merge({"target": role, "confidence": "high", "evidence": "Exact Godot humanoid name"}, true)
		else:
			var key := normalize(role)
			if normalized.has(key) and normalized[key].size() == 1:
				row.merge({"target": normalized[key][0], "confidence": "high", "evidence": "Normalized name after namespace/prefix stripping"}, true)
			else:
				var alias := _alias_for(role)
				if normalized.has(alias) and normalized[alias].size() == 1:
					row.merge({"target": normalized[alias][0], "confidence": "high", "evidence": "Curated Mixamo alias with side and chain semantics"}, true)
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
	return {"rows": suggestions, "root_motion_policy": root_policy}

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

static func diagnose(skeleton: Skeleton3D, mapping: Dictionary, root_policy: String) -> Array[String]:
	var issues: Array[String] = []
	for side in ["Left", "Right"]:
		for role in mapping:
			if String(role).begins_with(side) and normalize(String(mapping[role])).contains(("right" if side == "Left" else "left")):
				issues.append("%s is assigned to the wrong side bone %s" % [role, mapping[role]])
	var created := Profile.create(mapping, NodePath("."), skeleton, root_policy)
	if not created["ok"]:
		issues.append(created["message"])
		return issues
	for pair in [["Hips", "Spine"], ["Spine", "Chest"], ["Chest", "UpperChest"], ["UpperChest", "Neck"], ["Neck", "Head"], ["LeftUpperArm", "LeftLowerArm"], ["LeftLowerArm", "LeftHand"], ["RightUpperArm", "RightLowerArm"], ["RightLowerArm", "RightHand"], ["LeftUpperLeg", "LeftLowerLeg"], ["LeftLowerLeg", "LeftFoot"], ["RightUpperLeg", "RightLowerLeg"], ["RightLowerLeg", "RightFoot"]]:
		if mapping.has(pair[0]) and mapping.has(pair[1]) and not _is_descendant(skeleton, String(mapping[pair[1]]), String(mapping[pair[0]])):
			issues.append("%s must descend from %s" % [pair[1], pair[0]])
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
	for hand in ["LeftHand", "RightHand"]:
		var frame: Dictionary = HumanoidMap.ORIENTATION_FRAMES[hand]
		if not mapping.has(hand) or not mapping.has(frame["forward"]) or not mapping.has(frame["lateral_from"]) or not mapping.has(frame["lateral_to"]):
			continue
		var result := RestOrientation.anatomical_frame(skeleton, rests, mapping[hand], mapping[frame["forward"]], mapping[frame["lateral_from"]], mapping[frame["lateral_to"]])
		if not result["ok"]:
			issues.append("%s" % result["message"])
	return issues

static func normalize(name: String) -> String:
	var value := name.to_lower().replace("mixamorig", "")
	var result := ""
	for character in value:
		if character >= "a" and character <= "z" or character >= "0" and character <= "9":
			result += character
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
	var rests: Array[Transform3D] = []
	rests.resize(skeleton.get_bone_count())
	for index in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(index)
		rests[index] = skeleton.get_bone_rest(index) if parent < 0 else rests[parent] * skeleton.get_bone_rest(index)
	return rests

class_name KimodoRigCandidateMatcher
extends RefCounted

const HumanoidMap := preload("res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd")
const Profile := preload("res://addons/kimodo_motion/retargeting/kimodo_rig_profile.gd")
const Geometry := preload("res://addons/kimodo_motion/retargeting/rig_geometry.gd")
const Names := preload("res://addons/kimodo_motion/retargeting/rig_name_hints.gd")

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
	var hints := Names.inspect(skeleton)
	var influences := _skin_influences(skeleton)
	for bone in hints:
		hints[bone]["skin_influence"] = influences.has(bone)
	var suggestions := {}
	for role in roles:
		var row := {"role": role, "target": "", "confidence": "unmatched", "evidence": "Required role needs a manual mapping" if role in Profile.REQUIRED_BODY else "Optional role may be intentionally left unmapped", "required": role in Profile.REQUIRED_BODY or role == "Root", "conflict": false, "candidates": _name_candidates(role, hints)}
		_choose(row)
		suggestions[role] = row
	_resolve_pelvis_and_root(skeleton, suggestions)
	_rank_by_chains(skeleton, suggestions)
	_review_chains(skeleton, suggestions)
	# A conservative structural tier is useful on regular rigs with poor names.
	# It suggests only a unique, non-degenerate child on the correct side and
	# labels the result low-confidence so artist review remains explicit.
	for _pass in 3:
		for role in roles:
			if not String(suggestions[role]["target"]).is_empty():
				continue
			var candidate := _structural_candidate(skeleton, role, suggestions)
			if not candidate.is_empty():
				# Do not structurally override a known ambiguous name match.
				if not suggestions[role]["candidates"].is_empty():
					continue
				suggestions[role].merge({"target": candidate, "confidence": "low", "evidence": "Unique side + hierarchy + non-degenerate rest-axis candidate; review required"}, true)
	_review_chains(skeleton, suggestions)
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
	return Names.normalize(name)

static func _aliases_for(role: String) -> Array[String]:
	var result: Array[String] = [_alias_for(role)]
	var core := {"Hips": "pelvis", "Spine": "spine01", "Chest": "spine02", "UpperChest": "spine03", "Neck": "neck01"}
	if core.has(role):
		result.append(core[role])
	var extra := {"Root":["traj", "ctraj", "trajectory", "rootjoint"], "Hips":["hip"], "UpperChest":["ribcage"], "Neck":["neck1"]}
	for alias in extra.get(role, []):
		result.append(alias)
	for side in ["Left", "Right"]:
		var lower: String = side.to_lower()
		var body := {"Shoulder": "clavicle", "UpperArm": "upperarm", "LowerArm": "lowerarm", "Hand": "hand", "UpperLeg": "thigh", "LowerLeg": "calf", "Foot": "foot", "Toes": "ball", "Eye": "eye"}
		for part in body:
			if role == side + part:
				result.append(lower + body[part])
		var conventions := {"Shoulder":["clavic"], "UpperArm":["armstretch", "armupper"], "LowerArm":["forearmstretch", "armlower"], "UpperLeg":["thighstretch", "legupper"], "LowerLeg":["legstretch", "leglower"], "Toes":["toes", "toe"]}
		for part in conventions:
			if role == side + part:
				for alias in conventions[part]:
					result.append(lower + alias)
		for digit in DIGITS:
			for joint in DIGITS[digit].size():
				if role == side + digit + DIGITS[digit][joint]:
					result.append(lower + String(digit).to_lower() + "%02d" % (joint + 1))
					result.append(lower + ("pinky" if digit == "Little" else String(digit).to_lower()) + str(joint + 1))
					# Some rigs retain an extra finger-base bone; the numbered
					# phalanges remain the animation roles, not that helper.
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

static func _name_candidates(role: String, hints: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var aliases := _aliases_for(role)
	for bone in hints:
		var hint: Dictionary = hints[bone]
		var score := 0
		var evidence := ""
		if bone == role:
			score = 100
			evidence = "Exact Godot humanoid name"
		else:
			for key_index in hint["keys"].size():
				var key: String = hint["keys"][key_index]
				var matched := 95 if key == normalize(role) else (85 if key in aliases else 0)
				if key_index > 0:
					matched -= 25
				if matched > score:
					score = matched
					evidence = "Normalized name / curated Mixamo, sided or chain alias"
					if key_index > 0:
						evidence += "; exporter suffix/wrapper interpreted, original number preserved"
		if score > 0:
			if hint.get("skin_influence", false):
				evidence += "; sampled mesh-weight influence"
			result.append({"target": bone, "score": score, "eligible": not hint["decoy"], "evidence": evidence + ("; control/twist/end marker: manual review only" if hint["decoy"] else "")})
	return result

static func _skin_influences(skeleton: Skeleton3D) -> Dictionary:
	# Informational only: a bounded positive-weight sample cannot prove that an
	# unobserved bone is a control. Roots/helpers often correctly have no weights.
	var found := {}
	var scope := skeleton.owner if skeleton.owner != null else skeleton.get_parent()
	if scope == null:
		return found
	for node in scope.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.skin == null or mesh.mesh == null or mesh.get_node_or_null(mesh.skeleton) != skeleton:
			continue
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
				continue
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if bones.size() != weights.size():
				continue
			var stride := maxi(1, bones.size() / 10000)
			for offset in range(0, bones.size(), stride):
				var bind := bones[offset]
				if weights[offset] <= 0.00001 or bind < 0 or bind >= mesh.skin.get_bind_count():
					continue
				var name := mesh.skin.get_bind_name(bind)
				var index := skeleton.find_bone(name) if not name.is_empty() else mesh.skin.get_bind_bone(bind)
				if index >= 0 and index < skeleton.get_bone_count():
					found[String(skeleton.get_bone_name(index))] = true
	return found

static func _choose(row: Dictionary) -> void:
	row["candidates"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["eligible"] != b["eligible"]: return a["eligible"]
		if a["score"] != b["score"]: return a["score"] > b["score"]
		return a["target"] < b["target"]
	)
	row["target"] = ""
	row["confidence"] = "unmatched"
	var eligible: Array[Dictionary] = []
	for candidate in row["candidates"]:
		if candidate["eligible"]:
			eligible.append(candidate)
	if eligible.is_empty():
		if not row["candidates"].is_empty():
			row["evidence"] = "No safe automatic match. " + row["candidates"][0]["evidence"]
		return
	if eligible.size() > 1 and eligible[0]["score"] < 100 and eligible[0]["score"] - eligible[1]["score"] < 10:
		row["confidence"] = "ambiguous"
		row["evidence"] = "Similar candidates %s / %s; choose manually after checking the chain." % [eligible[0]["target"], eligible[1]["target"]]
		return
	var best: Dictionary = eligible[0]
	row["target"] = best["target"]
	row["confidence"] = "high" if best["score"] >= 85 else ("medium" if best["score"] >= 65 else "low")
	row["evidence"] = best["evidence"]

static func _resolve_pelvis_and_root(skeleton: Skeleton3D, rows: Dictionary) -> void:
	var anchors: Array[String] = []
	for role in ["Spine", "Chest", "UpperChest"]:
		if not String(rows[role]["target"]).is_empty():
			anchors.append(rows[role]["target"])
			break
	for role in ["LeftUpperLeg", "RightUpperLeg"]:
		if not String(rows[role]["target"]).is_empty():
			anchors.append(rows[role]["target"])
	if anchors.size() == 3:
		var common := skeleton.get_bone_parent(skeleton.find_bone(anchors[0]))
		while common >= 0:
			var bone := String(skeleton.get_bone_name(common))
			if Geometry.descendant(skeleton, anchors[1], bone) and Geometry.descendant(skeleton, anchors[2], bone):
				for candidate in rows["Hips"]["candidates"]:
					for anchor in anchors:
						if not Geometry.descendant(skeleton, anchor, candidate["target"]):
							candidate["eligible"] = false
							candidate["evidence"] += "; not ancestor of torso and both thigh chains"
				if String(rows["Hips"]["target"]) != bone:
					rows["Hips"]["candidates"].append({"target": bone, "score": 55, "eligible": true, "evidence": "Nearest common ancestor of torso and both thighs; pelvis/helper candidate, review required"})
				_choose(rows["Hips"])
				break
			common = skeleton.get_bone_parent(common)
	var hips := String(rows["Hips"]["target"])
	if not hips.is_empty():
		for candidate in rows["Root"]["candidates"]:
			if not Geometry.descendant(skeleton, hips, candidate["target"]):
				candidate["eligible"] = false
				candidate["evidence"] += "; pelvis or non-ancestor, not a separate motion root"
		_choose(rows["Root"])

static func _rank_by_chains(skeleton: Skeleton3D, rows: Dictionary) -> void:
	# Compare against the same snapshot, not earlier decisions in this pass.
	var targets := mapping_from_rows(rows)
	var rests := Geometry.global_rests(skeleton)
	for role in rows:
		for candidate in rows[role]["candidates"]:
			if not candidate["eligible"]:
				continue
			for chain in Profile.semantic_chains():
				var position: int = chain.find(role)
				if position < 0:
					continue
				for ancestor in chain.slice(0, position):
					if targets.has(ancestor) and not Geometry.descendant(skeleton, candidate["target"], targets[ancestor]):
						candidate["eligible"] = false
						candidate["evidence"] += "; outside mapped %s ancestor chain" % ancestor
					elif targets.has(ancestor) and rests[skeleton.find_bone(candidate["target"])].origin.distance_to(rests[skeleton.find_bone(targets[ancestor])].origin) <= 0.00001:
						candidate["eligible"] = false
						candidate["evidence"] += "; colocated with mapped %s (zero-length segment); omit an optional helper or choose distinct joints" % ancestor
		_choose(rows[role])

static func _review_chains(skeleton: Skeleton3D, rows: Dictionary) -> void:
	# Gather every conflicting endpoint before clearing rows, so traversal order
	# cannot turn a known mismatch into a confident suggestion.
	var rejected := {}
	for chain in Profile.semantic_chains():
		var previous := ""
		for role in chain:
			if String(rows[role]["target"]).is_empty():
				continue
			if not previous.is_empty():
				var parent: String = rows[previous]["target"]
				var child: String = rows[role]["target"]
				if not Geometry.descendant(skeleton, child, parent):
					var reason := "%s ('%s') does not descend from %s ('%s'); check their actual parent chain" % [role, child, previous, parent]
					rejected[role] = reason
			previous = role
	for role in rejected:
		for candidate in rows[role]["candidates"]:
			if candidate["target"] == rows[role]["target"]:
				candidate["eligible"] = false
				candidate["evidence"] += "; " + rejected[role]
		rows[role]["target"] = ""
		rows[role]["confidence"] = "review"
		rows[role]["evidence"] = rejected[role]

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
	for row in rows.values():
		if row["conflict"]:
			row["target"] = ""
			row["confidence"] = "review"
			row["evidence"] = "Candidate overlaps another role; choose distinct bones manually. " + row["evidence"]

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
		if Names._decoy(name):
			continue
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

class_name KimodoHumanoidRigProfile
extends RefCounted

const HumanoidMap := preload(
	"res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd"
)

const OPTIONAL_CANONICAL_BONES := ["LeftEye", "RightEye", "Jaw"]

var skeleton_path := NodePath()
var canonical_to_target := {}
var target_to_canonical := {}


static func exact_names(skeleton: Skeleton3D, path: NodePath) -> Dictionary:
	if skeleton == null:
		return {"ok": false, "message": "Character target has no Skeleton3D"}
	if skeleton.find_bone("Root") < 0:
		return {"ok": false, "message": "Character skeleton is missing required bone Root"}
	var mapping := {"Root": "Root"}
	for canonical_name in HumanoidMap.REQUIRED_TARGETS:
		if skeleton.find_bone(canonical_name) >= 0:
			mapping[String(canonical_name)] = String(canonical_name)
		elif String(canonical_name) not in OPTIONAL_CANONICAL_BONES:
			return {
				"ok": false,
				"message": "Character skeleton is missing required bone %s" % canonical_name,
			}
	return create(mapping, path, skeleton)


static func create(mapping: Dictionary, path: NodePath, skeleton: Skeleton3D) -> Dictionary:
	var profile := new()
	profile.skeleton_path = path
	for canonical_name in mapping:
		var target_name := String(mapping[canonical_name])
		if target_name.is_empty() or skeleton.find_bone(target_name) < 0:
			return {
				"ok": false,
				"message": "Rig profile target bone %s does not exist" % target_name,
			}
		if profile.target_to_canonical.has(target_name):
			return {
				"ok": false,
				"message": "Rig profile maps target bone %s more than once" % target_name,
			}
		profile.canonical_to_target[String(canonical_name)] = target_name
		profile.target_to_canonical[target_name] = String(canonical_name)
	for required_name in ["Root", "Hips"]:
		if not profile.canonical_to_target.has(required_name):
			return {
				"ok": false,
				"message": "Rig profile is missing required semantic bone %s" % required_name,
			}
	return {"ok": true, "profile": profile}


func target_for(canonical_name: StringName) -> StringName:
	return StringName(canonical_to_target.get(String(canonical_name), ""))


func canonical_for(target_name: StringName) -> StringName:
	return StringName(target_to_canonical.get(String(target_name), ""))


func rotation_targets() -> Array[StringName]:
	var result: Array[StringName] = []
	for canonical_name in HumanoidMap.REQUIRED_TARGETS:
		if canonical_to_target.has(String(canonical_name)):
			result.append(canonical_name)
	return result

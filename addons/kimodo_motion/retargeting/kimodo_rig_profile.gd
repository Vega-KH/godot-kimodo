@tool
class_name KimodoRigProfile
extends Resource

const SCHEMA_VERSION := 1
const ROOT_SEPARATE := "separate_root"
const ROOT_HIPS_ONLY := "hips_only"
const OPTIONAL_ROLES := ["LeftEye", "RightEye", "Jaw"]
const HumanoidMap := preload("res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd")

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

var target_to_canonical: Dictionary = {}

static func exact_names(skeleton: Skeleton3D, path: NodePath) -> Dictionary:
	if skeleton == null:
		return _error("Character target has no Skeleton3D")
	if skeleton.find_bone("Root") < 0:
		return _error("Character skeleton is missing required bone Root")
	var mapping := {"Root": "Root"}
	for role in HumanoidMap.REQUIRED_TARGETS:
		if skeleton.find_bone(role) >= 0:
			mapping[String(role)] = String(role)
		elif String(role) not in OPTIONAL_ROLES:
			return _error("Character skeleton is missing required bone %s" % role)
	return create(mapping, path, skeleton, ROOT_SEPARATE)

static func create(mapping: Dictionary, path: NodePath, skeleton: Skeleton3D, root_policy := ROOT_SEPARATE, scale_policy := "none") -> Dictionary:
	var profile := KimodoRigProfile.new()
	profile.skeleton_path = path
	profile.root_motion_policy = root_policy
	profile.translation_scale_policy = scale_policy
	profile.canonical_to_target = mapping.duplicate(true)
	for optional_role in OPTIONAL_ROLES:
		if not mapping.has(optional_role) or String(mapping[optional_role]).is_empty():
			profile.ignored_optional_roles.append(optional_role)
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
	var required: Array[String] = ["Hips"]
	if root_motion_policy == ROOT_SEPARATE:
		required.push_front("Root")
	for role in HumanoidMap.REQUIRED_TARGETS:
		if String(role) not in OPTIONAL_ROLES:
			required.append(String(role))
	var used := {}
	for role in canonical_to_target:
		var target := String(canonical_to_target[role])
		if target.is_empty() or skeleton.find_bone(target) < 0:
			return "Rig profile target bone %s does not exist" % target
		if used.has(target):
			return "Rig profile maps target bone %s more than once" % target
		used[target] = String(role)
	for role in required:
		if not canonical_to_target.has(role) or String(canonical_to_target[role]).is_empty():
			return "Rig profile is missing required semantic bone %s" % role
	if root_motion_policy == ROOT_HIPS_ONLY and canonical_to_target.has("Root"):
		return "A Hips-is-root profile must not map a separate Root"
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
	var rests: Array[Transform3D] = []
	rests.resize(skeleton.get_bone_count())
	for index in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(index)
		rests[index] = skeleton.get_bone_rest(index) if parent < 0 else rests[parent] * skeleton.get_bone_rest(index)
	return rests

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}

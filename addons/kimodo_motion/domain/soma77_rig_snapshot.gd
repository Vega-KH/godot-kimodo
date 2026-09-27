@tool
class_name KimodoSoma77RigSnapshot
extends Resource

const SCHEMA_VERSION := 1
const Contract := preload("res://addons/kimodo_motion/domain/soma77_contract.gd")

@export var schema_version := SCHEMA_VERSION
@export var contract_id := Contract.CONTRACT_ID
@export var contract_version := Contract.CONTRACT_VERSION
@export var signature := ""
@export var skeleton_transform := Transform3D.IDENTITY
@export var bone_names := PackedStringArray()
@export var parent_indices := PackedInt32Array()
@export var local_rests: Array[Transform3D] = []


static func capture(skeleton: Skeleton3D) -> KimodoSoma77RigSnapshot:
	if skeleton == null or skeleton.get_bone_count() != Contract.JOINT_NAMES.size():
		return null
	var snapshot := KimodoSoma77RigSnapshot.new()
	snapshot.skeleton_transform = skeleton.transform
	for index in skeleton.get_bone_count():
		if skeleton.get_bone_name(index) != Contract.JOINT_NAMES[index]:
			return null
		var rest := skeleton.get_bone_rest(index)
		if not rest.is_finite():
			return null
		snapshot.bone_names.append(String(skeleton.get_bone_name(index)))
		snapshot.parent_indices.append(skeleton.get_bone_parent(index))
		snapshot.local_rests.append(rest)
	snapshot.signature = snapshot.compute_signature()
	return snapshot


func validation_error() -> String:
	if schema_version != SCHEMA_VERSION:
		return "Unsupported SOMA rig snapshot schema %d." % schema_version
	if contract_id != Contract.CONTRACT_ID or contract_version != Contract.CONTRACT_VERSION:
		return "The archived source rig is not SOMA-77."
	if (
		bone_names.size() != Contract.JOINT_NAMES.size()
		or parent_indices.size() != bone_names.size()
		or local_rests.size() != bone_names.size()
	):
		return "The archived SOMA rig snapshot is incomplete."
	for index in bone_names.size():
		if bone_names[index] != Contract.JOINT_NAMES[index]:
			return "The archived SOMA joint order is invalid at %d." % index
		if parent_indices[index] >= index or parent_indices[index] < -1:
			return "The archived SOMA hierarchy is invalid at %s." % bone_names[index]
		if not local_rests[index].is_finite():
			return "The archived SOMA rest pose is non-finite at %s." % bone_names[index]
	if signature.is_empty() or signature != compute_signature():
		return "The archived SOMA rig signature does not match its contents."
	return ""


func instantiate_skeleton() -> Skeleton3D:
	if not validation_error().is_empty():
		return null
	var skeleton := Skeleton3D.new()
	skeleton.name = "Soma77Skeleton"
	skeleton.transform = skeleton_transform
	for index in bone_names.size():
		skeleton.add_bone(bone_names[index])
		skeleton.set_bone_parent(index, parent_indices[index])
		skeleton.set_bone_rest(index, local_rests[index])
		skeleton.set_bone_pose(index, local_rests[index])
	return skeleton


func compute_signature() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(schema_version))
	context.update(contract_id.to_utf8_buffer())
	context.update(var_to_bytes(contract_version))
	context.update(var_to_bytes(skeleton_transform))
	for index in bone_names.size():
		context.update(bone_names[index].to_utf8_buffer())
		context.update(var_to_bytes(parent_indices[index]))
		context.update(var_to_bytes(local_rests[index]))
	return context.finish().hex_encode()

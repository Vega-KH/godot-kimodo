@tool
class_name KimodoPoseAsset
extends Resource

const SCHEMA_VERSION := 1

@export var schema_version := SCHEMA_VERSION
@export var pose_id := ""
@export var title := "Untitled pose"
@export var rig_signature := ""
@export var bone_names := PackedStringArray()
@export var parent_names := PackedStringArray()
@export var local_rests: Array[Transform3D] = []
@export var sample: Animation
@export var provenance: Dictionary = {}


static func signature_for(skeleton: Skeleton3D) -> String:
	var names := PackedStringArray()
	var parents := PackedStringArray()
	var rests: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(index))
		var parent := skeleton.get_bone_parent(index)
		parents.append(skeleton.get_bone_name(parent) if parent >= 0 else "")
		rests.append(skeleton.get_bone_rest(index))
	return _signature(names, parents, rests)


static func _signature(names: PackedStringArray, parents: PackedStringArray, rests: Array[Transform3D]) -> String:
	# Name-based ordering makes an equivalent reindexed skeleton compatible.
	var entries := {}
	for index in names.size():
		entries[String(names[index])] = [parents[index], rests[index]]
	var sorted_names := names.duplicate()
	sorted_names.sort()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for name_value in sorted_names:
		context.update(var_to_bytes([name_value, entries[name_value]]))
	return context.finish().hex_encode()


func validation_error() -> String:
	if schema_version != SCHEMA_VERSION:
		return "Unsupported pose schema %d." % schema_version
	if pose_id.is_empty() or title.strip_edges().is_empty():
		return "Pose identity and title are required."
	if bone_names.is_empty() or parent_names.size() != bone_names.size() or local_rests.size() != bone_names.size():
		return "Pose rig metadata is incomplete."
	var seen := {}
	for index in bone_names.size():
		var bone := String(bone_names[index])
		if bone.is_empty() or seen.has(bone) or bone.contains(":") or bone.contains("/"):
			return "Pose rig contains an invalid or duplicate bone name."
		seen[bone] = true
		if not local_rests[index].is_finite():
			return "Pose rest transform is non-finite at %s." % bone
	for index in bone_names.size():
		var parent := String(parent_names[index])
		if not parent.is_empty() and (not seen.has(parent) or parent == bone_names[index]):
			return "Pose rig has an invalid parent."
	for index in bone_names.size():
		var ancestors := {}
		var current := String(bone_names[index])
		while not current.is_empty():
			if ancestors.has(current):
				return "Pose rig hierarchy contains a cycle."
			ancestors[current] = true
			current = parent_names[bone_names.find(current)]
	if rig_signature.is_empty() or rig_signature != _signature(bone_names, parent_names, local_rests):
		return "Pose rig signature does not match its metadata."
	if sample == null or sample.get_track_count() == 0 or sample.loop_mode != Animation.LOOP_NONE:
		return "Pose must contain a non-looping animation sample."
	var channels := {}
	for track in sample.get_track_count():
		var kind := sample.track_get_type(track)
		if kind not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			return "Pose contains a non-bone transform track."
		var path := sample.track_get_path(track)
		if path.get_name_count() != 1 or path.get_name(0) != "." or path.get_subname_count() != 1:
			return "Pose tracks must use skeleton-relative bone paths."
		var bone := String(path.get_subname(0))
		var channel := "%s:%d" % [bone, kind]
		if not seen.has(bone) or channels.has(channel):
			return "Pose contains an unknown or duplicate bone channel."
		channels[channel] = true
		if not sample.track_is_enabled(track) or sample.track_get_key_count(track) != 1 or sample.track_get_key_time(track, 0) != 0.0:
			return "Each pose channel needs one enabled key at time zero."
		var value: Variant = sample.track_get_key_value(track, 0)
		if kind == Animation.TYPE_ROTATION_3D:
			if not value is Quaternion or not value.is_finite() or absf(value.length_squared() - 1.0) > 0.0001:
				return "Pose rotation must be a finite unit quaternion."
		elif not value is Vector3 or not value.is_finite():
			return "Pose channel must contain a finite Vector3."
	return ""


func compatibility_error(skeleton: Skeleton3D) -> String:
	var problem := validation_error()
	if not problem.is_empty():
		return problem
	if skeleton == null or signature_for(skeleton) != rig_signature:
		return "The destination skeleton has a different hierarchy or rest pose. Select the pose's rig."
	return ""
